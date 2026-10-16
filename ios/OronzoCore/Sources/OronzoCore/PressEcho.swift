import Foundation

/// What the wrist shows in the moment after it has pressed a step control — **before** the phone
/// has said anything back.
///
/// The wrist's screen has never been able to move on its own for a rep interval: `WatchProjection`
/// ends its walk there ("nothing can be assumed about when a rep set ends"), so the only thing that
/// can change the screen is a snapshot from the phone. That makes a press a full round trip, and it
/// makes the wrist's responsiveness exactly the link's latency — where the phone's own screen is
/// local and instant. Reported from a workout as *"I tapped skip and it took a good 5-10 seconds
/// before it moved to the next exercise"*, against a phone that responded at once.
///
/// The round trip is not reliably fast, and that is by design rather than by accident. Both the
/// press and the answer travel a direct message only while the two apps consider each other
/// reachable, and `WCSession.isReachable` is an interdependent condition — the WatchKit extension
/// has to be running with high priority, and the phone's side additionally wants the extension's
/// own reachability to be true. When it is not, the press is queued for background delivery and the
/// answer is written to the **application context**, which Apple documents as sent "when the
/// opportunity arises, with the goal of having the data ready to use by the time the counterpart
/// wakes up". Neither is a real-time channel. This project's own runbook already records
/// `reachable=false` as the *normal* line in its phone logs.
///
/// So the wrist answers its own press, and the phone's next word replaces that answer. **This is
/// not the wrist becoming an authority.** The phone still owns the session: it applies the press,
/// it writes the record, it decides when the session ends, and its snapshot overrides this echo the
/// moment it arrives. What the wrist is doing is what it already does for elapsed time — predicting
/// from what it was told — except that what it is predicting here is the user's own command, issued
/// a moment ago on the wrist itself.
///
/// Three boundaries, each of them a decision rather than an omission:
///
/// - **Only the two step controls are echoed.** A pause is not, because a *false* pause stops the
///   wrist's clock while the phone runs the interval on: the wrist would sit frozen on something
///   the phone is counting through. A false skip only moves the wrist's screen, and the phone
///   catches up when the press lands. A finish is not echoed because a session's end is the
///   phone's to declare — the record, the summary, the history and the Health write all hang off it.
/// - **A press that would leave the interval list is not echoed at all.** `next` on the last
///   interval *finishes* the session in the engine, and `previous` at index 0 is the engine's
///   documented no-op. Both wait for the phone.
/// - **The echo is bounded** by `window`, measured from the press. Past it the wrist stops
///   pretending and shows the phone's truth again. The bound is the same order as `AskSchedule`'s
///   outer attempt: it is how long the wrist keeps asking before concluding the phone is not
///   listening.
///
/// A pure rule with no clock of its own, like `SessionClear`, `AskSchedule` and `WatchProjection`:
/// the caller has both times, this has the rule, and `swift test` proves it on macOS in a second.
public struct PressEcho: Equatable, Sendable {

    /// Which way through the interval list the press moves.
    ///
    /// Two cases rather than `WatchControl`, because three of that enum's five cases may not be
    /// echoed at all — see the boundaries above. A type that cannot hold them is a rule that cannot
    /// be forgotten.
    public enum Direction: Equatable, Sendable {
        case forward
        case backward
    }

    public let direction: Direction

    /// The state the phone would be in if this press had landed — built by the engine's own
    /// arithmetic rather than by an invention of this type's, so the two cannot disagree about what
    /// a press does. `PressEchoTests` pins them together for exactly that reason.
    public let state: SessionState

    /// When the press was made. What `window` is measured from.
    public let at: Date

    /// How long the wrist may stand on an unconfirmed press.
    ///
    /// **A minute, and the number is a bound rather than a measurement.** The echo's job is to
    /// cover a round trip that is late, and a late round trip here means the queued channel has
    /// not drained yet — seconds, not milliseconds. What it must also do is *stop*, because the one
    /// case it cannot distinguish from "late" is "the phone is gone", and a wrist showing a
    /// position the phone will never have is worse than one that moves on its own. A minute is
    /// about as long as `AskSchedule` keeps asking before it concludes the phone is not listening,
    /// which is the same question asked a different way.
    public static let window: TimeInterval = 60

