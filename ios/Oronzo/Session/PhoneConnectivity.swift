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

    /// Whether there is something the watch should be showing.
    ///
    /// **Not "do I hold a live session"** — that was the bug. A relaunched app holds nothing, and
    /// answered accordingly: see `currentWatchMessage`, which reaches for the record the phone
    /// wrote down before falling back to "nothing is running".
    var hasActiveSession: Bool { currentWatchMessage != nil }

    /// What the watch should be showing, from the best source available — or `nil` when there is
    /// genuinely nothing.
    ///
    /// Two sources, in order. A session **in memory** is authoritative: it is the one actually
    /// ticking, and its message is built fresh on every call so an answer can never be stale.
    /// Failing that, the **record on disk** — which is the case that used to be answered wrongly,
    /// because "no session in memory" is not the same fact as "no session", and the app had no way
    /// to tell them apart.
    ///
    /// The record is advanced through the engine before it is sent, so answering from a file
    /// written minutes ago puts the watch where it should *be*, not where it was. That is safe
    /// rather than clever: the projection from a stale anchor and a fresh one agree, which
    /// `WatchProjectionTests` pins — so this can correct the wrist and can never rewind it.
    var currentWatchMessage: WatchMessage? {
        if let advertised { return advertised.currentMessage }

        guard let record = SessionRecordFile.load(), record.isPresentable(at: .now) else { return nil }
        return (record.advanced(to: .now) ?? record).message
    }

    /// The live session. `@ObservationIgnored` because it is a back-reference, not UI state.
    @ObservationIgnored private weak var advertised: (any AdvertisedSession)?

    /// What the watch has told us about itself, from the controls it sends.
    ///
    /// **Observable, because a mismatch has to be shown and a log is not a place.** `Log.debug`'s
    /// autoclosure is never evaluated in a release build (`docs/patterns.md`), so a diagnostic that
    /// lives only in the log does not exist on the phone this actually ships to.
    ///
    /// The two fields are deliberately separate. "We have never heard from the watch" and "the
    /// watch told us nothing about its version" look the same if you only keep the version — and
    /// they mean opposite things: the first must say nothing at all, the second is the stale-build
    /// signal, because a watch built before versioning existed announces itself by its silence.
    private(set) var hasHeardFromWatch = false
    private(set) var watchProtocolVersion: Int?

    /// What to tell the person holding the phone, if anything.
    ///
    /// `nil` until the watch has actually spoken. That matters: a banner on every workout that
    /// simply has not had a wrist raise yet would be noise, and noise is how a real warning gets
    /// ignored.
    ///
    /// **It fires on a version difference, which is broader than "the watch is broken", and that
    /// is a deliberate trade rather than an oversight.** A build from before versioning existed
    /// cannot describe itself, so its silence is the only signal there is — and silence cannot
    /// distinguish a stale watch that happens to still work (the wire has been compatible so far)
    /// from one that cannot read the phone at all, which is the failure `docs/runbook.md` records
    /// as costing hours. Warning on the broader condition costs a red line on the phone until the
    /// watch is rebuilt, once; missing it costs the failure the line exists to prevent. The copy is
    /// therefore a maintenance instruction rather than an alarm — it says what to do, not that the
    /// workout is in trouble, because it is not: the countdown on this phone is unaffected either
    /// way.
    var watchNote: String? {
        guard hasHeardFromWatch else { return nil }
        switch WireProtocol.mismatch(watchProtocolVersion) {
        case .some(.peerIsOlder):
            return "Your Watch app is out of date — run the OronzoWatch scheme"
        case .some(.peerIsNewer):
            return "Update the Oronzo app to match your Watch"
        case .none:
            return nil
        }
    }

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

    /// Answers the watch with the truth: the session's own message, or "nothing is running".
    /// Called when the watch asks, and when the link comes up.
    ///
    /// **This used to clear the watch on every cold launch.** It is called from
    /// `activationDidCompleteWith`, and a fresh process has no session in memory *by
    /// construction* — so the phone told the watch "nothing is running" every time it started,
    /// whether or not a workout was going. Reproduced on paired simulators: start a session, kill
    /// the phone, relaunch it, and the wrist goes from a counting-down workout to **"No workout"**
    /// inside a second, with the watch's controls dead behind it.
    ///
    /// Reaching for the record as well is the whole fix. The answer is now built from whatever the
    /// phone *knows* is running rather than from whatever it happens to be holding.
    func answer() {
        // Read once: `currentWatchMessage` touches the disk when there is no live session, and
        // the log line and the send must not be able to disagree about what was found.
        let message = currentWatchMessage
        Log.debug("answer: \(message == nil ? "nothing running" : "a session")")
        send(message ?? .sessionEnded)
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

        // **Every control is also a receipt**, so the watch's build is learnt without inventing a
        // message to ask for it. An older watch sends `requestState` — that control has existed
        // since the recovery was first written — but no version key, and arriving without one *is*
        // the stale-build signal. A newer watch sends its version alongside.
        let version = payload["protocolVersion"] as? Int

        Task { @MainActor in
            self.hasHeardFromWatch = true
            self.watchProtocolVersion = version
            if let note = self.watchNote { Log.debug("watch build mismatch: \(note)") }
            self.deliver(control)
        }
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
