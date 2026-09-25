import XCTest
@testable import OronzoCore

/// The numbers the plan summary and the plan-list row show before a workout starts.
///
/// Two things earn their tests here. The first is that **rep-based work is counted at all**:
/// a rep-based step has no duration in the data, and ignoring it is what made the estimate for
/// a 50-minute workout read as 33. The second is the pace itself, which is calibrated against
/// one real session rather than derived, and so is worth pinning down where it can be seen.
final class PlanSummaryTests: XCTestCase {

    /// Every test here summarises a plan it built itself, and only the two-sided ones need
    /// exercise info at all. One helper keeps each test about what it asserts — the default is
    /// test-local on purpose, unlike the production initialiser, which requires the map so no
    /// call site can quietly under-count.
    private func summary(of plan: Plan, exercises: [UUID: ExerciseInfo] = [:]) -> PlanSummary {
        PlanSummary(
            plan: plan,
            intervals: PlanFlattener.flatten(plan, exercises: exercises),
            exercises: exercises
        )
    }

    // MARK: - Counting

    func testEmptyPlanSumsToNothingAndSaysSo() {
        let plan = Plan(name: "Empty")

        let summary = summary(of: plan)

        XCTAssertEqual(summary.blockCount, 0)
        XCTAssertEqual(summary.exerciseCount, 0)
        XCTAssertEqual(summary.timedSeconds, 0)
        XCTAssertFalse(summary.hasEstimatedWork, "nothing is estimated if there is nothing")
        XCTAssertNil(summary.durationText)
        XCTAssertEqual(summary.metaLine, "0 blocks · 0 exercises")
    }

    /// A block's `rounds` repeats its steps, so the interval stream is longer than the plan —
    /// but the counts describe the plan as authored, which is what the summary lists.
    func testRoundsAndSetsLengthenTheTimedSumButNotTheCounts() {
        let plan = Plan(name: "HIIT", blocks: [
            PlanBlock(name: "Main", rounds: 3, steps: [
                PlanStep(label: "Hard", sets: 1, mode: .time, duration: 20),
            ]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.blockCount, 1)
        XCTAssertEqual(summary.exerciseCount, 1, "one step is listed once, not once per round")
        XCTAssertEqual(summary.timedSeconds, 60, "3 rounds x 20s")
    }

    /// Rests count toward the time. They are part of the workout, and the flattener emits them
    /// as real intervals — this is the reason the sum comes from the stream rather than the plan.
    func testRestsAreIncludedInTheTimedSum() {
        let plan = Plan(name: "Sets", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Squat", sets: 4, mode: .time, duration: 30, restAfter: 15),
            ]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.timedSeconds, 180, "4 x (30s work + 15s rest)")
    }

    // MARK: - Rep-based work

    /// The regression this exists for: rep-based work used to contribute nothing, so a plan of
    /// six rep exercises read as though only its rests and its HIIT existed.
    func testRepBasedSetsAddWorkingTime() {
        let plan = Plan(name: "Sets", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Bench", sets: 4, mode: .reps, reps: 6, restAfter: 90),
            ]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.timedSeconds, 360, accuracy: 0.001, "four 90s rests, and no work")
        XCTAssertEqual(summary.repSeconds, 4 * 6 * PlanSummary.secondsPerRep, accuracy: 0.001)
        XCTAssertTrue(summary.hasEstimatedWork, "an estimated pace is not a known duration")
    }

    // MARK: - The duration claim

    /// A plan that is entirely timed gets an unqualified number — the data can prove it.
    func testFullyTimedPlanStatesItsDurationWithoutHedging() {
        let plan = Plan(name: "Timed", blocks: [
            PlanBlock(name: "Warm-up", steps: [PlanStep(label: "Easy", mode: .time, duration: 120)]),
            PlanBlock(name: "Main", steps: [PlanStep(label: "Hard", mode: .time, duration: 480)]),
        ])

        let summary = summary(of: plan)

        XCTAssertFalse(summary.hasEstimatedWork)
        XCTAssertEqual(summary.durationText, "10 min")
        XCTAssertEqual(summary.metaLine, "10 min · 2 blocks · 2 exercises")
    }

