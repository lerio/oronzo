import XCTest
@testable import OronzoCore

final class RecordableWorkoutTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A finished session with **active** time and wall-clock span stated separately, because
    /// the difference between them is a pause — which is the thing the rule turns on.
    private func session(
        active: TimeInterval,
        span: TimeInterval? = nil,
        status: SessionStatus = .completed
    ) -> CompletedSession {
        let span = span ?? active
        return CompletedSession(
            startedAt: t0,
            finishedAt: t0.addingTimeInterval(span),
            totalDuration: active,
            status: status,
            steps: []
        )
    }

    // MARK: - The three-minute bar

    func testASessionOfExactlyThreeMinutesIsRecorded() {
        let workout = RecordableWorkout(completed: session(active: 180))

        XCTAssertNotNil(workout, "the bar is a minimum, so it includes itself")
    }

    func testASessionJustUnderThreeMinutesIsNotRecorded() {
        XCTAssertNil(RecordableWorkout(completed: session(active: 179.99)))
    }

    func testAnEmptySessionIsNotRecorded() {
        XCTAssertNil(RecordableWorkout(completed: session(active: 0)))
    }

    // MARK: - What the workout says

    /// Health derives the workout's duration from these two dates, so the dates *are* the answer
    /// and there is nothing else to assert about it.
    func testTheWorkoutKeepsTheSessionsRealSpan() {
        let workout = RecordableWorkout(completed: session(active: 600))

        XCTAssertEqual(workout?.startedAt, t0)
        XCTAssertEqual(workout?.finishedAt, t0.addingTimeInterval(600))
    }

    /// The case that separates the two numbers. Ten minutes elapsed, but almost all of it was
    /// paused, so the work was two minutes and this is not a workout.
    func testALongPauseDoesNotTurnAShortSessionIntoAWorkout() {
        let paused = session(active: 120, span: 600)

        XCTAssertNil(RecordableWorkout(completed: paused))
    }

    /// The same separation, the other way round: a session that clears the bar on active time is
    /// recorded across its whole span, pause included. This is the documented imperfection — the
    /// entry is longer than the work — pinned so that changing it has to be deliberate.
    func testASessionThatClearsTheBarIsRecordedAcrossItsWholeSpan() {
        let workout = RecordableWorkout(completed: session(active: 300, span: 900))

        XCTAssertEqual(
            workout?.finishedAt.timeIntervalSince(t0), 900,
            "Health is told the span, not the active time"
        )
    }

    // MARK: - Which endings count

    func testASessionEndedEarlyIsStillRecorded() {
        let abandoned = session(active: 400, status: .abandoned)

        XCTAssertNotNil(
            RecordableWorkout(completed: abandoned),
            "ending early is not the same as not having done it"
        )
    }

    func testASessionThatNeverEndedIsNotRecorded() {
        let running = session(active: 400, status: .inProgress)

        XCTAssertNil(RecordableWorkout(completed: running))
    }
}
