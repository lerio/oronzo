import Foundation
import WatchKit

/// Milestone M0 probe.
///
/// The riskiest assumption in the project is that a watch app signed by a **free personal
/// team** can keep itself running through a workout. HealthKit is off the table (it fails
/// to sign on a personal team), so `WKExtendedRuntimeSession` is the only mechanism left —
/// and it silently fails if the Info.plist key is wrong, surfacing as
/// `.notApprovedToStartSession` rather than as a build error.
///
/// So before any real app code exists, this probe starts a real session and reports exactly
/// what the system did. If this doesn't reach `.running`, the Watch design changes.
@MainActor
@Observable
final class ExtendedRuntimeProbe: NSObject {

    enum Phase: String {
        case idle
        case starting
        case running
        case stopped
        case expired
        case resignedFrontmost
        case suppressed
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var detail = "Not started"
    private(set) var expirationDate: Date?
    private(set) var lastError: String?

    private var session: WKExtendedRuntimeSession?

    var isActive: Bool { phase == .running || phase == .starting }

    func start() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session

        phase = .starting
        detail = "start() called during app-active state"
        session.start()

        // Inspect immediately: a rejected session is `.invalid` right away.
        expirationDate = session.expirationDate
        if session.state == .invalid {
            phase = .failed
            detail = "start() rejected — session is .invalid"
        } else {
            detail = "start() returned, state=\(Self.describe(session.state))"
        }
    }

    func stop() {
        session?.invalidate()
        session = nil
        phase = .stopped
        detail = "Invalidated by the app"
        expirationDate = nil
    }

    /// An `WKExtendedRuntimeSession` can drive haptics itself — even when the app isn't
    /// frontmost. That is what lets a transition buzz your wrist with the phone on a bench.
    func fireTestHaptic() {
        session?.notifyUser(hapticType: .notification, repeatHandler: nil)
    }

    static func describe(_ state: WKExtendedRuntimeSessionState) -> String {
        switch state {
        case .notStarted: "notStarted"
        case .scheduled: "scheduled"
        case .running: "running"
        case .invalid: "invalid"
        @unknown default: "unknown(\(state.rawValue))"
        }
    }

    /// Applies a state change. Main-actor isolated, and takes only `Sendable` values so it
    /// can be reached from the non-isolated delegate callbacks.
    fileprivate func apply(_ phase: Phase, detail: String, expiration: Date? = nil, error: String? = nil) {
        self.phase = phase
        self.detail = detail
        self.expirationDate = expiration
        if let error { self.lastError = error }
    }

    fileprivate nonisolated static func interpret(
        _ reason: WKExtendedRuntimeSessionInvalidationReason
    ) -> (Phase, String) {
        switch reason {
        case .none:
            (.stopped, "Invalidated: none (app requested it)")
        case .expired:
            (.expired, "Invalidated: expired (1-hour cap reached)")
        case .resignedFrontmost:
            (.resignedFrontmost, "Invalidated: resignedFrontmost (another app took over)")
        case .suppressedBySystem:
            (.suppressed, "Invalidated: suppressedBySystem (battery/thermal)")
        case .sessionInProgress:
            (.failed, "Invalidated: sessionInProgress (one type per app)")
        case .error:
            (.failed, "Invalidated: error")
        @unknown default:
            (.failed, "Invalidated: unknown(\(reason.rawValue))")
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
//
// WatchKit calls these on the main thread, but the protocol is not main-actor isolated, so
// the methods are `nonisolated`. Under Swift 6 strict concurrency the delegate's
// `WKExtendedRuntimeSession` and `Error` arguments are *not* `Sendable` and must not be
// captured by the hop back to the main actor — so every value is read and reduced to plain
// `Sendable` data (Date/String/enum) on this side of the boundary first.

extension ExtendedRuntimeProbe: WKExtendedRuntimeSessionDelegate {

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let expiration = extendedRuntimeSession.expirationDate
        Task { @MainActor in
            self.apply(.running, detail: "RUNNING — extended runtime granted", expiration: expiration)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.apply(self.phase, detail: "Will expire imminently (approaching the 1-hour cap)")
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        let (phase, detail) = Self.interpret(reason)
        let message = error?.localizedDescription
        Task { @MainActor in
            self.apply(phase, detail: detail, error: message)
        }
    }
}
