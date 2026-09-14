import Foundation

/// Turns a plan into the ordered sequence of intervals the engine executes.
///
/// This is *the* contract of the project — the web preview, the iOS engine and the Watch
/// all consume its output, and `supabase/migrations/0005_step_sets.sql` documents the same
/// rule in SQL comments. Change it in one place and change it in all of them.
///
///     for block in blocks ordered by position:
///       for blockRound in 1...block.rounds:
///         for step in steps ordered by position:
///           for setIndex in 1...step.sets:
///             emit step
///             if step.restAfter: emit rest
///         if blockRound < block.rounds and block.restBetweenRounds: emit rest
///
/// **Sets and rounds are different things**, deliberately:
///
/// * `step.sets` — an exercise repeating: `"4 x 6-8 bench press"`. The set count belongs to
///   the exercise, so it does not need a block wrapped around one thing.
/// * `block.rounds` — a *group* repeating: `"6 x (20s hard, 40s easy)"`.
///
/// The two rest mechanisms differ too:
///
/// * `restAfter` on a step fires after **every** set, including the last, so an exercise's
///   rest carries you into the next exercise. Four sets means four rests.
/// * `restBetweenRounds` on a block fires **only between** rounds of that block, never
///   after the final one.
public enum PlanFlattener {

    public static let restLabel = "Break"

    public static func flatten(_ plan: Plan, exerciseNames: [UUID: String] = [:]) -> [Interval] {
        var intervals: [Interval] = []

        for (blockIndex, block) in plan.blocks.enumerated() {
            let blockRounds = max(1, block.rounds)

            for blockRound in 1...blockRounds {
                for step in block.steps {
                    for setIndex in 1...max(1, step.sets) {
                        intervals.append(
                            interval(
                                for: step,
                                index: intervals.count,
                                setIndex: setIndex,
                                blockRound: blockRound,
                                blockIndex: blockIndex,
                                block: block,
                                exerciseNames: exerciseNames
                            )
                        )

                        if let rest = step.restAfter, rest > 0 {
                            intervals.append(
                                restInterval(
                                    index: intervals.count,
                                    duration: rest,
                                    setIndex: setIndex,
                                    blockRound: blockRound,
                                    blockIndex: blockIndex,
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
                            blockRound: blockRound,
                            blockIndex: blockIndex,
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
        blockRound: Int,
        blockIndex: Int,
        block: PlanBlock,
        exerciseNames: [UUID: String]
    ) -> Interval {
        let isRest = step.kind == .rest

        let name: String
        if isRest {
            name = step.label ?? restLabel
        } else if let label = step.label {
            name = label
        } else if let id = step.exerciseID, let known = exerciseNames[id] {
            name = known
        } else {
            // A placeholder rather than a crash: an exercise deleted out from under a plan
            // should still let the workout run.
            name = "Exercise"
        }

        let duration: TimeInterval? = isRest
            ? step.duration
            : (step.mode == .time ? step.duration : nil)

        return Interval(
            index: index,
            kind: step.kind,
            name: name,
            mode: isRest ? .time : step.mode,
            duration: duration,
            reps: isRest ? nil : (step.mode == .reps ? step.reps : nil),
            targetWeightKg: isRest ? nil : step.targetWeightKg,
            setIndex: setIndex,
            blockRound: blockRound,
            blockIndex: blockIndex,
            blockName: block.name,
            exerciseID: isRest ? nil : step.exerciseID
        )
    }

    /// The synthetic rest emitted for `restAfter` / `restBetweenRounds`.
    private static func restInterval(
        index: Int,
        duration: TimeInterval,
        setIndex: Int,
        blockRound: Int,
        blockIndex: Int,
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
            blockRound: blockRound,
            blockIndex: blockIndex,
            blockName: block.name,
            exerciseID: nil
        )
    }
}
