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
