import Foundation

/// When the watch may ask the phone what it is running — **bounded, and deliberately so**.
///
/// The watch asks because every way a push can go missing is silent: the write lands before the
/// phone's link finished activating, a snapshot is overwritten in the single-slot application
/// context by a `sessionEnded` from a runner that is no longer live, or the watch resumes from a
/// wrist-drop suspension without being handed the context it missed. Asking is what turns each of
/// those from a permanently wrong screen into a recovery.
///
/// But asking is also the thing this project has already refused once. `docs/decisions.md` rules
/// out per-second traffic between the two apps, and the day the watch asks on a timer is the day
/// that rule is gone — a wrist-raise every thirty seconds with a one-second retry would be 3,600
/// messages an hour, which is precisely the poll the battery work removed. So the retry has a
/// **fixed size**: four attempts at most, the last one just over a minute after the first, and
/// then silence until the wrist comes up again and the watch has a reason to ask anew.
///
/// A pure function with no clock of its own, like `SessionSchedule` and `ExecutionEngine`: the
/// caller has the time, this has the rule, and `swift test` proves the bound on macOS.
public enum AskSchedule {

    /// The gaps between consecutive attempts, in seconds. Cumulative, so the attempts land at
    /// 0, 5, 20 and 65 seconds from the first.
    ///
    /// Widening rather than even, because the failures it covers have different timescales. A
    /// phone that is merely mid-activation answers within a second or two; one that is out of
    /// range is not going to answer at all, and the later attempts are there for the case in
    /// between — a phone that is briefly busy, or a `transferUserInfo` queue that has not drained
    /// yet.
    public static let backoff: [TimeInterval] = [5, 15, 45]

    /// How many attempts one waking is allowed, before the watch gives up and shows what it has.
    ///
    /// Four, and the number is the point: this multiplied by the wrist-raise rate is the whole
    /// worst-case message budget, and an hour with the phone never reachable costs at most 480
    /// messages against the 3,600 the poll this replaced would have spent.
    public static let attemptCount = backoff.count + 1

    /// The instant of attempt `attempt` (1-based), or `nil` when there are no attempts left.
    ///
    /// The first attempt is **now** rather than a gap away — asking immediately is the entire
    /// point of the mechanism, and delaying it would leave the wrist wrong for seconds longer for
    /// no saving.
    public static func attempt(_ attempt: Int, from now: Date) -> Date? {
        guard attempt >= 1, attempt <= attemptCount else { return nil }
        let elapsed = backoff.prefix(attempt - 1).reduce(0, +)
        return now.addingTimeInterval(elapsed)
    }
}
