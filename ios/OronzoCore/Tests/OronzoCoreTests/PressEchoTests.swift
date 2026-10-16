import XCTest
@testable import OronzoCore

final class PressEchoTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func timed(_ index: Int, _ seconds: TimeInterval, name: String = "Work") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1,
            blockName: nil, exerciseID: nil
        )
    }

    private func reps(_ index: Int, _ count: Int = 10, name: String = "Squat") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .reps, duration: nil,
            reps: count, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1,
            blockName: nil, exerciseID: nil
        )
    }

    /// The engine's own state, in the shape the wire carries it — so an echo can be compared with
    /// what the phone will actually do rather than with a hand-written expectation.
    private func state(of engine: ExecutionEngine) -> SessionState {
        SessionState(
            currentIndex: engine.currentIndex,
            isPaused: engine.phase == .paused,
            isFinished: engine.phase == .finished,
            intervalEnd: engine.intervalEnd,
            remainingWhenPaused: engine.remainingWhenPaused,
            finishedAt: engine.finishedAt
        )
    }

    // MARK: - What a press earns

    func testNextMovesOnAndCarriesTheNextIntervalsOwnLength() {
        let intervals = [reps(0), timed(1, 45)]

        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state.currentIndex, 1)
        XCTAssertEqual(echo?.state.intervalEnd, t0.addingTimeInterval(45))
        XCTAssertNil(echo?.state.remainingWhenPaused)
        XCTAssertEqual(echo?.direction, .forward)
        XCTAssertEqual(echo?.at, t0)
    }

    func testNextOntoARepIntervalEchoesNoEndDate() {
        let intervals = [reps(0), reps(1)]

        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state.currentIndex, 1)
        XCTAssertNil(echo?.state.intervalEnd, "a rep interval has no length for the wrist to count")
    }

    func testPreviousWalksBack() {
        let intervals = [timed(0, 60), reps(1)]

        let echo = PressEcho.earned(
            by: .previous, intervals: intervals, showing: 1, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state.currentIndex, 0)
        XCTAssertEqual(echo?.state.intervalEnd, t0.addingTimeInterval(60))
        XCTAssertEqual(echo?.direction, .backward)
    }

    /// `next` on the last interval is how a session *finishes* in the engine. DONE is the phone's
    /// to declare — the record, the summary, the history and the Health write all hang off it — so
    /// the wrist waits rather than inventing an end to the workout.
    func testNextOnTheLastIntervalIsNotEchoed() {
        let intervals = [reps(0), reps(1)]

        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 1, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertNil(echo)
    }

    /// `goBack` at index 0 is a documented no-op in the engine, so there is nothing to echo.
    func testPreviousAtTheStartIsNotEchoed() {
        let intervals = [reps(0), reps(1)]

        let echo = PressEcho.earned(
            by: .previous, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertNil(echo)
    }

    /// The three controls the wrist may not answer for itself. A pause would stop this clock while
    /// the phone ran the interval on; a finish is the phone's; an ask is not a move.
    func testOnlyTheStepControlsAreEchoed() {
        let intervals = [reps(0), reps(1)]

        for control: WatchControl in [.togglePause, .finish, .requestState] {
            XCTAssertNil(
                PressEcho.earned(
                    by: control, intervals: intervals, showing: 0,
                    isPaused: false, isFinished: false, now: t0
                ),
                "\(control.rawValue) may not be answered by the wrist"
            )
        }
    }

    func testAFinishedSessionEchoesNothing() {
        let intervals = [reps(0), reps(1)]

        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: true, now: t0
        )

        XCTAssertNil(echo)
    }

    func testAPressWithNoPlanBehindItIsRefused() {
        let echo = PressEcho.earned(
            by: .next, intervals: [], showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertNil(echo)
    }

    /// **Earning from the *displayed* index is what makes a burst of presses work.** Two taps in
    /// quick succession have to move two intervals, which they only do if the second press is
    /// measured from the first echo rather than from the phone's position, which has not moved.
    func testTwoPressesInQuickSuccessionMoveTwoIntervals() {
        let intervals = [reps(0), reps(1), reps(2)]

        let first = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )
        let second = PressEcho.earned(
            by: .next, intervals: intervals, showing: first?.state.currentIndex ?? 0,
            isPaused: false, isFinished: false, now: t0.addingTimeInterval(1)
        )

        XCTAssertEqual(second?.state.currentIndex, 2)
    }

    // MARK: - The echo says what the engine will do

    /// The cross-check that keeps this type from inventing an arithmetic of its own. Each case
    /// runs a real engine, then asks what the wrist would have shown for the same press.
    func testTheEchoAgreesWithTheEngineWhenAdvancing() {
        let intervals = [reps(0), timed(1, 45)]
        var engine = ExecutionEngine(intervals: intervals)
        _ = engine.start(at: t0)

        _ = engine.advance(at: t0)
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state, state(of: engine))
    }

    func testTheEchoAgreesWithTheEngineWhenAdvancingWhilePaused() {
        let intervals = [reps(0), timed(1, 45)]
        var engine = ExecutionEngine(intervals: intervals)
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0)

        _ = engine.advance(at: t0)
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: true, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state, state(of: engine))
        XCTAssertEqual(echo?.state.remainingWhenPaused, 45, "a paused press holds the whole interval")
        XCTAssertNil(echo?.state.intervalEnd)
    }

    func testTheEchoAgreesWithTheEngineWhenGoingBack() {
        let intervals = [timed(0, 60), reps(1)]
        var engine = ExecutionEngine(intervals: intervals)
        _ = engine.start(at: t0)
        _ = engine.advance(at: t0)

        _ = engine.goBack(at: t0)
        let echo = PressEcho.earned(
            by: .previous, intervals: intervals, showing: 1, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state, state(of: engine))
    }

    func testTheEchoAgreesWithTheEngineGoingBackWhilePaused() {
        let intervals = [timed(0, 60), reps(1)]
        var engine = ExecutionEngine(intervals: intervals)
        _ = engine.start(at: t0)
        _ = engine.advance(at: t0)
        _ = engine.pause(at: t0)

        _ = engine.goBack(at: t0)
        let echo = PressEcho.earned(
            by: .previous, intervals: intervals, showing: 1, isPaused: true, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.state, state(of: engine))
    }

    // MARK: - When the phone's word replaces it

    func testASnapshotAtTheEchoedIndexReleasesIt() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        let phone = SessionState(
            currentIndex: 1, isPaused: false, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: nil
        )

        XCTAssertEqual(echo?.verdict(against: phone), .released)
    }

    /// The ordinary case while a press is in flight: the phone is still where it was, and the
    /// wrist must not be dragged back to it.
    func testASnapshotStillBehindHoldsTheEcho() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        let phone = SessionState(
            currentIndex: 0, isPaused: false, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: nil
        )

        XCTAssertEqual(echo?.verdict(against: phone), .hold)
    }

    /// Someone pressed on the phone as well: the phone is past the echo, and being past it is the
    /// phone's word winning, not a reason to hold the wrist back.
    func testASnapshotAheadReleasesItToo() {
        let intervals = [reps(0), reps(1), reps(2)]
        var engine = ExecutionEngine(intervals: intervals)
        _ = engine.start(at: t0)
        _ = engine.advance(at: t0)
        _ = engine.advance(at: t0)

        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.verdict(against: state(of: engine)), .released)
        XCTAssertEqual(engine.currentIndex, 2)
    }

    func testABackwardEchoIsReleasedByAPhoneAtOrBehindIt() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .previous, intervals: intervals, showing: 1, isPaused: false, isFinished: false, now: t0
        )

        let caughtUp = SessionState(
            currentIndex: 0, isPaused: false, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: nil
        )
        let stillBehind = SessionState(
            currentIndex: 1, isPaused: false, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: nil
        )

        XCTAssertEqual(echo?.verdict(against: caughtUp), .released)
        XCTAssertEqual(echo?.verdict(against: stillBehind), .hold)
    }

    /// The session ended while the wrist was still holding a position inside it.
    func testAFinishedPhoneReleasesEveryEcho() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        let finished = SessionState(
            currentIndex: 1, isPaused: false, isFinished: true,
            intervalEnd: nil, remainingWhenPaused: nil, finishedAt: t0
        )

        XCTAssertEqual(echo?.verdict(against: finished), .released)
    }

    /// **Without this, a press made while paused would keep the wrist frozen through a resume** —
    /// showing a stopped clock for an interval the phone is counting down.
    func testAPhoneThatResumedReleasesAPressMadeWhilePaused() {
        let intervals = [reps(0), timed(1, 45)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: true, isFinished: false, now: t0
        )

        // The phone has not caught up on the position at all — it is still on interval 0 — but it
        // is running, which is the one fact that overrules the echo.
        let running = SessionState(
            currentIndex: 0, isPaused: false, isFinished: false,
            intervalEnd: t0.addingTimeInterval(30), remainingWhenPaused: nil
        )

        XCTAssertEqual(echo?.verdict(against: running), .released)
    }

    /// A press made while paused, with the phone still paused and still where it was: the ordinary
    /// in-flight case, in the paused flavour.
    func testAPressMadeWhilePausedIsHeldWhileThePhoneIsStillPaused() {
        let intervals = [reps(0), timed(1, 45)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: true, isFinished: false, now: t0
        )

        let phone = SessionState(
            currentIndex: 0, isPaused: true, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: 30
        )

        XCTAssertEqual(echo?.verdict(against: phone), .hold)
    }

    /// **A pause is the phone's word about the clock, and it outranks a position the wrist is only
    /// holding on to.** The press is not lost — it is still in flight, and the phone will apply it
    /// a moment later, paused, one interval on. What must not happen is the wrist sitting on a
    /// running countdown while the phone has been told to stop.
    func testAPauseOnThePhoneReleasesAnEchoPressedWhileRunning() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        let pausedOnThePhone = SessionState(
            currentIndex: 0, isPaused: true, isFinished: false,
            intervalEnd: nil, remainingWhenPaused: nil
        )

        XCTAssertEqual(echo?.verdict(against: pausedOnThePhone), .released)
    }

    // MARK: - The bound

    /// The one case the wrist cannot tell from "still in flight" is "the phone is gone", so the
    /// echo stops rather than standing forever.
    func testAnEchoExpiresAMinuteAfterThePress() {
        let intervals = [reps(0), reps(1)]
        let echo = PressEcho.earned(
            by: .next, intervals: intervals, showing: 0, isPaused: false, isFinished: false, now: t0
        )

        XCTAssertEqual(echo?.expiresAt, t0.addingTimeInterval(PressEcho.window))
        XCTAssertEqual(PressEcho.window, 60)
    }
}
