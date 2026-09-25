import Foundation

/// Turns a plan into the ordered sequence of intervals the engine executes.
///
/// This is *the* contract of the project — the web preview, the iOS engine and the Watch
/// all consume its output, and `web/src/lib/types.ts` restates the same rule in TypeScript.
/// The statement of record is `AGENTS.md`; the migrations describe the *shape* a plan is stored
/// in, and their comments stopped tracking this loop several migrations ago (`0005` has `sets`
/// but not the sides, `0001` has a loop but neither). Change the rule here and in `types.ts`,
/// and change `AGENTS.md` with it.
///
///     for block in blocks ordered by position:
///       for blockRound in 1...block.rounds:
///         for step in steps ordered by position:
///           for setIndex in 1...step.sets:
///             for side in sideSuffixes(of: step, exercises:):  // [nil], or [left, right]
///               emit step, named "… (left)" / "… (right)" when there is a side
///             if step.restAfter: emit rest        // once per set, after the pair
///         if blockRound < block.rounds and block.restBetweenRounds: emit rest
///
/// **Sets and rounds are different things**, deliberately:
///
/// * `step.sets` — an exercise repeating: `"4 x 8 bench press"`. The set count belongs to
///   the exercise, so it does not need a block wrapped around one thing.
/// * `block.rounds` — a *group* repeating: `"6 x (20s hard, 40s easy)"`.
/// * A two-sided exercise is neither: it doubles *within* a set, and the doubled pair shares
///   the set's index. See `sideSuffixes`.
///
/// The two rest mechanisms differ too:
///
/// * `restAfter` on a step fires after **every** set, including the last, so an exercise's
///   rest carries you into the next exercise. Four sets means four rests.
/// * `restBetweenRounds` on a block fires **only between** rounds of that block, never
///   after the final one.
public enum PlanFlattener {

    /// What a rest is called, wherever it is drawn. Private because it is only ever written into an
    /// `Interval`'s name here — nothing outside needs to spell it a second way, which is the point.
    private static let restLabel = "Break"

    /// What to call a step.
    ///
    /// Public because the plan summary on the phone lists steps straight off the `Plan`, and a
    /// name resolved a second way there would be a second answer: the summary would say one
    /// thing and the workout that follows it another. Today `label` is `null` on every step the
    /// builder writes (`docs/known-issues.md` §1 — no input sets it), so the exercise table is
    /// the branch that actually runs.
    ///
    /// **Side-free, deliberately:** the side belongs to an *interval* being done, not to the step
    /// being planned, and `PlanDetailView` lists a plan as authored. Only `interval(for:...)`
    /// appends a suffix.
    ///
    /// The placeholder is deliberate: an exercise deleted out from under a plan should still let
    /// the workout run.
    public static func name(for step: PlanStep, exercises: [UUID: ExerciseInfo]) -> String {
        if let label = step.label {
            return label
        }
        if let id = step.exerciseID, let known = exercises[id] {
            return known.name
        }
        return "Exercise"
    }

    /// The name suffixes a step is performed with, in order: one entry — `nil`, meaning no suffix
    /// — when the exercise is done once, two when it is done per side.
    ///
    /// This is the whole of "has two sides" as the engine sees it. `PlanSummary` reads `.count`
    /// from it rather than working out the rule again, because the flattener emits that many
    /// intervals and an estimate that counted one of them would quietly disagree with the
    /// session it is describing.
    ///
    /// The spelling is duplicated in `web/src/lib/types.ts` deliberately, exactly as `restLabel`
    /// and `REST_LABEL` are: the two flatteners are the same rule written twice, and the strings
    /// it writes into an interval are part of what the rule says.
    public static func sideSuffixes(of step: PlanStep, exercises: [UUID: ExerciseInfo]) -> [String?] {
        guard let id = step.exerciseID, exercises[id]?.hasTwoSides == true else { return [nil] }
        return ["left", "right"]
    }

