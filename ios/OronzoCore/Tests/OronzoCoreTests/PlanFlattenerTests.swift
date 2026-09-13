import XCTest
@testable import OronzoCore

final class PlanFlattenerTests: XCTestCase {

    // MARK: - The two canonical shapes

    /// "3 sets of 12 squats, 90s rest between sets."
    /// Repetition is the block's `rounds`; there is no separate "sets" concept.
    func testSetsAreExpressedAsRoundsOfOneStep() {
        let squat = UUID()
        let plan = Plan(name: "Squats", blocks: [
            PlanBlock(rounds: 3, restBetweenRounds: 90, steps: [
                PlanStep(exerciseID: squat, kind: .exercise, mode: .reps, reps: 12),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exerciseNames: [squat: "Back Squat"])

        XCTAssertEqual(intervals.count, 5, "3 sets + 2 rests between them")
        XCTAssertEqual(intervals.map(\.kind), [.exercise, .rest, .exercise, .rest, .exercise])
        XCTAssertEqual(intervals.map(\.name), ["Back Squat", "Break", "Back Squat", "Break", "Back Squat"])
        XCTAssertEqual(intervals.map(\.roundIndex), [1, 1, 2, 2, 3])
        XCTAssertEqual(intervals[0].reps, 12)
        XCTAssertNil(intervals[0].duration, "a rep interval has no length")
        XCTAssertEqual(intervals[1].duration, 90)
        XCTAssertFalse(intervals[0].advancesAutomatically)
    }

    /// "Circuit of 4 exercises x 3 rounds, 20s between exercises."
    func testCircuitOfFourRepeatedThreeTimes() {
        let plan = Plan(name: "Circuit", blocks: [
            PlanBlock(rounds: 3, steps: (1...4).map { n in
                PlanStep(
                    exerciseID: nil,
                    kind: .exercise,
                    label: "Move \(n)",
                    mode: .time,
                    duration: 40,
                    restAfter: 20
                )
            }),
        ])

        let intervals = PlanFlattener.flatten(plan)

        // 4 moves + 4 rests per round, 3 rounds.
        XCTAssertEqual(intervals.count, 24)
        XCTAssertEqual(intervals.filter { $0.kind == .rest }.count, 12)
        XCTAssertEqual(intervals.filter { $0.kind == .exercise }.count, 12)
        XCTAssertEqual(intervals[0].name, "Move 1")
        XCTAssertEqual(intervals[0].duration, 40)
        XCTAssertEqual(intervals[1].kind, .rest)
        XCTAssertEqual(intervals[1].duration, 20)
        XCTAssertTrue(intervals[0].advancesAutomatically)
    }

    // MARK: - The documented asymmetry between the two rest mechanisms

    func testRestAfterFiresEvenOnTheLastStepOfARound() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 2, steps: [
                PlanStep(kind: .exercise, label: "A", mode: .time, duration: 30, restAfter: 15),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        // [A, rest, A, rest] — the rest after round 1's step is the rest before round 2.
        XCTAssertEqual(intervals.count, 4)
        XCTAssertEqual(intervals.map(\.kind), [.exercise, .rest, .exercise, .rest])
    }

    func testRestBetweenRoundsDoesNotFireAfterTheFinalRound() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 3, restBetweenRounds: 60, steps: [
                PlanStep(kind: .exercise, label: "A", mode: .time, duration: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 5, "3 work + 2 rests — never a trailing rest")
        XCTAssertEqual(intervals.last?.kind, .exercise)
    }

    func testSingleRoundProducesNoRestsAtAll() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, restBetweenRounds: 60, steps: [
                PlanStep(kind: .exercise, label: "A", mode: .time, duration: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 1, "rest_between_rounds is meaningless with one round")
        XCTAssertEqual(intervals[0].kind, .exercise)
    }

    // MARK: - Rest steps and naming

    func testExplicitRestStepIsEmittedWithItsOwnLabel() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(kind: .exercise, label: "Squat", mode: .reps, reps: 10),
                PlanStep(kind: .rest, label: "Breathe", mode: .time, duration: 120),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[1].kind, .rest)
        XCTAssertEqual(intervals[1].name, "Breathe")
        XCTAssertEqual(intervals[1].duration, 120)
        XCTAssertNil(intervals[1].reps)
    }

    func testUnlabelledRestFallsBackToBreak() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [PlanStep(kind: .rest, mode: .time, duration: 30)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan).first?.name, "Break")
    }

    func testLabelOverridesTheExerciseName() {
        let id = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(exerciseID: id, kind: .exercise, label: "Warm-up squats", mode: .reps, reps: 5),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan, exerciseNames: [id: "Back Squat"])

        XCTAssertEqual(intervals[0].name, "Warm-up squats")
    }

    /// An exercise deleted out from under a plan must still let the workout run.
    func testUnknownExerciseFallsBackToAPlaceholderRatherThanCrashing() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(exerciseID: UUID(), kind: .exercise, mode: .reps, reps: 5),
            ]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan).first?.name, "Exercise")
    }

    func testRepStepCarriesWeightAndTimeStepDoesNotCarryReps() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(kind: .exercise, label: "Squat", mode: .reps, reps: 8, targetWeightKg: 60),
                PlanStep(kind: .exercise, label: "Plank", mode: .time, duration: 45, targetWeightKg: 10),
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
            PlanBlock(name: "Warm-up", rounds: 1, steps: [PlanStep(label: "Jumping Jack", mode: .time, duration: 60)]),
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
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 0, steps: [PlanStep(kind: .exercise, label: "A", mode: .time, duration: 10)]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan).count, 1)
    }

    // MARK: - Ranges
    //
    // Hypertrophy programming is written "4 x 6-8" and "50-60 kg". A single integer would
    // misrepresent the prescription, so the ceiling has to survive flattening intact.

    func testRepAndWeightRangesReachTheInterval() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 4, restBetweenRounds: 90, steps: [
                PlanStep(
                    kind: .exercise, label: "Flat DB Bench Press", mode: .reps,
                    reps: 6, repsMax: 8, targetWeightKg: 20, targetWeightMaxKg: nil
                ),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertEqual(intervals.count, 7, "4 sets + 3 rests")
        XCTAssertEqual(intervals[0].reps, 6)
        XCTAssertEqual(intervals[0].repsMax, 8)
        XCTAssertEqual(intervals[0].repsDisplay, "6–8 reps")
        XCTAssertEqual(intervals[0].weightDisplay, "20 kg", "a single load reads without a dash")
        XCTAssertEqual(intervals[0].primaryTarget, "6–8 reps")
    }

    func testWeightRangeDisplaysWithADash() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 4, steps: [
                PlanStep(kind: .exercise, label: "Lat Pulldown", mode: .reps,
                         reps: 6, repsMax: 8, targetWeightKg: 50, targetWeightMaxKg: 60),
            ]),
        ])

        let interval = PlanFlattener.flatten(plan)[0]

        XCTAssertEqual(interval.weightDisplay, "50–60 kg")
        XCTAssertEqual(interval.repsDisplay, "6–8 reps")
    }

    func testFractionalWeightRangeReadsCleanly() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 3, steps: [
                PlanStep(kind: .exercise, label: "Lateral Raise", mode: .reps,
                         reps: 12, repsMax: 15, targetWeightKg: 6, targetWeightMaxKg: 7.5),
            ]),
        ])

        let interval = PlanFlattener.flatten(plan)[0]

        XCTAssertEqual(interval.weightDisplay, "6–7.5 kg", "wholes lose their .0, halves keep theirs")
    }

    func testEqualBoundsAreNotShownAsARange() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(kind: .exercise, label: "A", mode: .reps, reps: 10, repsMax: 10),
            ]),
        ])

        XCTAssertEqual(PlanFlattener.flatten(plan)[0].repsDisplay, "10 reps")
    }

    func testRangesDoNotLeakOntoTimedOrRestIntervals() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(rounds: 1, steps: [
                PlanStep(kind: .exercise, label: "Plank", mode: .time, duration: 45),
                PlanStep(kind: .rest, mode: .time, duration: 30),
            ]),
        ])

        let intervals = PlanFlattener.flatten(plan)

        XCTAssertNil(intervals[0].repsDisplay, "a timed step has no rep target")
        XCTAssertNil(intervals[1].repsDisplay)
        XCTAssertEqual(intervals[0].primaryTarget, "45s")
    }
}
