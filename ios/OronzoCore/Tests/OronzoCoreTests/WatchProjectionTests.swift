import XCTest
@testable import OronzoCore

final class WatchProjectionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func timed(_ index: Int, _ seconds: TimeInterval, name: String = "Work") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil
        )
    }

    private func reps(_ index: Int, _ count: Int = 10, name: String = "Squat") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .reps, duration: nil,
            reps: count, targetWeightKg: nil, setIndex: 1, setCount: 1,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil
        )
    }

    /// Nothing has elapsed — the watch should just keep showing what the phone said.
    func testNoProjectionBeforeTheBoundary() {
        let intervals = [timed(0, 60), timed(1, 60)]
        let end = t0.addingTimeInterval(60)

        let (index, projectedEnd) = WatchProjection.project(
            intervals: intervals, from: 0, end: end, now: t0.addingTimeInterval(30)
        )

        XCTAssertEqual(index, 0)
        XCTAssertEqual(projectedEnd, end)
    }

    func testProjectsIntoTheNextTimedInterval() {
        let intervals = [timed(0, 60), timed(1, 30)]
        let end = t0.addingTimeInterval(60)

        let (index, projectedEnd) = WatchProjection.project(
            intervals: intervals, from: 0, end: end, now: t0.addingTimeInterval(70)
        )

        XCTAssertEqual(index, 1)
        XCTAssertEqual(projectedEnd, t0.addingTimeInterval(90), "the new boundary keeps the schedule")
    }

    /// The phone was quiet for a while: several intervals elapsed, and the watch should land
    /// where the session actually is rather than a step behind.
    func testProjectsAcrossSeveralIntervals() {
        let intervals = [timed(0, 60), timed(1, 60), timed(2, 60), timed(3, 60)]

        let (index, end) = WatchProjection.project(
            intervals: intervals, from: 0, end: t0.addingTimeInterval(60), now: t0.addingTimeInterval(185)
        )

        XCTAssertEqual(index, 3)
        XCTAssertEqual(end, t0.addingTimeInterval(240))
    }

    /// A rep interval has no length, so the walk stops there and the watch waits to be told.
    func testStopsAtARepInterval() {
        let intervals = [timed(0, 60), reps(1, 12), timed(2, 45)]

        let (index, end) = WatchProjection.project(
            intervals: intervals, from: 0, end: t0.addingTimeInterval(60), now: t0.addingTimeInterval(90)
        )

        XCTAssertEqual(index, 1)
        XCTAssertNil(end, "nothing can be assumed about when a rep set ends")
    }

    /// Starting on a rep interval — the phone is paused on it, so there is nothing to project.
    func testRepIntervalWithNoEndIsLeftAlone() {
        let intervals = [reps(0, 10), timed(1, 30)]

        let (index, end) = WatchProjection.project(
            intervals: intervals, from: 0, end: nil, now: t0.addingTimeInterval(999)
        )

        XCTAssertEqual(index, 0)
        XCTAssertNil(end)
    }

    /// Paused: the phone sends no end date, so the watch must not invent progress.
    func testPausedStateIsNotProjected() {
        let intervals = [timed(0, 60), timed(1, 60)]

        let (index, end) = WatchProjection.project(
            intervals: intervals, from: 0, end: nil, now: t0.addingTimeInterval(999)
        )

        XCTAssertEqual(index, 0)
        XCTAssertNil(end)
    }

    /// Past the final interval the walk stops rather than running off the end of the array.
    func testDoesNotRunPastTheLastInterval() {
        let intervals = [timed(0, 60), timed(1, 60)]

        let (index, end) = WatchProjection.project(
            intervals: intervals, from: 0, end: t0.addingTimeInterval(60), now: t0.addingTimeInterval(10_000)
        )

        XCTAssertEqual(index, 1)
        XCTAssertEqual(end, t0.addingTimeInterval(120), "it stops on the last interval rather than inventing more")
    }

    func testUnknownIndexIsReturnedUnchanged() {
        let intervals = [timed(0, 60)]

        let (index, end) = WatchProjection.project(intervals: intervals, from: 7, end: nil, now: t0)

        XCTAssertEqual(index, 7)
        XCTAssertNil(end)
    }
}
