import Foundation

/// Turns a plan into the ordered sequence of intervals the engine executes.
///
/// This is *the* contract of the project — the web preview, the iOS engine and the Watch
/// all consume its output, and `supabase/migrations/0005_step_rounds.sql` documents the
/// same rule in SQL comments. Change it in one place and you must change it in all of them.
///
///     for block in blocks ordered by position:
///       for blockRound in 1...block.rounds:
///         for step in steps ordered by position:
///           for stepRound in 1...step.rounds:
///             emit step
///             if step.restAfter: emit rest
///         if blockRound < block.rounds and block.restBetweenRounds: emit rest
///
/// Both a step and a block can repeat, which is what lets the two natural shapes be written
/// the way a programme writes them:
///
/// * `"4 x 6-8 bench press, rest 90s"` — a step with `rounds = 4`. The set count belongs to
///   the exercise, so it no longer needs a block wrapped around one thing.
/// * `"6 x (20s hard, 40s easy)"` — a block with `rounds = 6` holding two steps, i.e. a
///   group that repeats.
///
/// The two rest mechanisms differ deliberately:
///
/// * `restAfter` on a step fires after **every** round, including the last, so an
///   exercise's rest carries you into the next exercise. Four sets means four rests.
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
                    for stepRound in 1...max(1, step.rounds) {
                        intervals.append(
                            interval(
                                for: step,
                                index: intervals.count,
                                round: stepRound,
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
                                    round: stepRound,
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
                            round: blockRound,
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
        round: Int,
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
            roundIndex: round,
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
        round: Int,
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
            roundIndex: round,
            blockRound: blockRound,
            blockIndex: blockIndex,
            blockName: block.name,
            exerciseID: nil
        )
    }
}
