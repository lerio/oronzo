import XCTest
@testable import OronzoCore

final class PlanFlattenerTests: XCTestCase {

    // MARK: - Step sets ("4 x 6-8 bench press")

    /// The set count belongs to the exercise, so a step repeats on its own.
    func testStepSetsRepeatTheExercise() {
        let squat = UUID()
        let plan = Plan(name: "Squats", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: squat, sets: 3, mode: .reps, reps: 12, restAfter: 90),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [squat: ExerciseInfo(name: "Back Squat")])

        // Three sets, and a rest after EACH of them — including the last, which carries you
        // into whatever comes next.
        XCTAssertEqual(intervals.map(\.kind), [.exercise, .rest, .exercise, .rest, .exercise, .rest])
        XCTAssertEqual(intervals.count, 6)
        XCTAssertEqual(intervals.map(\.setIndex), [1, 1, 2, 2, 3, 3], "the step's own set number")
        XCTAssertEqual(intervals.map(\.blockRound), [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(intervals[0].reps, 12)
        XCTAssertEqual(intervals[1].duration, 90)
        XCTAssertEqual(intervals[5].kind, .rest, "the final set is followed by rest too")
    }

    func testStepWithNoSetsDefaultsToOne() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "A", mode: .reps, reps: 5, restAfter: 30)]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 2, "one set plus its rest")
        XCTAssertEqual(PlanStep(mode: .reps, reps: 5).sets, 1)
    }

    func testStepWithSetsButNoRestEmitsNoRests() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Squat", sets: 4, mode: .reps, reps: 8)]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 4)
        XCTAssertTrue(intervals.allSatisfy { $0.kind == .exercise })
    }

    // MARK: - Two-sided exercises ("8 reps per leg")

    /// A two-sided exercise emits both sides inside the set, and the rest still falls once —
    /// after the pair, because the pair is what a set of lunges means to the person doing them.
    func testTwoSidedExerciseEmitsBothSidesThenOneRest() {
        let lunge = UUID()
        let plan = Plan(name: "Lunges", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: lunge, sets: 3, mode: .reps, reps: 8, restAfter: 90),
            ]),
        ])

        let intervals = PlanFlattener.flatten(
            plan,
            exercises: [lunge: ExerciseInfo(name: "Reverse Lunge", hasTwoSides: true)]
        )

        XCTAssertEqual(intervals.count, 9, "six sides and three rests — not six rests")
        XCTAssertEqual(
            intervals.map(\.kind),
            [.exercise, .exercise, .rest, .exercise, .exercise, .rest, .exercise, .exercise, .rest]
        )
        XCTAssertEqual(
            intervals.map(\.name),
            ["Reverse Lunge (left)", "Reverse Lunge (right)", "Break",
             "Reverse Lunge (left)", "Reverse Lunge (right)", "Break",
             "Reverse Lunge (left)", "Reverse Lunge (right)", "Break"]
        )
        // The pair IS the set: both sides carry the same number, so the screen reads "set 1 of 3"
        // while you are on either leg rather than counting to six.
        XCTAssertEqual(intervals.map(\.setIndex), [1, 1, 1, 2, 2, 2, 3, 3, 3])
        XCTAssertEqual(intervals[0].setCount, 3)
        XCTAssertEqual(intervals.map(\.index), Array(0..<9), "indices stay contiguous")
        XCTAssertEqual(intervals[2].duration, 90, "the rest did not move or double")
    }

    /// A timed two-sided exercise holds for the **full** duration on each side. Nothing here
    /// splits the duration across the pair, which is the misreading worth pinning down.
    func testTwoSidedTimedExerciseHoldsTheFullDurationPerSide() {
        let plank = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: plank, sets: 2, mode: .time, duration: 45, restAfter: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(
            plan,
            exercises: [plank: ExerciseInfo(name: "Side Plank", hasTwoSides: true)]
        )

        XCTAssertEqual(intervals.map(\.name), [
            "Side Plank (left)", "Side Plank (right)", "Break",
            "Side Plank (left)", "Side Plank (right)", "Break",
        ])
        XCTAssertEqual(intervals.map(\.duration), [45, 45, 30, 45, 45, 30])
    }

    /// Flag off is the behaviour every plan had before the flag existed.
    func testAOneSidedExerciseIsUnchanged() {
        let squat = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: squat, sets: 2, mode: .reps, reps: 5, restAfter: 60),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [squat: ExerciseInfo(name: "Back Squat")])

        XCTAssertEqual(intervals.map(\.name), ["Back Squat", "Break", "Back Squat", "Break"])
    }

    /// A step with an explicit label gets the side too: the side belongs to the exercise being
    /// done, not to whatever name it happens to be listed under.
    func testASideIsAppendedToALabelAsWell() {
        let lunge = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(exerciseID: lunge, label: "Warm-up lunges", mode: .reps, reps: 8)]),
        ])

        let intervals = PlanFlattener.flatten(
            plan,
            exercises: [lunge: ExerciseInfo(name: "Reverse Lunge", hasTwoSides: true)]
        )

        XCTAssertEqual(intervals.map(\.name), ["Warm-up lunges (left)", "Warm-up lunges (right)"])
    }

    /// `name(for:)` is what the plan detail screen lists *as authored*, so it stays side-free even
    /// with the flag on — otherwise a plan would read as twice as long as it is written. That is a
    /// deliberate second answer for one step, so it is asserted rather than left as an accident.
    func testTheStepNameStaysSideFreeWhileTheIntervalsDoNot() {
        let lunge = UUID()
        let step = PlanStep(exerciseID: lunge, mode: .reps, reps: 8)
        let exercises = [lunge: ExerciseInfo(name: "Reverse Lunge", hasTwoSides: true)]

        XCTAssertEqual(PlanFlattener.name(for: step, exercises: exercises), "Reverse Lunge")
        XCTAssertEqual(PlanFlattener.sideSuffixes(of: step, exercises: exercises).count, 2)
        XCTAssertEqual(PlanFlattener.sideSuffixes(of: step, exercises: [:]).count, 1)
    }

    // MARK: - Effort ("Hard — 20 sec"), structured

    /// The step's intensity rides onto every interval it emits, and an absent one stays absent:
    /// nothing here invents an effort for a step that did not declare one.
    func testIntensityReachesEveryIntervalOfTheStep() {
        let plan = Plan(name: "HIIT", blocks: [
            PlanBlock(name: "Intervals", steps: [
                PlanStep(label: "Burpee", sets: 2, mode: .time, duration: 20, intensity: .hard),
                PlanStep(label: "Plank", mode: .time, duration: 45),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.map(\.intensity), [.hard, .hard, nil])
        XCTAssertNil(intervals[2].intensity, "a step that declared nothing invents nothing")
    }

    /// Effort sits between the set count and the round count. A set number is progress — "set 2
    /// of 4" is how much is left — while a round number and the effort are both things you want
    /// mid-interval, and the effort wins because a HIIT block is where the two collide.
    func testEffortSitsBetweenTheSetCountAndTheRoundCount() {
        let sixRounds = Plan(name: "P", blocks: [
            PlanBlock(name: "HIIT", rounds: 6, steps: [
                PlanStep(label: "Burpee", mode: .time, duration: 20, intensity: .hard),
            ]),
        ])
        XCTAssertEqual(
            PlanFlattener.flatten(sixRounds, exercises: [:])[0].contextLabel, "hard",
            "six rounds and one set: the effort is what the line is for"
        )

        let threeSets = Plan(name: "P", blocks: [
            PlanBlock(name: "Finisher", steps: [
                PlanStep(label: "Plank", sets: 3, mode: .time, duration: 45, intensity: .medium),
            ]),
        ])
        XCTAssertEqual(
            PlanFlattener.flatten(threeSets, exercises: [:])[0].contextLabel, "Set 1 of 3",
            "a set count is progress, and progress outranks effort"
        )
    }

    // MARK: - Block rounds ("6 x (20s hard, 40s easy)")

    /// A block is a *group* that repeats — the other shape a programme uses.
    func testBlockRoundsRepeatTheWholeGroup() {
        let plan = Plan(name: "HIIT", blocks: [
            PlanBlock(name: "Intervals", rounds: 6, steps: [
                PlanStep(label: "Hard — 20 sec", mode: .time, duration: 20),
                PlanStep(label: "Easy — 40 sec", mode: .time, duration: 40),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 12, "6 rounds x 2 steps, no rests at all")
        XCTAssertEqual(intervals.map(\.blockRound), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6])
        XCTAssertEqual(intervals.map(\.setIndex), Array(repeating: 1, count: 12), "each step runs once per round")
        XCTAssertEqual(intervals[0].name, "Hard — 20 sec")
        XCTAssertEqual(intervals[1].duration, 40)
    }

    func testCircuitOfFourRepeatedThreeTimes() {
        let plan = Plan(name: "Circuit", blocks: [
            PlanBlock(rounds: 3, steps: (1...4).map { n in
                PlanStep(label: "Move \(n)", mode: .time, duration: 40, restAfter: 20)
            }),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 24, "3 rounds x (4 moves + 4 rests)")
        XCTAssertEqual(intervals.filter { $0.kind == .rest }.count, 12)
        XCTAssertEqual(intervals[0].name, "Move 1")
        XCTAssertEqual(intervals[1].duration, 20)
    }

    // MARK: - The two rest mechanisms

    func testBlockRestFiresOnlyBetweenRoundsNeverAfterTheLast() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 3, restBetweenRounds: 60, steps: [
                PlanStep(label: "A", mode: .time, duration: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 5, "3 work + 2 rests — never a trailing rest")
        XCTAssertEqual(intervals.last?.kind, .exercise)
        XCTAssertEqual(intervals.map(\.kind), [.exercise, .rest, .exercise, .rest, .exercise])
    }

    func testBlockRestIsMeaninglessWithOneRound() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, restBetweenRounds: 60, steps: [
                PlanStep(label: "A", mode: .time, duration: 30),
            ]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan, exercises: [:]).count, 1)
    }

    // MARK: - Both at once

    /// A block that repeats, containing an exercise that repeats — the two nest.
    func testStepSetsAndBlockRoundsNest() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 2, restBetweenRounds: 30, steps: [
                PlanStep(label: "A", sets: 2, mode: .time, duration: 10, restAfter: 5),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        // round 1: A, r5, A, r5, then the between-rounds rest
        // round 2: A, r5, A, r5, with no trailing block rest
        XCTAssertEqual(intervals.count, 9)
        XCTAssertEqual(
            intervals.map(\.kind),
            [.exercise, .rest, .exercise, .rest, .rest, .exercise, .rest, .exercise, .rest]
        )
        XCTAssertEqual(intervals.map(\.blockRound), [1, 1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(intervals.map(\.setIndex), [1, 1, 2, 2, 1, 1, 1, 2, 2])
        XCTAssertEqual(intervals.count { $0.duration == 30 }, 1, "exactly one between-rounds rest")
    }

    /// "Set 2 of 4" needs the total, which lives in the plan rather than the interval — so
    /// intervals carry it through.
    func testIntervalsCarryTheTotalsForContextLabels() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 2, steps: [
                PlanStep(label: "Squat", sets: 3, mode: .reps, reps: 8, restAfter: 60),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 12, "3 sets + 3 rests, twice")
        XCTAssertEqual(intervals[0].setIndex, 1)
        XCTAssertEqual(intervals[0].setCount, 3)
        XCTAssertEqual(intervals[0].blockRound, 1)
        XCTAssertEqual(intervals[0].blockRoundCount, 2)

        XCTAssertEqual(intervals[1].kind, .rest)
        XCTAssertEqual(intervals[1].setIndex, 1, "the rest belongs to the set it follows")

        XCTAssertEqual(intervals[5].setIndex, 3)
        XCTAssertEqual(intervals[5].setCount, 3, "even the rest after the final set knows the total")
        XCTAssertEqual(intervals[6].blockRound, 2)
    }

    // MARK: - Rests are emitted, not authored

    /// A rest is no longer something you put in a plan — it is emitted between sets, and
    /// always reads "Break".
    func testSyntheticRestIsLabelledBreak() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Squat", mode: .reps, reps: 10, restAfter: 120)]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[1].kind, .rest)
        XCTAssertEqual(intervals[1].name, "Break")
        XCTAssertEqual(intervals[1].duration, 120)
        XCTAssertNil(intervals[1].reps)
    }

    func testLabelOverridesTheExerciseName() {
        let id = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: id, label: "Warm-up squats", mode: .reps, reps: 5),
            ]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan, exercises: [id: ExerciseInfo(name: "Back Squat")])[0].name, "Warm-up squats")
    }

    /// An exercise deleted out from under a plan must still let the workout run.
    func testUnknownExerciseFallsBackToAPlaceholderRatherThanCrashing() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(exerciseID: UUID(), mode: .reps, reps: 5)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan, exercises: [:]).first?.name, "Exercise")
    }

    func testRepStepCarriesWeightAndTimeStepDoesNotCarryReps() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Squat", mode: .reps, reps: 8, targetWeightKg: 60),
                PlanStep(label: "Plank", mode: .time, duration: 45, targetWeightKg: 10),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals[0].targetWeightKg, 60)
        XCTAssertEqual(intervals[0].reps, 8)
        XCTAssertNil(intervals[0].duration)

        XCTAssertEqual(intervals[1].duration, 45)
        XCTAssertNil(intervals[1].reps)
    }

    func testMultipleBlocksConcatenateInOrder() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(name: "Warm-up", steps: [PlanStep(label: "Jumping Jack", mode: .time, duration: 60)]),
            PlanBlock(name: "Main", rounds: 2, steps: [PlanStep(label: "Squat", mode: .reps, reps: 10)]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.map(\.name), ["Jumping Jack", "Squat", "Squat"])
        XCTAssertEqual(intervals.map(\.blockName), ["Warm-up", "Main", "Main"])
        XCTAssertEqual(intervals.map(\.index), [0, 1, 2], "indices are contiguous across blocks")
    }

    func testEmptyPlanFlattensToNothing() {
        XCTAssertTrue(PlanFlattener.flatten(Plan(name: "Empty"), exercises: [:]).isEmpty)
    }

    func testZeroRoundsIsTreatedAsOne() {
        let zeroBlock = Plan(name: "P", blocks: [
            PlanBlock(rounds: 0, steps: [PlanStep(label: "A", mode: .time, duration: 10)]),
        ])
        XCTAssertEqual(PlanFlattener.flatten(zeroBlock, exercises: [:]).count, 1)

        let zeroStep = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "A", sets: 0, mode: .time, duration: 10)]),
        ])
        XCTAssertEqual(PlanFlattener.flatten(zeroStep, exercises: [:]).count, 1)
    }

    // MARK: - Display

    func testRepsAndWeightReachTheInterval() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Flat DB Bench Press", sets: 4, mode: .reps,
                         reps: 8, targetWeightKg: 20, restAfter: 90),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertEqual(intervals.count, 8, "4 sets + 4 rests")
        XCTAssertEqual(intervals[0].repsDisplay, "8 reps")
        XCTAssertEqual(intervals[0].weightDisplay, "20 kg")
    }

    func testFractionalWeightReadsCleanly() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Lateral Raise", mode: .reps,
                                       reps: 12, targetWeightKg: 7.5)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan, exercises: [:])[0].weightDisplay, "7.5 kg")
    }

    func testWholeWeightHasNoTrailingDecimal() {
        XCTAssertEqual(MeasurementFormat.weight(20), "20 kg")
        XCTAssertEqual(MeasurementFormat.weight(7.5), "7.5 kg")
    }

    func testRepsAndWeightDoNotLeakOntoTimedOrRestIntervals() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Plank", mode: .time, duration: 45, restAfter: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        XCTAssertNil(intervals[0].repsDisplay, "a timed step has no rep target")
        XCTAssertNil(intervals[1].repsDisplay, "nor does the rest it emits")
    }

    func testContextLabelPrefersTheSetCountThenTheRoundThenTheBlockName() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(name: "Main", rounds: 2, steps: [
                PlanStep(label: "Squat", sets: 3, mode: .reps, reps: 10),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exercises: [:])

        // 3 sets of one exercise in a 2-round block: the more specific count wins.
        XCTAssertEqual(intervals[0].contextLabel, "Set 1 of 3")
        XCTAssertEqual(intervals[2].contextLabel, "Set 3 of 3")

        // A lone exercise with no repeats falls back to the block's name.
        let plain = PlanFlattener.flatten(Plan(name: "P", blocks: [
            PlanBlock(name: "Finisher", steps: [PlanStep(label: "Plank", mode: .time, duration: 60)]),
        ]), exercises: [:])
        XCTAssertEqual(plain[0].contextLabel, "Finisher")
    }

    func testClockRoundsUpSoItNeverReadsZeroWhileTimeRemains() {
        XCTAssertEqual(MeasurementFormat.clock(remaining: 65), "1:05")
        XCTAssertEqual(MeasurementFormat.clock(remaining: 0.4), "0:01")
        XCTAssertEqual(MeasurementFormat.clock(remaining: 0), "0:00")
        XCTAssertEqual(MeasurementFormat.clock(remaining: -5), "0:00", "a late tick never shows a negative clock")
    }

    func testStepWithNoLoadHasNoWeightDisplay() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Push-Up", mode: .reps, reps: 12)]),
        ])

        XCTAssertNil(PlanFlattener.flatten(plan, exercises: [:])[0].weightDisplay)
    }
}
