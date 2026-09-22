#if DEBUG
import Foundation
import OronzoCore
import SwiftUI

/// A plan built in code, so the session runner can be exercised without an account, a
/// backend or a network.
///
/// Launch with `-demoSession` to go straight to the runner, or use the `#Preview` below.
/// Debug builds only — the release build has no such entry point.
enum DemoPlan {

    static var launchArgumentPlan: Plan? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demoSession") { return make() }
        if arguments.contains("-demoFinish") { return short() }
        return nil
    }

    /// `-demoSummary` shows the plan summary rather than the runner. See `RootView`.
    ///
    /// It is a separate plan rather than `make()` because the two exist to show different
    /// things: `make()` sets every step's `label`, and the builder sets **none** of them
    /// (`docs/known-issues.md` §1 — no input in `PlanEditor.tsx` writes the field). So `make()`
    /// never exercises the branch that actually runs in production, where a step is named from
    /// the exercise table. This one is in the shape a real plan arrives in.
    static var wantsSummary: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoSummary")
    }

    /// Stable ids, because the plan and the names it resolves against are built separately.
    private static let benchID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    private static let pulldownID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
    private static let squatID = UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!

    static let builderExerciseNames: [UUID: String] = [
        benchID: "Flat Dumbbell Bench Press",
        pulldownID: "Neutral-Grip Lat Pulldown",
        squatID: "Goblet Squat",
    ]

    /// Shaped the way `save_plan` writes a plan: `exercise_id` set, `label` null throughout.
    static func builderShaped() -> Plan {
        Plan(
            id: UUID(),
            name: "Demo — Built in the web app",
            blocks: [
                PlanBlock(name: "Warm-up", steps: [
                    PlanStep(exerciseID: squatID, mode: .time, duration: 90),
                ]),
                PlanBlock(name: "Main work", steps: [
                    PlanStep(exerciseID: benchID, sets: 4, mode: .reps, reps: 8,
                             targetWeightKg: 20, restAfter: 90),
                    PlanStep(exerciseID: pulldownID, sets: 3, mode: .reps, reps: 10,
                             targetWeightKg: 50, restAfter: 60),
                ]),
                PlanBlock(name: "Finisher", rounds: 4, steps: [
                    PlanStep(exerciseID: squatID, mode: .time, duration: 30, restAfter: 15),
                ]),
            ]
        )
    }

    /// Six seconds end to end, so the finish-and-save path can be exercised without waiting
    /// two minutes for a real warm-up to drain.
    static func short() -> Plan {
        Plan(
            id: UUID(),
            name: "Demo — Finish",
            blocks: [
                PlanBlock(steps: [
                    PlanStep(label: "Sprint", mode: .time, duration: 3),
                    PlanStep(label: "Breathe", mode: .time, duration: 3),
                ]),
            ]
        )
    }

    static func make() -> Plan {
        Plan(
            id: UUID(),
            name: "Demo — Upper Body A",
            blocks: [
                // Leads with a timed step so the countdown is the first thing shown.
                PlanBlock(name: "Warm-up", steps: [
                    PlanStep(label: "Easy — 2 min", mode: .time, duration: 120),
                ]),
                PlanBlock(name: "Main work", steps: [
                    PlanStep(label: "Flat Dumbbell Bench Press", sets: 4, mode: .reps,
                             reps: 8, targetWeightKg: 20, restAfter: 90),
                    PlanStep(label: "Neutral-Grip Lat Pulldown", sets: 4, mode: .reps,
                             reps: 6, targetWeightKg: 50, restAfter: 90),
                ]),
                PlanBlock(name: "HIIT", rounds: 6, steps: [
                    PlanStep(label: "Hard — 20 sec", mode: .time, duration: 20),
                    PlanStep(label: "Easy — 40 sec", mode: .time, duration: 40),
                ]),
            ]
        )
    }
}

#Preview("Session runner") {
    SessionRunner(plan: DemoPlan.make(), exerciseNames: [:])
}
#endif
