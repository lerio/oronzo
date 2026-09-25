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

    // Removed: `nextSecond(after:)`, which returned the next whole second so the phone could be
    // woken to repaint its clock. The phone draws its countdown from a `TimelineView` now, so
    // nothing calls it and there is no second term in the phone's schedule any more. Deleted
    // rather than left in place, like the Lock Screen surface before it (`docs/decisions.md`): a
    // helper with no caller is an invitation to reintroduce the wake it was written for, and the
    // whole point of this file is that the wakes are counted.

    // MARK: - Whether to sleep, and for how long

    /// What a surface's wake loop should do next.
    ///
    /// **This is a rule rather than an `if`, because the failure it prevents is a battery one and
    /// battery failures do not announce themselves.** Both loops used to end by falling out of a
    /// `guard let … else { return }`: "nothing is due" and "nothing will ever be due again" reached
    /// the same answer by the same route. That happens to be correct today — every thing that moves
    /// a session on also restarts its loop — and it stops being correct the moment anyone makes
    /// "nothing is due" mean *wait a bit and look again*. That reads like an obvious improvement
    /// and it would put a finished workout's `DONE` screen on a timer for as long as it stayed up,
    /// on the largest battery cost the watch has.
    ///
    /// There are two answers, and the second one covers strictly more than it looks like it does:
    ///
    /// - `.at` — something can happen at this instant. Sleep until then.
    /// - `.rest` — **nothing more will be due from this session's own clock. Park the loop, and do
    ///   not wake again to check.** A rep interval is the obvious case: it has no length, so
    ///   nothing about it can be predicted and only a tap moves it on. But a paused session, a
    ///   *finished* session and no session at all land here too, and that is the important part —
    ///   a finished session must be as silent as an idle one, and the only thing that distinguishes
    ///   them is intent. Parking is right for all four because every one of them is moved on by
    ///   something outside the loop, and that thing restarts it: `WatchLink.apply` on every
    ///   snapshot, `SessionController.resume`/`advance`/`goBack`, `syncRuntimeAndCues` on a wrist
    ///   raise.
    ///
    /// A periodic re-check would therefore buy nothing even in principle: every deadline in a
    /// session is an absolute date, so a wake could only ever learn what the anchor already said.
    public enum Wake: Equatable, Sendable {
        /// Something can happen at this instant.
        case at(Date)
        /// Nothing is due, and nothing will be until something external moves the session.
        case rest
    }

    /// What the loop should do next, from wherever the session is.
    ///
    /// - Parameters:
    ///   - hasSession: whether there is a session at all. Without one nothing is ever due — this
    ///     is the watch before the phone has said anything, and the phone before it has started.
    public static func wake(
        after now: Date,
        end: Date?,
        isPaused: Bool,
        isFinished: Bool,
        hasSession: Bool
    ) -> Wake {
        guard hasSession, !isFinished else { return .rest }
        guard let next = nextEvent(after: now, end: end, isPaused: isPaused, isFinished: isFinished)
        else { return .rest }
        return .at(next)
    }
}
