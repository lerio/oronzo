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

    private(set) var isReachable = false
    private var session: WCSession?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported(), session == nil else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func send(_ message: WatchMessage) {
        guard let session, let data = try? WireCodec.encode(message) else { return }

        try? session.updateApplicationContext(["message": data])

        if session.isReachable {
            session.sendMessage(["message": data], replyHandler: nil, errorHandler: nil)
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    // Required on iOS: the session goes inactive while the watch is switched, and has to be
    // re-activated or the link is silently dead afterwards.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
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
