import Foundation
import WatchKit

/// Keeps the watch app running through a session.
///
/// This is the *only* mechanism available to us. HealthKit's workout session would be the
/// documented choice, but it cannot be signed by a free personal team, so an extended
/// runtime session is what stops the app being suspended when the wrist goes down.
/// `physical-therapy` is the longest-lived type that allows background execution, which
/// puts a hard one-hour ceiling on a session — see `docs/decisions.md`.
///
/// Verified on device at M0: the session is granted, the app survives a wrist drop.
@MainActor
@Observable
final class WatchRuntime: NSObject {

    /// Why the session stopped, when watchOS ended it rather than us. Shown on the watch:
    /// an extended runtime session that dies silently leaves a workout frozen on screen
    /// with nothing to explain why, and the user has no way to tell that from a bug.
    private(set) var note: String?

    private var session: WKExtendedRuntimeSession?
    /// Set while `stop()` tears the session down on purpose, so that the invalidation which
    /// follows it can be told apart from watchOS killing the session underneath us.
    private var isStopping = false

    func start() {
        guard session == nil else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        isStopping = false
        note = nil
        // Must be called while the app is active, or it is refused.
        session.start()
    }

    func stop() {
        isStopping = true
        session?.invalidate()
        session = nil
        note = nil
    }
}

extension WatchRuntime: WKExtendedRuntimeSessionDelegate {

    /// Required by the protocol, and deliberately empty: `start()` has already cleared the
    /// note, and nothing downstream needs the session object it hands over.
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.note = "Approaching the one-hour limit"
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        let message = Self.describe(reason)
        Task { @MainActor in
            self.session = nil
            // A deliberate `stop()` also lands here, a moment later. Reporting it would
            // resurrect a message about a session that is already over.
            guard !self.isStopping else {
                self.isStopping = false
                return
            }
            self.note = message
        }
    }

    nonisolated private static func describe(
        _ reason: WKExtendedRuntimeSessionInvalidationReason
    ) -> String {
        switch reason {
        case .expired: "One-hour limit reached — start a new session"
        case .suppressedBySystem: "Paused by the watch (low power)"
        case .resignedFrontmost: "Another app took over"
        case .sessionInProgress: "A session is already running"
        case .error: "Ended unexpectedly"
        case .none: "Ended"
        @unknown default: "Ended"
        }
    }
}