    /// No default on `exercises`, deliberately, though every other argument here has one.
    ///
    /// A missing *name* map degrades visibly: every interval is called "Exercise" and someone
    /// notices. A missing *sides* map is invisible — the step silently flattens once, and only
    /// the person mid-workout finds out. So the map is required and the compiler visits every
    /// call site instead. `PlanStore` is the one place that builds it from disk, and it discards
    /// a cache it cannot read in full rather than handing over a map with the flag missing.
    public static func flatten(_ plan: Plan, exercises: [UUID: ExerciseInfo]) -> [Interval] {
        var intervals: [Interval] = []

        for block in plan.blocks {
            let blockRounds = max(1, block.rounds)

            for blockRound in 1...blockRounds {
                for step in block.steps {
                    for setIndex in 1...max(1, step.sets) {
                        // A two-sided exercise emits both sides here, so the rest below still
                        // falls once per set — after the pair, which is what "a set of lunges"
                        // means when you are the one doing them.
                        for side in sideSuffixes(of: step, exercises: exercises) {
                            intervals.append(
                                interval(
                                    for: step,
                                    index: intervals.count,
                                    setIndex: setIndex,
                                    side: side,
                                    blockRound: blockRound,
                                    blockRoundCount: blockRounds,
                                    block: block,
                                    exercises: exercises
                                )
                            )
                        }

                        if let rest = step.restAfter, rest > 0 {
                            intervals.append(
                                restInterval(
                                    index: intervals.count,
                                    duration: rest,
                                    setIndex: setIndex,
                                    setCount: max(1, step.sets),
                                    blockRound: blockRound,
                                    blockRoundCount: blockRounds,
                                    block: block
                                )
                            )
                        }
                    }
                }

                let isFinalRound = blockRound == blockRounds
                if !isFinalRound, let between = block.restBetweenRounds, between > 0 {
                    intervals.append(
                        restInterval(
                            index: intervals.count,
                            duration: between,
                            setIndex: blockRound,
                            setCount: 1,
                            blockRound: blockRound,
                            blockRoundCount: blockRounds,
                            block: block
                        )
                    )
                }
            }
        }

        return intervals
    }

    private static func interval(
        for step: PlanStep,
        index: Int,
        setIndex: Int,
        side: String?,
        blockRound: Int,
        blockRoundCount: Int,
        block: PlanBlock,
        exercises: [UUID: ExerciseInfo]
    ) -> Interval {
        // The side rides in the name rather than in a field of its own: `Interval` is `Codable`
        // and shipped whole in every snapshot to the watch, so a new field would fail to decode
        // the ones already in flight — which shows up as a silent "No workout" on the wrist.
        let base = name(for: step, exercises: exercises)
        let name = side.map { "\(base) (\($0))" } ?? base

        return Interval(
            index: index,
            kind: .exercise,
            name: name,
            mode: step.mode,
            duration: step.mode == .time ? step.duration : nil,
            reps: step.mode == .reps ? step.reps : nil,
            targetWeightKg: step.targetWeightKg,
            setIndex: setIndex,
            setCount: max(1, step.sets),
            blockRound: blockRound,
            blockRoundCount: blockRoundCount,
            blockName: block.name,
            exerciseID: step.exerciseID,
            // Carried straight through: it is the step's own word, and nothing decides it here.
            intensity: step.intensity
        )
    }

    /// The synthetic rest emitted for `restAfter` / `restBetweenRounds`.
    private static func restInterval(
        index: Int,
        duration: TimeInterval,
        setIndex: Int,
        setCount: Int,
        blockRound: Int,
        blockRoundCount: Int,
        block: PlanBlock
    ) -> Interval {
        Interval(
            index: index,
            kind: .rest,
            name: restLabel,
            mode: .time,
            duration: duration,
            reps: nil,
            targetWeightKg: nil,
            setIndex: setIndex,
            setCount: setCount,
            blockRound: blockRound,
            blockRoundCount: blockRoundCount,
            blockName: block.name,
            exerciseID: nil
        )
    }
}
