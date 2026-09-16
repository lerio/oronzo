import Foundation
import OronzoCore
import WatchConnectivity

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

    /// Called when the watch asks for something. Set by `SessionController`.
    var onControl: (@MainActor (WatchControl) -> Void)?

    /// Whether this phone believes a workout is in progress. Read only by `clearIfIdle`.
    private(set) var hasActiveSession = false

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

    func setSessionActive(_ active: Bool) {
        hasActiveSession = active
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

        Task { @MainActor in self.onControl?(control) }
    }
}
