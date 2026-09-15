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

    private(set) var isRunning = false
    private(set) var expiresAt: Date?
    private(set) var note: String?

    private var session: WKExtendedRuntimeSession?

    func start() {
        guard session == nil else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        // Must be called while the app is active, or it is refused.
        session.start()
        note = "Starting…"
    }

    func stop() {
        session?.invalidate()
        session = nil
        isRunning = false
        expiresAt = nil
        note = nil
    }
}

extension WatchRuntime: WKExtendedRuntimeSessionDelegate {

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Read on this side: the session object is not Sendable, so it cannot be captured
        // by the hop back to the main actor.
        let expiry = extendedRuntimeSession.expirationDate
        Task { @MainActor in
            self.isRunning = true
            self.expiresAt = expiry
            self.note = nil
        }
    }

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
            self.isRunning = false
            self.session = nil
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
