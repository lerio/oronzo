import XCTest
@testable import OronzoCore

/// The watch's retry, which has to be bounded because of what it would otherwise become.
///
/// Asking is how a watch that missed a push recovers, and it is the only mechanism there is — the
/// phone pushes and cannot know whether it was heard. But an unbounded retry is a message stream,
/// and `docs/decisions.md` rules per-second traffic between these two apps out for reasons that
/// cost a battery to learn. So the bound is the feature: these tests exist to make sure it stays
/// one if someone later decides the watch "should try a bit harder".
///
/// **And to make sure it is not cut short either**, which is the opposite temptation: an earlier
/// pass gave a wrist showing nothing a single attempt, on the reasoning that it had nothing to
/// correct. It has something to discover — a workout that just started — and one shot is not a
/// recovery. `testAWakingWithNothingOnScreenStillRetries` is that argument, pinned.
final class AskScheduleTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// The first attempt is **now**. Delaying it would leave the wrist reading "No workout" for
    /// seconds longer and would save nothing — asking immediately is the entire mechanism.
    func testTheFirstAttemptIsImmediate() {
        XCTAssertEqual(AskSchedule.attempts(from: t0).first, t0)
    }

    func testTheAttemptsWiden() {
        XCTAssertEqual(
            AskSchedule.attempts(from: t0),
            [t0,
             t0.addingTimeInterval(5),
             t0.addingTimeInterval(20),
             t0.addingTimeInterval(65)]
        )
    }

    /// Bounded, and this is the assertion that matters: an hour with the phone never reachable
    /// costs a handful of messages per waking, not one per second.
    func testTheRetryScheduleIsBounded() {
        XCTAssertEqual(AskSchedule.attempts(from: t0).count, AskSchedule.backoff.count + 1)
        XCTAssertLessThanOrEqual(AskSchedule.backoff.reduce(0, +), 65, "the last attempt lands about a minute out")
    }

    /// **The waking with nothing on screen keeps its retry.** This is the shape of the bug that
    /// started the whole recovery mechanism: a workout begins on the phone, that one push is
    /// missed, and a wrist with nothing on it has no way to find out except by asking — so it must
    /// ask more than once, because the phone may be mid-launch on the first try.
    func testAWakingWithNothingOnScreenStillRetries() {
        XCTAssertEqual(AskSchedule.attempts(from: t0).count, 4)
    }

    /// None of the attempts lands on top of another — a retry that fires immediately after the
    /// one before it is a poll wearing a schedule.
    func testNoTwoAttemptsAreCloserThanFiveSeconds() {
        let instants = AskSchedule.attempts(from: t0)

        for (earlier, later) in zip(instants, instants.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.timeIntervalSince(earlier), 5)
        }
    }

    /// The bound in the terms that matter, stated once so that raising the number of attempts has
    /// to argue with a number rather than with a feeling. A one-hour session with a wrist raise
    /// every thirty seconds is 120 wakings; the poll this replaced was 3,600 wakes an hour.
    func testAnHourOfRaisingTheWristStaysFarBelowAPoll() {
        let wristRaisesPerHour = 120
        let worstCase = wristRaisesPerHour * AskSchedule.attempts(from: t0).count

        XCTAssertLessThan(worstCase, 600, "an hour of never being answered stays in the hundreds")
    }
}
