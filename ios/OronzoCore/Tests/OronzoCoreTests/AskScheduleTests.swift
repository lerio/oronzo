import XCTest
@testable import OronzoCore

/// The watch's retry, which has to be bounded because of what it would otherwise become.
///
/// Asking is how a watch that missed a push recovers, and it is the only mechanism there is — the
/// phone pushes and cannot know whether it was heard. But an unbounded retry is a message stream,
/// and `docs/decisions.md` rules per-second traffic between these two apps out for reasons that
/// cost a battery to learn. So the bound is the feature: these tests exist to make sure it stays
/// one if someone later decides the watch "should try a bit harder".
final class AskScheduleTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// The first attempt is **now**. Delaying it would leave the wrist reading "No workout" for
    /// seconds longer and would save nothing — asking immediately is the entire mechanism.
    func testTheFirstAttemptIsImmediate() {
        XCTAssertEqual(AskSchedule.attempt(1, from: t0), t0)
    }

    func testTheAttemptsWiden() {
        XCTAssertEqual(AskSchedule.attempt(2, from: t0), t0.addingTimeInterval(5))
        XCTAssertEqual(AskSchedule.attempt(3, from: t0), t0.addingTimeInterval(20))
        XCTAssertEqual(AskSchedule.attempt(4, from: t0), t0.addingTimeInterval(65))
    }

    /// Bounded, and this is the assertion that matters: an hour with the phone never reachable
    /// costs a handful of messages per waking, not one per second.
    func testTheRetryScheduleIsBounded() {
        XCTAssertNil(AskSchedule.attempt(AskSchedule.attemptCount + 1, from: t0))
        XCTAssertNil(AskSchedule.attempt(99, from: t0))
        XCTAssertNil(AskSchedule.attempt(0, from: t0), "attempts are 1-based")
    }

    /// None of the attempts lands on top of another — a retry that fires immediately after the
    /// one before it is a poll wearing a schedule.
    func testNoTwoAttemptsAreCloserThanFiveSeconds() {
        let instants = (1...AskSchedule.attemptCount).compactMap { AskSchedule.attempt($0, from: t0) }

        XCTAssertEqual(instants.count, AskSchedule.attemptCount)
        for (earlier, later) in zip(instants, instants.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.timeIntervalSince(earlier), 5)
        }
    }

    /// The bound in the terms that matter, stated once so that raising `attemptCount` has to
    /// argue with a number rather than with a feeling. A one-hour session with a wrist raise
    /// every thirty seconds is 120 wakings; the poll this replaced was 3,600 wakes an hour.
    func testAnHourOfRetryingStaysFarBelowAPoll() {
        let wristRaisesPerHour = 120
        let worstCase = wristRaisesPerHour * AskSchedule.attemptCount

        XCTAssertLessThan(worstCase, 600, "an hour of never being answered stays in the hundreds")
    }
}
