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
/// **A waking with nothing to show gets the same four, and that was learned the hard way.** An
/// earlier pass reasoned that a wrist showing nothing has nothing to *correct*, so one attempt was
/// enough — the phone pushes on its own state changes anyway. That reasoning has a hole exactly
/// the size of the bug this file exists for: the state change that matters is the *start* of a
/// workout, it happens once, and if that one push is missed the next one is a whole interval away
/// (or, on a rep set, a tap away). The wrist then reads **"No workout"** for minutes, which is the
/// silent failure the whole link was rebuilt to remove. A single shot is not a recovery — the same
/// lesson this project already paid for once. And the cost of being wrong in this direction is
/// bounded: the extra attempts are spent only when the phone does not answer at all, which is a
/// phone that is not there.
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

    /// Every instant at which one waking should ask the phone, in order.
    ///
    /// The first attempt is **now** rather than a gap away — asking immediately is the entire
    /// point of the mechanism, and delaying it would leave the wrist wrong for seconds longer for
    /// no saving.
    public static func attempts(from now: Date) -> [Date] {
        // Walked as a running total rather than read off the array: `backoff` holds the *gaps*
        // between attempts, so the third attempt is 5 + 15 seconds out, not 15. Getting that
        // wrong shortens the retry by half a minute, which is the sort of thing only a test
        // notices — this one did.
        var elapsed: TimeInterval = 0
        var offsets: [TimeInterval] = [0]
        for gap in backoff {
            elapsed += gap
            offsets.append(elapsed)
        }
        return offsets.map { now.addingTimeInterval($0) }
    }
}