    /// The case the `~` exists for: rep-based work is a pace assumption, not a measurement.
    func testRepBasedWorkMarksTheDurationApproximate() {
        let plan = Plan(name: "Mixed", blocks: [
            PlanBlock(name: "Warm-up", steps: [PlanStep(label: "Easy", mode: .time, duration: 120)]),
            PlanBlock(name: "Main", steps: [PlanStep(label: "Bench", mode: .reps, reps: 8)]),
        ])

        let summary = summary(of: plan)

        XCTAssertTrue(summary.hasEstimatedWork)
        XCTAssertEqual(summary.durationText, "~2 min", "120s timed plus 8 reps at the pace")
        XCTAssertEqual(summary.metaLine, "~2 min · 2 blocks · 2 exercises")
    }

    /// A plan with no timed work at all still has a duration now — this is the case that used
    /// to state nothing, which is the least useful answer available.
    func testAllRepPlanIsEstimatedFromThePace() {
        let plan = Plan(name: "Reps only", blocks: [
            PlanBlock(steps: [PlanStep(label: "Bench", sets: 3, mode: .reps, reps: 8)]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.timedSeconds, 0)
        XCTAssertTrue(summary.hasEstimatedWork)
        XCTAssertEqual(summary.durationText, "~1 min", "24 reps at the pace")
        XCTAssertEqual(summary.metaLine, "~1 min · 1 block · 1 exercise")
    }

    /// Below a minute the spelling switches to seconds rather than rounding to "0 min".
    func testSubMinuteTimedPlanReadsInSeconds() {
        let plan = Plan(name: "Short", blocks: [
            PlanBlock(steps: [PlanStep(label: "Sprint", mode: .time, duration: 45)]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.durationText, "45s")
        XCTAssertEqual(summary.metaLine, "45s · 1 block · 1 exercise")
    }

    /// A `.time` step missing its duration contributes nothing and cannot be estimated either,
    /// so it is the one shape where the total really is a floor. Flagged, not silently summed.
    func testTimedStepWithoutADurationIsAlsoTreatedAsEstimated() {
        let plan = Plan(name: "Incomplete", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Hold", mode: .time, duration: nil),
                PlanStep(label: "Easy", mode: .time, duration: 120),
            ]),
        ])

        let summary = summary(of: plan)

        XCTAssertTrue(summary.hasEstimatedWork)
        XCTAssertEqual(summary.durationText, "~2 min")
    }

    // MARK: - Two-sided exercises

    /// A two-sided *timed* exercise doubles its work and leaves the rests alone: the duration is
    /// held per side, and the rest still falls once per set.
    func testATwoSidedTimedExerciseDoublesItsWorkButNotItsRests() {
        let plank = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: plank, sets: 2, mode: .time, duration: 45, restAfter: 30),
            ]),
        ])

        let oneSided = summary(of: plan, exercises: [plank: ExerciseInfo(name: "Side Plank")])
        let twoSided = summary(of: plan, exercises: [plank: ExerciseInfo(name: "Side Plank", hasTwoSides: true)])

        XCTAssertEqual(oneSided.timedSeconds, 45 * 2 + 30 * 2)
        XCTAssertEqual(twoSided.timedSeconds, 45 * 2 * 2 + 30 * 2, "two holds per set, one rest per set")
    }

    /// The rep half is estimated from the *plan* rather than from the emitted intervals, so it has
    /// to be told about the sides. Otherwise the two halves of one number would disagree about the
    /// same step, and every two-sided rep exercise would read short by half its work.
    func testATwoSidedRepExerciseDoublesTheRepHalfOfTheEstimate() {
        let lunge = UUID()
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(exerciseID: lunge, sets: 3, mode: .reps, reps: 8, restAfter: 60),
            ]),
        ])

        let oneSided = summary(of: plan, exercises: [lunge: ExerciseInfo(name: "Reverse Lunge")])
        let twoSided = summary(of: plan, exercises: [lunge: ExerciseInfo(name: "Reverse Lunge", hasTwoSides: true)])

        XCTAssertEqual(oneSided.repSeconds, Double(3 * 8) * PlanSummary.secondsPerRep)
        XCTAssertEqual(twoSided.repSeconds, Double(3 * 8 * 2) * PlanSummary.secondsPerRep)
        XCTAssertEqual(oneSided.timedSeconds, twoSided.timedSeconds, "the rest is once per set either way")
        XCTAssertEqual(twoSided.exerciseCount, 1, "still one exercise as authored, not two")
    }

    // MARK: - The calibration

    /// `secondsPerRep` is calibrated, not derived, so the number it produces is the thing worth
    /// asserting — a refactor that quietly halves the rep allowance should fail here.
    ///
    /// The shape below is the Monday plan's arithmetic without its detail:
    /// `supabase/plans/monday-upper-body-a.sql` sums to 1950s of timed work and rest across 202
    /// reps, and its own notes budget it at "roughly 45–50 min". The estimate belongs at the
    /// low end of that range — an estimate read before a workout should be met without rushing.
    func testThePaceIsCalibratedToTheMondayPlan() {
        let plan = Plan(name: "Monday — Upper Body A + HIIT", blocks: [
            PlanBlock(name: "Timed work and rest", steps: [
                PlanStep(label: "All of it", mode: .time, duration: 1950),
            ]),
            PlanBlock(name: "Rep-based work", steps: [
                PlanStep(label: "All of it", mode: .reps, reps: 202),
            ]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.timedSeconds, 1950, accuracy: 0.001)
        XCTAssertEqual(summary.repSeconds, 747.4, accuracy: 0.001)
        XCTAssertEqual(summary.durationText, "~45 min")
    }

    // MARK: - Singulars

    func testOneOfEachReadsInTheSingular() {
        let plan = Plan(name: "One", blocks: [
            PlanBlock(steps: [PlanStep(label: "Squat", mode: .time, duration: 60)]),
        ])

        let summary = summary(of: plan)

        XCTAssertEqual(summary.metaLine, "1 min · 1 block · 1 exercise")
    }

    // MARK: - The spoken line

    /// VoiceOver reads `~` as "tilde" and `min` as an abbreviation, so the meta line needs a
    /// twin. Everything else about it must agree with what is on screen — two roundings that
    /// disagreed would be worse than no spoken line at all.
    func testSpokenMetaLineExpandsTheSymbolsVoiceOverWouldMisread() {
        let mixed = Plan(name: "Mixed", blocks: [
            PlanBlock(name: "Warm-up", steps: [PlanStep(label: "Easy", mode: .time, duration: 120)]),
            PlanBlock(name: "Main", steps: [PlanStep(label: "Bench", mode: .reps, reps: 8)]),
        ])

        XCTAssertEqual(
            summary(of: mixed).spokenMetaLine,
            "about 2 minutes, 2 blocks, 2 exercises"
        )

        let exact = Plan(name: "Timed", blocks: [
            PlanBlock(steps: [PlanStep(label: "Sprint", mode: .time, duration: 60)]),
        ])

        XCTAssertEqual(
            summary(of: exact).spokenMetaLine,
            "1 minute, 1 block, 1 exercise",
            "no hedge when the total is the whole plan"
        )
    }

    /// The written and spoken forms are the same number. The units are spelled differently on
    /// purpose — "45s" is written, "45 seconds" is spoken — so the number is what must agree.
    func testSpokenAndWrittenDurationsAgree() {
        for seconds: TimeInterval in [30, 45, 60, 90, 150, 599, 3599] {
            let plan = Plan(name: "P", blocks: [
                PlanBlock(steps: [PlanStep(label: "Hold", mode: .time, duration: seconds)]),
            ])
            let summary = summary(of: plan)

            guard let written = summary.durationText else {
                return XCTFail("\(seconds)s is fully timed and should state a duration")
            }

            XCTAssertEqual(
                String(written.prefix { $0.isNumber }),
                String(summary.spokenMetaLine.prefix { $0.isNumber }),
                "\(seconds)s: written \"\(written)\" and spoken \"\(summary.spokenMetaLine)\" disagree"
            )
        }
    }

    // MARK: - The name a step is listed under

    /// The plan summary lists steps straight off the `Plan`, so it asks the flattener what to
    /// call them. This is the same precedence the executed session uses, which is the point:
    /// the summary and the workout cannot name the same step differently.
    func testStepNamePrefersTheLabelThenTheExerciseTable() {
        let id = UUID()

        XCTAssertEqual(
            PlanFlattener.name(for: PlanStep(exerciseID: id, label: "Warm-up squats"), exercises: [id: ExerciseInfo(name: "Back Squat")]),
            "Warm-up squats",
            "an explicit label wins"
        )
        XCTAssertEqual(
            PlanFlattener.name(for: PlanStep(exerciseID: id), exercises: [id: ExerciseInfo(name: "Back Squat")]),
            "Back Squat",
            "the exercise table is the branch that actually runs — the builder never sets label"
        )
        XCTAssertEqual(
            PlanFlattener.name(for: PlanStep(exerciseID: UUID()), exercises: [:]),
            "Exercise",
            "a deleted exercise still lets the workout run"
        )
    }
}
