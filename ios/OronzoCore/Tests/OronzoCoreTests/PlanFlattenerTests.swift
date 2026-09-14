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

        let intervals = PlanFlattener.flatten(plan, exerciseNames: [squat: "Back Squat"])

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

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 2, "one set plus its rest")
        XCTAssertEqual(PlanStep(mode: .reps, reps: 5).sets, 1)
    }

    func testStepWithSetsButNoRestEmitsNoRests() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Squat", sets: 4, mode: .reps, reps: 8)]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 4)
        XCTAssertTrue(intervals.allSatisfy { $0.kind == .exercise })
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

        let intervals = PlanFlattener.flatten(plan)

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

        let intervals = PlanFlattener.flatten(plan)

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

        let intervals = PlanFlattener.flatten(plan)

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

        XCTAssertEqual(PlanFlattener.flatten(plan).count, 1)
    }

    // MARK: - Both at once

    /// A block that repeats, containing an exercise that repeats — the two nest.
    func testStepSetsAndBlockRoundsNest() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 2, restBetweenRounds: 30, steps: [
                PlanStep(label: "A", sets: 2, mode: .time, duration: 10, restAfter: 5),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

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

    // MARK: - Rests are emitted, not authored

    /// A rest is no longer something you put in a plan — it is emitted between sets, and
    /// always reads "Break".
    func testSyntheticRestIsLabelledBreak() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Squat", mode: .reps, reps: 10, restAfter: 120)]),
        ])

        let intervals = PlanFlattener.flatten(plan)

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

        XCTAssertEqual(PlanFlattener.flatten(plan, exerciseNames: [id: "Back Squat"])[0].name, "Warm-up squats")
    }

    /// An exercise deleted out from under a plan must still let the workout run.
    func testUnknownExerciseFallsBackToAPlaceholderRatherThanCrashing() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(exerciseID: UUID(), mode: .reps, reps: 5)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan).first?.name, "Exercise")
    }

    func testRepStepCarriesWeightAndTimeStepDoesNotCarryReps() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Squat", mode: .reps, reps: 8, targetWeightKg: 60),
                PlanStep(label: "Plank", mode: .time, duration: 45, targetWeightKg: 10),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

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

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.map(\.name), ["Jumping Jack", "Squat", "Squat"])
        XCTAssertEqual(intervals.map(\.blockName), ["Warm-up", "Main", "Main"])
        XCTAssertEqual(intervals.map(\.blockIndex), [0, 1, 1])
        XCTAssertEqual(intervals.map(\.index), [0, 1, 2], "indices are contiguous across blocks")
    }

    func testEmptyPlanFlattensToNothing() {
        XCTAssertTrue(PlanFlattener.flatten(Plan(name: "Empty")).isEmpty)
    }

    func testZeroRoundsIsTreatedAsOne() {
        let zeroBlock = Plan(name: "P", blocks: [
            PlanBlock(rounds: 0, steps: [PlanStep(label: "A", mode: .time, duration: 10)]),
        ])
        XCTAssertEqual(PlanFlattener.flatten(zeroBlock).count, 1)

        let zeroStep = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "A", sets: 0, mode: .time, duration: 10)]),
        ])
        XCTAssertEqual(PlanFlattener.flatten(zeroStep).count, 1)
    }

    // MARK: - Display

    func testRepsAndWeightReachTheInterval() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Flat DB Bench Press", sets: 4, mode: .reps,
                         reps: 8, targetWeightKg: 20, restAfter: 90),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 8, "4 sets + 4 rests")
        XCTAssertEqual(intervals[0].repsDisplay, "8 reps")
        XCTAssertEqual(intervals[0].weightDisplay, "20 kg")
        XCTAssertEqual(intervals[0].primaryTarget, "8 reps")
    }

    func testFractionalWeightReadsCleanly() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Lateral Raise", mode: .reps,
                                       reps: 12, targetWeightKg: 7.5)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan)[0].weightDisplay, "7.5 kg")
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

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertNil(intervals[0].repsDisplay, "a timed step has no rep target")
        XCTAssertNil(intervals[1].repsDisplay, "nor does the rest it emits")
        XCTAssertEqual(intervals[0].primaryTarget, "45s")
    }

    func testStepWithNoLoadHasNoWeightDisplay() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Push-Up", mode: .reps, reps: 12)]),
        ])

        XCTAssertNil(PlanFlattener.flatten(plan)[0].weightDisplay)
    }
}
