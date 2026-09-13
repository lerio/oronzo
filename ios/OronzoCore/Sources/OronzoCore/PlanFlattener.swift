import Foundation

/// Turns a plan into the ordered sequence of intervals the engine executes.
///
/// This is *the* contract of the project — the web preview, the iOS engine and the Watch
/// all consume its output, and `supabase/migrations/0001_init.sql` documents the same rule
/// in SQL comments. Change it in one place and you must change it in all of them.
///
///     for block in blocks ordered by position:
///       for round in 1...block.rounds:
///         for step in steps ordered by position:
///           emit step; if step.restAfter: emit rest
///         if round < block.rounds and block.restBetweenRounds: emit rest
///
/// The asymmetry is deliberate and load-bearing:
///
/// * `restAfter` **does** fire after the final step of a round — usually what you want,
///   since it doubles as the rest before the next round.
/// * `restBetweenRounds` fires **only between** rounds, never after the last one.
///
/// Making both fire would produce double rests that are miserable to debug in the editor.
public enum PlanFlattener {

    public static let restLabel = "Break"

    public static func flatten(_ plan: Plan, exerciseNames: [UUID: String] = [:]) -> [Interval] {
        var intervals: [Interval] = []

        for (blockIndex, block) in plan.blocks.enumerated() {
            let rounds = max(1, block.rounds)

            for round in 1...rounds {
                for step in block.steps {
                    intervals.append(
                        interval(
                            for: step,
                            index: intervals.count,
                            round: round,
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
                                round: round,
                                blockIndex: blockIndex,
                                block: block
                            )
                        )
                    }
                }

                let isFinalRound = round == rounds
                if !isFinalRound, let between = block.restBetweenRounds, between > 0 {
                    intervals.append(
                        restInterval(
                            index: intervals.count,
                            duration: between,
                            round: round,
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
            blockIndex: blockIndex,
            blockName: block.name,
            exerciseID: isRest ? nil : step.exerciseID
        )
    }

    private static func restInterval(
        index: Int,
        duration: TimeInterval,
        round: Int,
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
            blockIndex: blockIndex,
            blockName: block.name,
            exerciseID: nil
        )
    }
}
