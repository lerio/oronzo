import Foundation

/// A finished session that is worth telling Apple Health about — or nothing, when it was too
/// short to have been a workout.
///
/// **This decision lives in the core, not in the app, because it is the part worth proving.** The
/// `HKWorkout` that follows from it needs a device and a permission prompt; whether a session
/// clears the bar, and what the workout's dates are, do not. So the rule is a pure function with
/// no clock of its own — like `SessionSchedule` and `SessionPresentation`, the caller has the
/// time, this has the rule, and `swift test` settles it on macOS in a second.
///
/// ## Why three minutes
///
/// A session can be started by a mis-tap, and one can be started on purpose to look at the runner.
/// Neither is a workout, and a log that accepts them is a log you stop trusting. Three minutes is
/// comfortably past an accident and comfortably inside a real warm-up.
///
/// The bar is checked against `totalDuration`, which **excludes paused time**, and that is the
/// number the summary screen already shows as "time". So the rule agrees with what the session
/// itself claims to have been: a workout started and immediately paused, then abandoned ten
/// minutes later, is not a ten-minute workout and is not recorded as one.
///
/// ## What Health is told, and the one place this is imperfect
///
/// Only the two dates. HealthKit *derives* the workout's duration from them — `HKWorkout.duration`
/// is documented as the span adjusted by pause events — so there is no separate duration to hand
/// over, and the workout Health draws is the wall-clock span.
///
/// That span is deliberately the real one: a workout that ran from 09:00 to 09:30 belongs at
/// 09:00–09:30 on Health's timeline, whatever was paused inside it. The imperfection is that a
/// session with a long pause in it is therefore recorded as longer than the work it contained.
/// Removing it would mean carrying Oronzo's pauses across as `HKWorkoutEvent`s, and the engine
/// keeps `pausedTotal` as a running scalar rather than a list of intervals — so the information
/// needed to place them is not there. That is a change to `ExecutionEngine`, and it is not worth
/// making until this has been used enough to say the inaccuracy actually matters.
public struct RecordableWorkout: Equatable, Sendable {

    /// When the session really began, and when it really ended.
    public let startedAt: Date
    public let finishedAt: Date

    /// Sessions shorter than this are not workouts.
    public static let minimumDuration: TimeInterval = 180

    /// `nil` when this session should not become a workout.
    ///
    /// - Note: An **abandoned** session is recorded, deliberately. Ending a workout early is not
    ///   the same as not having done it, and a twenty-minute session stopped at minute twenty is
    ///   twenty minutes of exercise that Health should know about. Only a session too short to
    ///   have been anything, or one that never actually ended, is refused.
    public init?(completed: CompletedSession) {
        // A session that never closed is not a workout. `close(_:at:)` is the only thing that
        // produces a finished one, so this is a guard against a future caller handing over a
        // snapshot of a session that is still running — whose `finishedAt` is a fallback rather
        // than an ending.
        guard completed.status != .inProgress else { return nil }

        guard completed.totalDuration >= Self.minimumDuration else { return nil }

        self.startedAt = completed.startedAt
        self.finishedAt = completed.finishedAt
    }
}
