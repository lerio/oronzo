import XCTest
@testable import OronzoCore

final class ExecutionEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func timed(_ index: Int, _ seconds: TimeInterval, name: String = "Work") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1,
            blockName: nil, exerciseID: nil
        )
    }

    private func reps(_ index: Int, _ count: Int = 10, weight: Double? = nil, name: String = "Squat") -> Interval {
        Interval(
            index: index, kind: .exercise, name: name, mode: .reps, duration: nil,
            reps: count, targetWeightKg: weight, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1,
            blockName: nil, exerciseID: nil
        )
    }

    private func rest(_ index: Int, _ seconds: TimeInterval) -> Interval {
        Interval(
            index: index, kind: .rest, name: "Break", mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1, blockRound: 1, blockRoundCount: 1,
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

    /// A pause that has not ended yet is time not spent exercising, exactly like one that has.
    ///
    /// It was excluded only once `resume` folded it into `pausedTotal`, so anything that read
    /// `elapsed` *during* a pause was told the pause was work. The reading corrects itself on
    /// resume, which is why it survived: the number was right whenever anyone looked at the end.
    func testElapsedExcludesAPauseThatIsStillInProgress() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0.addingTimeInterval(10))

        XCTAssertEqual(engine.elapsed(at: t0.addingTimeInterval(100)), 10, accuracy: 0.001,
                       "ninety seconds of standing still is not ninety seconds of work")
    }

    /// The same fact at the moment it becomes permanent: ending a session **while paused** must
    /// not write the final pause into `totalDuration`, which is the number that goes to history.
    func testEndingWhilePausedExcludesTheFinalPauseFromTheTotal() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), timed(1, 60)])
        _ = engine.start(at: t0)
        _ = engine.pause(at: t0.addingTimeInterval(10))

        let completed = engine.abandon(at: t0.addingTimeInterval(300))

        XCTAssertEqual(completed.totalDuration, 10, accuracy: 0.001,
                       "five minutes of paused phone is not five minutes of training")
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

    // MARK: - Snapshots

    func testFinishMarksUnreachedIntervalsSoHistoryIsHonest() {
        var engine = ExecutionEngine(intervals: [timed(0, 60), reps(1, 10), reps(2, 10)])
        _ = engine.start(at: t0)
        _ = engine.tick(now: t0.addingTimeInterval(60))
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

    // MARK: - Adjusting a step's load mid-session

    /// An interval that came from a `plan_steps` row, which is what an adjustment needs to exist.
    private func weighted(_ index: Int, step: UUID?, weight: Double, intensity: Intensity? = nil) -> Interval {
        Interval(
            index: index, kind: .exercise, name: "Press", mode: .reps, duration: nil,
            reps: 8, targetWeightKg: weight, setIndex: index + 1, setCount: 3,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil,
            stepID: step, intensity: intensity
        )
    }

    /// **The whole point of the feature**: the step is one prescription, so every one of its
    /// intervals moves — the sets still ahead as much as the one being performed — and a step that
    /// merely shares the exercise does not.
    func testACommittedEditMovesEveryIntervalOfItsStepAndNoOther() {
        let edited = UUID()
        let untouched = UUID()
        var engine = ExecutionEngine(intervals: [
            weighted(0, step: edited, weight: 20),
            weighted(1, step: edited, weight: 20),
            rest(2, 60),
            weighted(3, step: untouched, weight: 50),
        ])
        _ = engine.start(at: t0)

        engine.applyLoadEdit(StepLoadEdit(stepID: edited, weightKg: 22.5))

        XCTAssertEqual(engine.intervals.map(\.targetWeightKg), [22.5, 22.5, nil, 50])
        XCTAssertEqual(engine.intervals[1].stepID, edited, "and it is still the same step")
    }

    /// An edit is keyed by the step, and an interval with no step is in no step's set — so a rest
    /// and a step built in code are both left exactly as they were.
    func testAnEditLeavesSteplessIntervalsAlone() {
        let step = UUID()
        var engine = ExecutionEngine(intervals: [
            weighted(0, step: step, weight: 20),
            rest(1, 60),
            weighted(2, step: nil, weight: 30),
        ])
        _ = engine.start(at: t0)

        engine.applyLoadEdit(StepLoadEdit(stepID: step, weightKg: 22.5))

        XCTAssertNil(engine.intervals[1].targetWeightKg, "a rest has no load to edit")
        XCTAssertEqual(engine.intervals[2].targetWeightKg, 30, "a step with no row belongs to no edit")
    }

    /// A load is not a duration and not a position. Everything the engine tracks about *where the
    /// session is* — and everything it has already recorded about it — has to survive untouched,
    /// or an adjustment made in set two would rewrite sets already done.
    func testAnEditDoesNotMoveTheSessionOrItsRecordedOutcomes() {
        let step = UUID()
        var engine = ExecutionEngine(intervals: [
            weighted(0, step: step, weight: 20),
            weighted(1, step: step, weight: 20),
            weighted(2, step: step, weight: 20),
        ])
        _ = engine.start(at: t0)
        _ = engine.advance(at: t0.addingTimeInterval(30))    // set 1 done
        _ = engine.tick(now: t0.addingTimeInterval(45))      // set 2 running, anchored at 60

        let indexBefore = engine.currentIndex
        let endBefore = engine.intervalEnd
        let outcomesBefore = engine.outcomes

        engine.applyLoadEdit(StepLoadEdit(stepID: step, weightKg: 22.5))

        XCTAssertEqual(engine.currentIndex, indexBefore)
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.intervalEnd, endBefore, "a load does not move a clock")
        XCTAssertEqual(engine.outcomes, outcomesBefore, "set 1 is recorded at the load it was done at")
        XCTAssertEqual(engine.current?.targetWeightKg, 22.5, "and the set in progress has the new one")
    }

    /// The edit travels the same way everything else the session knows does: into the record, so a
    /// phone that relaunches mid-workout resumes onto the load it was actually using.
    func testACommittedEditSurvivesTheRecord() throws {
        let step = UUID()
        let planID = UUID()
        var engine = ExecutionEngine(intervals: [weighted(0, step: step, weight: 20, intensity: .low)])
        _ = engine.start(at: t0)

        engine.applyLoadEdit(StepLoadEdit(stepID: step, weightKg: 22.5, intensity: .hard))
        let record = SessionRecord(engine: engine, planID: planID, planName: "P", savedAt: t0)

        let restored = ExecutionEngine(restoring: try WireCodec.decode(
            SessionRecord.self, from: WireCodec.encode(record)
        ))

        XCTAssertEqual(restored?.intervals.first?.targetWeightKg, 22.5)
        XCTAssertEqual(restored?.intervals.first?.intensity, .hard)
        XCTAssertEqual(restored?.intervals.first?.stepID, step, "still adjustable after a resume")
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
        let intervals = PlanFlattener.flatten(plan, exercises: [squat: ExerciseInfo(name: "Back Squat")])
        var engine = ExecutionEngine(intervals: intervals)

        _ = engine.start(at: t0)

        // set → rest → set → rest → set → rest
        var clock = t0
        for _ in 0..<6 {
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
        var engine = ExecutionEngine(intervals: PlanFlattener.flatten(plan, exercises: [:]))
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
