import Foundation

/// When a surface must next wake up on its own.
///
/// **This exists because polling cost the watch its battery.** Both runners used to re-derive
/// "where am I now" on a fixed timer — the watch four times a second for haptics, the phone ten
/// times a second for its clock — and asked whether anything had changed. Almost every one of
/// those wakes found nothing: a minute-long interval has exactly four instants at which anything
/// can happen, and 236 at which it cannot. Because the watch keeps an extended runtime session
/// (the only way to stay alive on a free personal team), it does not get suspended while it spins,
/// so the whole of that waste was spent out of a battery the size of a thumbnail.
///
/// The same reasoning the engine already rests on makes the answer cheap: **every deadline here is
/// an absolute `Date`**, so the next instant at which the session can move is arithmetic rather
/// than something that has to be watched for. `WatchProjection` walks the interval list forward
/// from the phone's last anchor; this says when that walk will next change.
///
/// A pure function with no clock of its own, like `ExecutionEngine` and `SessionPresentation`: the
/// callers have the time, this has the rule, and `swift test` proves it on macOS in a second.
public enum SessionSchedule {

    /// The next instant at which a running session can change, or `nil` when nothing is due.
    ///
    /// - Parameters:
    ///   - end: the projected **absolute** end of the interval now on screen, or `nil` for a
    ///     rep interval — which has no length, so nothing about it can be predicted and only the
    ///     phone can move it on.
    ///   - isPaused: a paused session holds its clock, so nothing is due. (`end` is not `nil` while
    ///     paused — `WatchLink.position` turns the frozen remainder back into a date so the screen
    ///     can draw it — which is exactly why this has to be stated rather than inferred.)
    ///   - isFinished: nothing will ever be due again.
    ///
    /// The instants it returns are the interval's own end and, in the last three seconds, the
    /// boundaries at which `MeasurementFormat.clock(remaining:)` changes value. That function
    /// rounds **up**, so the countdown steps at exactly `end - 3`, `end - 2`, `end - 1` and `end`
    /// — the four moments the cue vocabulary was tuned against.
    ///
    /// Strictly after `now`: a boundary that has already arrived is not returned again. That is
    /// also what makes the callers safe — a wake that lands a hair early returns the same instant
    /// once more and no more, so a sleeping loop cannot spin.
    public static func nextEvent(
        after now: Date,
        end: Date?,
        isPaused: Bool,
        isFinished: Bool
    ) -> Date? {
        guard !isFinished, !isPaused, let end else { return nil }

        // Descending offsets, so this walks the candidates in *ascending* time and the first one
        // still ahead of us is the earliest. Written as a walk rather than a `min` because "which
        // countdown second are we in" is the question, and it reads as the list it is.
        for secondsBeforeEnd in [3.0, 2.0, 1.0, 0.0] {
            let candidate = end.addingTimeInterval(-secondsBeforeEnd)
            if candidate > now { return candidate }
        }
        return nil
    }

    /// The next whole second after `now` — the instants an `M:SS` clock changes.
    ///
    /// The phone draws its countdown from a stored remainder rather than a `TimelineView`, so it
    /// is the one surface that has to be woken to repaint a clock. This is what keeps that to once
    /// a second instead of ten times, which is what it was.
    public static func nextSecond(after now: Date) -> Date {
        let seconds = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: seconds.rounded(.down) + 1)
    }
}
