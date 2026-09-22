import Foundation
import OronzoCore
import WatchConnectivity

/// The session driving the watch, as the link sees it.
///
/// A **reference**, rather than the bare `onControl` closure and `hasActiveSession` flag this
/// replaces, for one reason: the link has to be able to tell *which* session is talking to it.
/// A closure cannot be compared to anything, so a tear-down had to clear the handler and the
/// flag unconditionally — leaving nothing to stop one runner's tear-down from clearing the
/// watch on behalf of a *different, still-running* session, or from leaving the link convinced
/// a workout was in progress after the controller had gone. `advertise` / `resign` are what
/// make both impossible: a live session can only be displaced by another session, never by a
/// stale tear-down.
///
/// Held weakly by `PhoneConnectivity`, so a controller deallocated without ever calling
/// `teardown()` cannot leave the link believing a workout is still running — the phantom
/// session, from the other side.
@MainActor
protocol AdvertisedSession: AnyObject {
    /// The complete message the watch should be showing right now. Never partial: the
    /// application context is a single slot, so this is re-sent whole every time.
    var currentMessage: WatchMessage { get }
    /// Something the watch did — a step control, a pause, a finish.
    func handle(_ control: WatchControl)
}

/// The phone's half of the link to the watch.
///
/// Every message is written to the **application context** as well as sent directly. The
/// application context always holds the latest state and is delivered even when the watch
/// app is not running, so a glance at the wrist is never showing something stale; the
/// direct `sendMessage` is only there to make it feel instant when the watch is listening.
///
/// A single shared instance, because there is exactly one `WCSession` and it must be
/// activated early and stay activated.
@MainActor
@Observable
final class PhoneConnectivity: NSObject {

    static let shared = PhoneConnectivity()

    /// Whether a workout is running, as the link sees it — *derived from a live session*
    /// rather than remembered, which is what stops it from ever being stale.
    var hasActiveSession: Bool { advertised != nil }

    /// The live session. `@ObservationIgnored` because it is a back-reference, not UI state.
    @ObservationIgnored private weak var advertised: (any AdvertisedSession)?

