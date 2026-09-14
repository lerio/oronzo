import XCTest
@testable import OronzoCore

final class ExecutionEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func timed(_ index: Int, _ seconds: TimeInterval, name: String = "Work") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1, blockIndex: 0,
            blockName: nil, exerciseID: nil
        )
    }

    private func reps(_ index: Int, _ count: Int = 10, weight: Double? = nil, name: String = "Squat") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .reps, duration: nil,
            reps: count, targetWeightKg: weight, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1, blockIndex: 0,
            blockName: nil, exerciseID: nil
        )
    }

    private func rest(_ index: Int, _ seconds: TimeInterval) -> Interval {
        Interval(
            index: index, kind: .rest, name: "Break", mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1, blockIndex: 0,
            blockName: nil, exerciseID: nil
        )
    }

    // MARK: - Starting

    func testStartAnchorsTheFirstIntervalToAnAbsoluteEndDate() {
        var engine = ExecutionEngine(intervals: [timed(0, 60)])

        let events = engine.start(at: t0)

        XCTAssertEqual(events, [.started(index: 0, end: t0.addingTimeInterval(60))])
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(60))
        XCTAssertEqual(engine.currentIndex, 0)
    }

    func testStartOnARepIntervalHasNoEndDate() {
        var engine = ExecutionEngine(intervals: [reps(0)])

        _ = engine.start(at: t0)

        XCTAssertNil(engine.intervalEnd, "a rep interval has no length to count down from")
        XCTAssertFalse(engine.current?.advancesAutomatically ?? true)
    }

    func testStartIsIgnoredWhenAlreadyRunning() {
        var engine = ExecutionEngine(intervals: [timed(0, 60)])
        _ = engine.start(at: t0)

        XCTAssertTrue(engine.start(at: t0.addingTimeInterval(10)).isEmpty)
    }

    func testEmptySessionCannotStart() {
        var engine = ExecutionEngine(intervals: [])
        XCTAssertTrue(engine.start(at: t0).isEmpty)
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: - Auto-advance

    func testTickBeforeTheBoundaryDoesNothing() {
        var engine = ExecutionEngine(intervals: [timed(0, 60)])
        _ = engine.start(at: t0)

        XCTAssertTrue(engine.tick(now: t0.addingTimeInterval(59)).isEmpty)
        XCTAssertEqual(engine.currentIndex, 0)
    }

    func testTickAtTheBoundaryAdvances() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 30)])
        _ = engine.start(at: t0)

        let events = engine.tick(now: t0.addingTimeInterval(60))

        XCTAssertEqual(events, [.advanced(from: 0, to: 1)])
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(90), "boundaries chain, so no drift")
    }

    /// The case that motivates absolute end dates: the phone was in a pocket, the app was
    /// suspended for three minutes, and several intervals elapsed. That must resolve as ONE
    /// jump — not a burst of events, and not a countdown that is quietly wrong.
    func testSuspensionAcrossSeveralIntervalsCoalescesIntoOneEvent() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60), timed(2, 60), timed(3, 60)])
        _ = engine.start(at: t0)

        let events = engine.tick(now: t0.addingTimeInterval(185))

        XCTAssertEqual(events, [.advanced(from: 0, to: 3)], "one event, not three")
        XCTAssertEqual(engine.currentIndex, 3)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(240), "still on the original schedule")
        XCTAssertEqual(engine.outcomes[0]?.status, .completed)
        XCTAssertEqual(engine.outcomes[1]?.status, .completed)
        XCTAssertEqual(engine.outcomes[2]?.status, .completed)
        XCTAssertEqual(engine.outcomes[3]?.status, .pending)
    }

    func testTickingPastTheLastTimedIntervalFinishesTheSession() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))

        let events = engine.tick(now: t0.addingTimeInterval(500))

        XCTAssertEqual(events, [.finished])
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.outcomes[1]?.status, .completed)
    }

    /// Auto-advance must stop dead at a rep interval: there is no length to elapse, so the
    /// session waits for a tap however long the user takes.
    func testAutoAdvanceStopsAtARepInterval() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), reps(1, 12)])
        _ = engine.start(at: t0)

        let advanced = engine.tick(now: t0.addingTimeInterval(70))
        XCTAssertEqual(advanced, [.advanced(from: 0, to: 1)])
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertNil(engine.intervalEnd)

        XCTAssertTrue(engine.tick(now: t0.addingTimeInterval(9_999)).isEmpty, "waits indefinitely")
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testASessionEndingInARepIntervalDoesNotAutoFinish() {
        var engine = ExecutionEngine(intervals: [reps(0, 10)])
        _ = engine.start(at: t0)

        XCTAssertTrue(engine.tick(now: t0.addingTimeInterval(3_600)).isEmpty)
        XCTAssertEqual(engine.phase, .running)
    }

    // MARK: - Pause and resume

    func testPauseAndResumeShiftTheBoundaryByExactlyThePausedTime() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)

        _ = engine.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertEqual(engine.remainingWhenPaused, 50)
        XCTAssertNil(engine.intervalEnd)

        _ = engine.resume(at: t0.addingTimeInterval(40))

        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(90), "60s + the 30s paused")
        XCTAssertEqual(engine.pausedTotal, 30)
    }

    func testTickingWhilePausedDoesNothing() {
        var engine = ExecutionEngine(intervals: [timed(0, 60)])
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0.addingTimeInterval(10))

        XCTAssertTrue(engine.tick(now: t0.addingTimeInterval(1_000)).isEmpty)
        XCTAssertEqual(engine.currentIndex, 0)
    }

    func testPausingARepIntervalThenResumingLeavesItOpenEnded() {
        var engine = ExecutionEngine(intervals: [reps(0)])
        _ = engine.start(at: t0)

        _ = engine.pause(at: t0.addingTimeInterval(5))
        XCTAssertNil(engine.remainingWhenPaused)

        _ = engine.resume(at: t0.addingTimeInterval(20))
        XCTAssertNil(engine.intervalEnd, "still a rep interval — nothing to count down")
    }

    func testElapsedExcludesTimeSpentPaused() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0.addingTimeInterval(10))
        _ = engine.resume(at: t0.addingTimeInterval(40))

        XCTAssertEqual(engine.elapsed(at: t0.addingTimeInterval(100)), 70, accuracy: 0.001)
    }

    // MARK: - Manual control

    func testAdvanceCompletesTheCurrentInterval() {
        var engine = ExecutionEngine(intervals: [reps(0, 10), timed(1, 30)])
        _ = engine.start(at: t0)

        let events = engine.advance(at: t0.addingTimeInterval(45))

        XCTAssertEqual(events, [.advanced(from: 0, to: 1)])
        XCTAssertEqual(engine.outcomes[0]?.status, .completed)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(75))
    }

    func testAdvanceOnTheLastIntervalFinishes() {
        var engine = ExecutionEngine(intervals: [reps(0, 10)])
        _ = engine.start(at: t0)

        XCTAssertEqual(engine.advance(at: t0.addingTimeInterval(45)), [.finished])
        XCTAssertEqual(engine.phase, .finished)
    }

    func testSkippingMarksTheIntervalSkippedRatherThanCompleted() {
        var engine = ExecutionEngine(intervals: [reps(0, 10), reps(1, 10)])
        _ = engine.start(at: t0)

        _ = engine.advance(at: t0, skipped: true)

        XCTAssertEqual(engine.outcomes[0]?.status, .skipped)
    }

    func testAdvancingWhilePausedStaysPaused() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 45)])
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0.addingTimeInterval(10))

        _ = engine.advance(at: t0.addingTimeInterval(20))

        XCTAssertEqual(engine.phase, .paused)
        XCTAssertEqual(engine.remainingWhenPaused, 45, "the new interval, still not started")
        XCTAssertNil(engine.intervalEnd)
    }

    func testGoBackResetsTheEarlierInterval() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))

        let events = engine.goBack(at: t0.addingTimeInterval(61))

        XCTAssertEqual(events, [.advanced(from: 1, to: 0)])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.intervalEnd, t0.addingTimeInterval(121), "restarts the interval")
        XCTAssertEqual(engine.outcomes[0]?.status, .pending, "the redo clears the outcome")
    }

    func testGoBackAtTheStartIsANoOp() {
        var engine = ExecutionEngine(intervals: [timed(0, 60)])
        _ = engine.start(at: t0)

        XCTAssertTrue(engine.goBack(at: t0).isEmpty)
        XCTAssertEqual(engine.currentIndex, 0)
    }

    // MARK: - Recording actuals

    func testRecordedRepsAndWeightReachTheSnapshot() {
        var engine = ExecutionEngine(intervals: [reps(0, 10, weight: 60)])
        _ = engine.start(at: t0)
        engine.record(reps: 8, weightKg: 62.5)
        _ = engine.advance(at: t0.addingTimeInterval(50))

        let session = engine.snapshot(status: .completed)

        XCTAssertEqual(session.steps[0].actualReps, 8)
        XCTAssertEqual(session.steps[0].actualWeightKg, 62.5)
        XCTAssertEqual(session.steps[0].plannedReps, 10)
        XCTAssertEqual(session.steps[0].plannedWeightKg, 60)
        XCTAssertEqual(session.steps[0].status, .completed)
    }

    // MARK: - Snapshots

    func testFinishMarksUnreachedIntervalsSoHistoryIsHonest() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), reps(1, 10), reps(2, 10)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))
        engine.record(reps: 12, weightKg: nil)
        _ = engine.advance(at: t0.addingTimeInterval(90))

        let session = engine.finish(at: t0.addingTimeInterval(120))

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.steps.map(\.status), [.completed, .completed, .notReached])
        XCTAssertEqual(session.totalDuration, 120, accuracy: 0.001)
    }

    func testAbandonMarksTheRemainderAsUnreached() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), reps(1, 10)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))

        let session = engine.abandon(at: t0.addingTimeInterval(75))

        XCTAssertEqual(session.status, .abandoned)
        XCTAssertEqual(session.steps.map(\.status), [.completed, .notReached])
    }

    func testSnapshotCarriesTheFullPlannedShape() {
        var engine = ExecutionEngine(intervals: [timed(0, 60, name: "Plank"), rest(1, 30)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))

        let session = engine.finish(at: t0.addingTimeInterval(95))

        XCTAssertEqual(session.steps.count, 2, "one row per interval, including rests")
        XCTAssertEqual(session.steps[0].exerciseName, "Plank")
        XCTAssertEqual(session.steps[0].plannedDuration, 60)
        XCTAssertEqual(session.steps[1].kind, .rest)
        XCTAssertEqual(session.steps[1].exerciseName, "Break")
        XCTAssertEqual(session.steps.map(\.position), [0, 1])
    }

    // MARK: - End to end

    /// "3 x 12 squats, 90s rest", run to completion by tapping through.
    func testTheCanonicalSetsPlanRunsEndToEnd() {
        let squat = UUID()
        let plan = Plan(name: "Squats", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: squat, sets: 3, mode: .reps, reps: 12, restAfter: 90),
            ]),
        ])
        let intervals = PlanFlattener.flatten(plan, exerciseNames: [squat: "Back Squat"])
        var engine = ExecutionEngine(intervals: intervals)

        _ = engine.start(at: t0)

        // set → rest → set → rest → set → rest
        var clock = t0
        for _ in 0..<6 {
            engine.record(reps: 12, weightKg: 60)
            clock = clock.addingTimeInterval(45)
            _ = engine.advance(at: clock)
        }

        let session = engine.finish(at: clock)

        XCTAssertEqual(session.steps.count, 6)
        XCTAssertEqual(session.steps.filter { $0.kind == .exercise }.count, 3)
        XCTAssertTrue(session.steps.allSatisfy { $0.status == .completed })
        XCTAssertEqual(session.steps[0].exerciseName, "Back Squat")
        XCTAssertEqual(session.steps[1].exerciseName, "Break")
        XCTAssertEqual(session.steps.map(\.setIndex), [1, 1, 2, 2, 3, 3])
    }

    /// The other shape: a group that repeats, driven by auto-advance rather than taps.
    func testTheCanonicalCircuitRunsEndToEnd() {
        let plan = Plan(name: "HIIT", blocks: [
            PlanBlock(rounds: 3, steps: [
                PlanStep(label: "Hard", mode: .time, duration: 20),
                PlanStep(label: "Easy", mode: .time, duration: 40),
            ]),
        ])
        var engine = ExecutionEngine(intervals: PlanFlattener.flatten(plan))
        _ = engine.start(at: t0)

        // 3 rounds x 60s. Tick once past the end and expect a single coalesced event.
        let events = engine.tick(now: t0.addingTimeInterval(999))

        XCTAssertEqual(events, [.finished])
        XCTAssertEqual(engine.phase, .finished)

        let session = engine.finish(at: t0.addingTimeInterval(999))
        XCTAssertEqual(session.steps.count, 6)
        XCTAssertEqual(session.steps.map(\.blockRound), [1, 1, 2, 2, 3, 3])
        XCTAssertTrue(session.steps.allSatisfy { $0.status == .completed })
    }
}
