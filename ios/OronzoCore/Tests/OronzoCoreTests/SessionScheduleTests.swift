import XCTest
@testable import OronzoCore

/// The rule that decides when a surface may sleep.
///
/// The point of this file is the arithmetic: the watch spends a whole workout inside
/// `nextEvent`, and a mistake here is a cue that never reaches a wrist — the silent failure this
/// project keeps having to dig out. So the boundaries are pinned individually, and the last test
/// counts the wakes a real session costs.
final class SessionScheduleTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The four instants in an interval

    /// A minute-long interval has exactly four moments worth waking for: the three countdown
    /// steps and the end. Everything else about it is knowable in advance.
    func testAMinuteLongIntervalWakesOnlyAtItsCountdownAndItsEnd() {
        let end = t0.addingTimeInterval(60)

        XCTAssertEqual(next(at: t0, end: end), end.addingTimeInterval(-3))
        XCTAssertEqual(next(at: t0.addingTimeInterval(30), end: end), end.addingTimeInterval(-3))
        XCTAssertEqual(next(at: end.addingTimeInterval(-3.5), end: end), end.addingTimeInterval(-3))
        XCTAssertEqual(next(at: end.addingTimeInterval(-3), end: end), end.addingTimeInterval(-2))
        XCTAssertEqual(next(at: end.addingTimeInterval(-2), end: end), end.addingTimeInterval(-1))
        XCTAssertEqual(next(at: end.addingTimeInterval(-1), end: end), end)
        XCTAssertNil(next(at: end, end: end), "the interval is over; the projection decides what is next")
    }

    /// A boundary that has already arrived is never returned again. This is what stops a sleeping
    /// loop from spinning when a wake lands a fraction early: it returns the same instant at most
    /// once more, and then moves on.
    func testABoundaryAlreadyReachedIsNotReturnedAgain() {
        let end = t0.addingTimeInterval(10)

        let justAfter = end.addingTimeInterval(-2) + 0.000_1
        XCTAssertNotEqual(next(at: justAfter, end: end), end.addingTimeInterval(-2))
        XCTAssertEqual(next(at: justAfter, end: end), end.addingTimeInterval(-1))
    }

    /// The countdown reads three, two, one — so the last quarter of a minute is the only part of
    /// it that needs more than one wake.
    func testTheThreeCountdownStepsAreOneSecondApart() {
        let end = t0.addingTimeInterval(90)
        var cursor = end.addingTimeInterval(-3.2)
        var steps: [TimeInterval] = []

        while let event = next(at: cursor, end: end) {
            steps.append(event.timeIntervalSince(end))
            cursor = event
        }

        XCTAssertEqual(steps, [-3, -2, -1, 0])
    }

    // MARK: - When nothing is due

    /// A rep interval has no length, so nothing about it can be predicted from the clock. Only the
    /// phone can move it on.
    func testARepIntervalSchedulesNothing() {
        XCTAssertNil(next(at: t0, end: nil))
    }

    /// A paused session holds its clock. `end` is not nil in that state — the watch turns the
    /// frozen remainder back into a date so the screen can draw it — so this has to be stated.
    func testAPausedSessionSchedulesNothing() {
        let end = t0.addingTimeInterval(60)
        XCTAssertNil(
            SessionSchedule.nextEvent(after: t0, end: end, isPaused: true, isFinished: false)
        )
    }

    /// DONE has nothing left to say, and this is what lets the watch put the whole session —
    /// extended runtime session included — down the moment the workout ends.
    func testAFinishedSessionSchedulesNothing() {
        let end = t0.addingTimeInterval(60)
        XCTAssertNil(
            SessionSchedule.nextEvent(after: t0, end: end, isPaused: false, isFinished: true)
        )
    }

    // MARK: - The whole-second clock

    func testTheNextSecondIsStrictlyAheadOfNow() {
        XCTAssertEqual(
            SessionSchedule.nextSecond(after: t0).timeIntervalSince1970,
            1_700_000_001
        )
        // Mid-second, the next whole second is the one after it.
        XCTAssertEqual(
            SessionSchedule.nextSecond(after: t0.addingTimeInterval(0.4)).timeIntervalSince1970,
            1_700_000_001
        )
        // Exactly on a boundary, it must advance rather than return where it already is.
        XCTAssertEqual(
            SessionSchedule.nextSecond(after: t0.addingTimeInterval(1)).timeIntervalSince1970,
            1_700_000_002
        )
    }

    // MARK: - What the change is worth

    /// **The measurement behind the battery fix.**
    ///
    /// This walks a real 15-minute session the way the watch now does — sleep to the next event,
    /// re-project, sleep again — and counts the wakes. The loop it replaces sampled four times a
    /// second regardless, which for this same session is 3,600 wakes; the watch also polled for
    /// haptics on its own timer, so the true before was twice that.
    ///
    /// Kept as a test rather than a claim: if a later change reintroduces polling, this fails.
    func testAFifteenMinuteSessionWakesAboutEightyTimesInsteadOfThreeThousandSixHundred() {
        let intervals = PlanFlattener.flatten(Plan(name: "P", blocks: [
            PlanBlock(name: "Main", steps: (0..<10).map { i in
                PlanStep(label: "Set \(i + 1)", mode: .time, duration: 60, restAfter: 30)
            }),
        ]), exercises: [:])
        let duration = intervals.compactMap(\.duration).reduce(0, +)
        XCTAssertEqual(duration, 900, "a 15-minute session is the fixture")

        // The phone's anchor: on the first interval, with that interval's end.
        var cursor = t0
        var index = 0
        var end = intervals[0].duration.map { t0.addingTimeInterval($0) }
        XCTAssertNotNil(end)

        var wakes = 0
        while let event = SessionSchedule.nextEvent(
            after: cursor, end: end, isPaused: false, isFinished: false
        ) {
            wakes += 1
            cursor = event
            (index, end) = WatchProjection.project(
                intervals: intervals, from: index, end: end, now: cursor
            )
            XCTAssertLessThanOrEqual(wakes, 200, "the walk should terminate well before this")
        }

        XCTAssertEqual(index, intervals.count - 1, "the whole session was walked")
        // Four wakes per interval: the three countdown steps and the boundary itself.
        XCTAssertEqual(wakes, intervals.count * 4)

        let pollingAtFourHertz = Int(duration * 4)
        XCTAssertLessThan(
            wakes * 40, pollingAtFourHertz,
            "\(wakes) wakes against \(pollingAtFourHertz) for a 4 Hz poll — the ratio is the win"
        )
    }

    // MARK: - Helpers

    private func next(at now: Date, end: Date?) -> Date? {
        SessionSchedule.nextEvent(after: now, end: end, isPaused: false, isFinished: false)
    }
}