    private var session: WCSession?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            Log.debug("WCSession is not supported on this device")
            return
        }
        guard session == nil else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// Claims the link for this session — **unless another session already holds it**.
    ///
    /// The refusal is the point. SwiftUI builds a `SessionRunner` on every re-render of the view
    /// presenting it, and each build constructs a `SessionController` that may outlive the build;
    /// before this check, such a controller could take the link and then answer the watch's
    /// controls from its own empty engine. That is a wrist which jumps back to the first exercise
    /// and then stops responding, with the phone entirely unaffected — see `pushState` for the
    /// other half of the guard.
    ///
    /// Claiming is idempotent, so a session that already holds the link can re-claim it. A
    /// session that has gone cannot block anything: the reference is weak, so a released
    /// controller leaves the link empty and the next real session starts normally.
    @discardableResult
    func claim(_ session: any AdvertisedSession) -> Bool {
        guard advertised == nil || advertised === session else { return false }
        advertised = session
        return true
    }

    /// Whether this session is the one the watch is hearing from. The licence to speak.
    func isAdvertising(_ session: any AdvertisedSession) -> Bool {
        advertised === session
    }

    /// Unregisters — **only if this session is still the live one** — and reports whether it
    /// was. The return value is the caller's licence to tell the watch the session has ended:
    /// a runner that has already been superseded by a newer one must not clear it.
    @discardableResult
    func resign(_ session: any AdvertisedSession) -> Bool {
        guard advertised === session else { return false }
        advertised = nil
        return true
    }

    /// Called when the app comes forward. If nothing is running, say so.
    ///
    /// Without this the watch keeps whatever it was last told, and the application context
    /// has no expiry — so a phone that was force-quit or crashed mid-workout leaves the
    /// watch happily showing a session that no longer exists. Cheap to send, and idempotent.
    func clearIfIdle() {
        guard !hasActiveSession else { return }
        send(.sessionEnded)
    }

    /// Answers the watch with the truth: the live session's own message, or "nothing is
    /// running". Called when the watch asks, and when the link comes up.
    ///
    /// This is what makes the link recoverable. The phone used to speak only when its state
    /// changed, so anything the watch missed stayed missed; now the watch can ask, and the
    /// answer is built from whatever is *actually* running rather than from a remembered flag.
    func answer() {
        Log.debug("answer: \(hasActiveSession ? "live session" : "nothing running")")
        send(advertised?.currentMessage ?? .sessionEnded)
    }

    func send(_ message: WatchMessage) {
        guard let session else {
            Log.debug("send skipped: no session")
            return
        }
        guard let data = try? WireCodec.encode(message) else {
            Log.debug("send skipped: encode failed")
            return
        }

        do {
            try session.updateApplicationContext(["message": data])
            // Logged on success as well as failure. Without this, "the phone wrote the context"
            // and "the phone never called send" are indistinguishable in the log — which is
            // the exact ambiguity that made a silent watch link so hard to diagnose.
            //
            // The case name only: interpolating `message` would dump the entire interval list.
            Log.debug("sent \(Self.kind(of: message)) (\(data.count) bytes); reachable=\(session.isReachable)")
        } catch {
            // Silently swallowing this is how a link "works" and delivers nothing.
            Log.debug("updateApplicationContext failed: \(error)")
        }

        // No error handler either way: the context above is the reliable path, and this is
        // only here to make a reachable watch update instantly rather than on next wake.
        if session.isReachable {
            session.sendMessage(["message": data], replyHandler: nil, errorHandler: nil)
        }
    }

    /// The message's case name, for logging. Deliberately not the payload.
    private static func kind(of message: WatchMessage) -> String {
        switch message {
        case .session: "session"
        case .sessionEnded: "sessionEnded"
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        // The three properties that decide whether any of this can work at all, so that a
        // workout that never reaches the watch can be told apart from one never started.
        Log.debug(
            "activation: state=\(activationState.rawValue) "
            + "reachable=\(session.isReachable) paired=\(session.isPaired) "
            + "watchAppInstalled=\(session.isWatchAppInstalled) "
            + "error=\(error.map { String(describing: $0) } ?? "none")"
        )

        // Speak again now that the link is up.
        //
        // Two holes this closes. A workout started *before* activation finished had its only
        // push dropped — `updateApplicationContext` throws while the session is not activated,
        // which the link logs and, until this line, never retried. And the phantom clear
        // depended on a `scenePhase` *change* to `.active`, which a cold launch does not
        // necessarily produce; activation always completes, so this is the hook that can be
        // relied on. Idempotent: it sends the truth, which at launch is "nothing running".
        Task { @MainActor in self.answer() }
    }

    // Required on iOS: the session goes inactive while the watch is switched, and has to be
    // re-activated or the link is silently dead afterwards.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    /// Controls sent while the watch could not reach the phone arrive here, later.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private nonisolated func handle(_ payload: [String: Any]) {
        guard let raw = payload["control"] as? String,
              let control = WatchControl(rawValue: raw)
        else { return }

        Task { @MainActor in self.deliver(control) }
    }

    /// Routes a control from the watch.
    ///
    /// `.requestState` is answered here rather than handed to the session, so that the watch
    /// gets a reply even when no session is running — which is precisely the moment it needs
    /// one, because that is the wrist showing "No workout" and hoping to be wrong.
    ///
    /// The other controls are logged, because this direction is otherwise invisible: from the
    /// wrist, a press that reached a session that was no longer live and a press that reached
    /// nothing at all look exactly the same, and that ambiguity is reported as "the next button
    /// stopped working".
    private func deliver(_ control: WatchControl) {
        guard control != .requestState else {
            answer()
            return
        }
        guard let advertised else {
            Log.debug("control \(control.rawValue): dropped, nothing running")
            return
        }
        Log.debug("control \(control.rawValue): handed to the live session")
        advertised.handle(control)
    }
}