    /// When the wrist gives the press up.
    public var expiresAt: Date { at.addingTimeInterval(Self.window) }

    /// Whether the phone has caught up — the same shape as `SessionClear.Decision`: a direction,
    /// not a sentence, because the caller is the one that has to phrase it.
    public enum Verdict: Equatable, Sendable {
        /// The phone's word is older than this press. Keep showing the echo.
        case hold
        /// The phone has accounted for it — or has said something that overrules it. Use the
        /// phone's state.
        case released
    }

    /// The echo a press earns, or `nil` when the press may not be echoed and must simply wait for
    /// the phone.
    ///
    /// - Parameters:
    ///   - control: what the wrist was asked to send.
    ///   - intervals: the plan as the phone last sent it. Never edited here — a load adjustment is
    ///     the phone's, and the wrist is only moving through the list.
    ///   - index: **where the wrist is showing the session now**, which is not necessarily where
    ///     the phone last said it was: a timed interval can have elapsed, and a previous echo can
    ///     still be standing. Earning from the displayed index rather than the phone's is what
    ///     makes two presses in quick succession move two intervals.
    ///   - isPaused: the phone is holding the clock. The echo copies this, because a press while
    ///     paused moves the position and nothing else — the engine's own rule.
    ///   - isFinished: the session is over, and nothing about it may be echoed.
    public static func earned(
        by control: WatchControl,
        intervals: [Interval],
        showing index: Int,
        isPaused: Bool,
        isFinished: Bool,
        now: Date
    ) -> PressEcho? {
        guard !isFinished, intervals.indices.contains(index) else { return nil }

        let direction: Direction
        let target: Int
        switch control {
        case .next:
            direction = .forward
            target = index + 1
        case .previous:
            direction = .backward
            target = index - 1
        // The three controls the wrist may not answer for itself, each for the reason the type's
        // documentation gives: a pause holds a clock this surface does not own, a finish is the
        // phone's alone to declare, and an ask is not a move at all.
        case .togglePause, .finish, .requestState:
            return nil
        }

        // One bounds check for both ends, which is also what refuses the two presses that leave the
        // list: `previous` at 0 lands on -1, and `next` on the last interval lands past the end —
        // where the engine does not move at all, it *finishes*.
        guard intervals.indices.contains(target) else { return nil }

        // The engine's arithmetic, mirrored: a running session anchors the new interval at `now`
        // from the interval's own duration, and a paused one holds the whole of it as a remainder
        // with no date at all. See `ExecutionEngine.advance` and `goBack`.
        let duration = intervals[target].duration
        return PressEcho(
            direction: direction,
            state: SessionState(
                currentIndex: target,
                isPaused: isPaused,
                isFinished: false,
                intervalEnd: isPaused ? nil : duration.map { now.addingTimeInterval($0) },
                remainingWhenPaused: isPaused ? duration : nil,
                finishedAt: nil
            ),
            at: now
        )
    }

    /// Whether the phone's last word settles this echo.
    ///
    /// Three ways it can, and the two that are not about position are the ones worth naming:
    ///
    /// - The phone has reached or passed the echoed index **in the direction the press went**. A
    ///   phone still *behind* an unconfirmed press is the ordinary case — the press is in flight —
    ///   and must not take the screen back.
    /// - The phone has **finished**, which ends every echo: the DONE screen is the phone's, and a
    ///   wrist still showing a mid-session interval in front of it would be wrong about the one
    ///   thing that matters at the end.
    /// - The phone's **pause state** differs from the echo's. A pause is the phone's word to hold
    ///   the clock, and it overrules a position the wrist is only holding on to: without this, a
    ///   press made while paused would keep the wrist frozen through a resume, counting nothing
    ///   while the phone counted the interval down.
    public func verdict(against phone: SessionState) -> Verdict {
        guard !phone.isFinished else { return .released }
        guard phone.isPaused == state.isPaused else { return .released }

        switch direction {
        case .forward:
            return phone.currentIndex >= state.currentIndex ? .released : .hold
        case .backward:
            return phone.currentIndex <= state.currentIndex ? .released : .hold
        }
    }
}
