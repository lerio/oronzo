import Foundation
import WatchKit

/// Keeps the watch app running through a session.
///
/// This is a **chosen** mechanism, not a forced one. HealthKit's `HKWorkoutSession` is the
/// documented choice for a workout app, and the reason once given here for not using it — that a
/// free personal team cannot sign HealthKit — **was wrong, and was never tested.** HealthKit signs
/// fine, and the phone records finished workouts to Apple Health.
///
/// The extended runtime session stays because it is what stops the app being suspended when the
/// wrist goes down, and replacing it is a large rewrite of the most failure-prone part of the
/// system. The cost is a hard one-hour ceiling: `physical-therapy` is the longest-lived type that
/// allows background execution. See `docs/decisions.md`.
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
    /// Whether a workout is running. This is the *intent*, and it outlives any individual
    /// session — which is exactly what was missing before.
    private var shouldBeRunning = false
    /// Confirmed by the delegate. A session object that was created but never reported started
    /// was refused, and must be replaced rather than reused.
    private var didStart = false
    private var restarts = 0

    /// Called by the view whenever a workout starts or ends.
    func setRunning(_ running: Bool) {
        let intentChanged = running != shouldBeRunning
        shouldBeRunning = running

        guard running else {
            stop()
            return
        }
        if intentChanged { restarts = 0 }

        // watchOS only grants an extended runtime session while the app is frontmost, and a
        // refused `start()` never calls back — so a session that was created but never confirmed
        // started would block every later attempt. Replace it instead of waiting on it.
        if session != nil, !didStart {
            discard()
        }

        startIfNeeded()
    }

    private func startIfNeeded() {
        guard shouldBeRunning, session == nil else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        isStopping = false
        didStart = false
        note = nil
        session.start()
    }

    private func stop() {
        isStopping = true
        session?.invalidate()
        session = nil
        didStart = false
        note = nil
        restarts = 0
    }

    /// Tears the session down without reporting it as an unexpected end.
    private func discard() {
        isStopping = true
        session?.invalidate()
        session = nil
        didStart = false
    }

    /// Retries after watchOS took the session away mid-workout.
    ///
    /// Without this the app is suspended on every wrist drop for the rest of the workout — and
    /// nothing else would ever bring it back, because `start()` used to be called only when the
    /// workout *began*. That failure is quiet and looks like several unrelated bugs: a stale
    /// always-on display, cue buzzes arriving late, the app vanishing to the watch face, and a
    /// general sluggishness from being suspended and resumed constantly.
    private func retryIfRunning() {
        guard shouldBeRunning, restarts < 3 else { return }
        restarts += 1

        Task { @MainActor in
            // A beat, so a session watchOS is in the middle of tearing down is not raced.
            try? await Task.sleep(for: .seconds(2))
            self.startIfNeeded()
        }
    }
}

extension WatchRuntime: WKExtendedRuntimeSessionDelegate {

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.didStart = true
            self.restarts = 0
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
            self.session = nil
            self.didStart = false
            // A deliberate `stop()` also lands here, a moment later. Reporting it would
            // resurrect a message about a session that is already over.
            guard !self.isStopping else {
                self.isStopping = false
                return
            }
            self.note = message
            self.retryIfRunning()
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
