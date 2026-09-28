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
        if arguments.contains("-demoRecord") { return make() }
        if arguments.contains("-demoFinish") { return short() }
        return nil
    }

    /// Whether this launch's demo should be **written down** like a real session.
    ///
    /// `-demoSession` deliberately is not: it is a fixture for looking at the runner, and a record
    /// it left behind would be resumed by the next ordinary launch as a workout nobody started.
    ///
    /// `-demoRecord` is the same session with the record left on — which is the only way to
    /// exercise **resume** without an account and a backend, and resume is the mechanism most worth
    /// exercising. Terminate the app mid-workout and launch it again with no arguments: the runner
    /// comes back at the interval it should be at.
    ///
    /// Delete the record afterwards if you care: launch once more with `-demoSession`, which
    /// clears any record it finds before starting.
    static var persistsRecord: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoRecord")
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

    /// `-demoAdjust` drives the load arrows for you: a nudge, then a save.
    ///
    /// It exists because **the arrows cannot otherwise be looked at.** There is no way to tap a
    /// simulator from here — the machine has no `idb`, no `cliclick`, and no Simulator UI attached
    /// to the booted device — so the pending state and the Adjust button are unreachable by any
    /// route except this one. Which is the same reason the three arguments above exist: the runner
    /// has to be exercisable without an account, a backend, or a finger.
    ///
    /// Two seconds apart, so a screenshot taken in between catches the button that saving removes.
    static var wantsAdjustWalkthrough: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoAdjust")
    }

    /// Stable ids, because the plan and the info it resolves against are built separately.
    private static let benchID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    private static let pulldownID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
    private static let squatID = UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!
    private static let rowID = UUID(uuidString: "00000000-0000-0000-0000-00000000B004")!

    /// Stable **step** ids, in a namespace of their own.
    ///
    /// A step id is what the runner writes a load adjustment back through, so a demo needs one to
    /// exercise the arrows at all — but it must never be able to name a real `plan_steps` row,
    /// even if a launch were somehow signed in. These are fabricated rather than random for
    /// exactly that reason, the same way the exercise ids above are: `00000000-…-000000000001`
    /// cannot collide with a `gen_random_uuid()`. Belt and braces with `SessionController.savesPlan`,
    /// which stops the request being sent at all.
    ///
    /// They also let `make()` show why the id belongs to the *step* and not the exercise: it uses
    /// `squatID` twice, at 120s and again at 6 × 30s, which is exactly the case keying on
    /// `exerciseID` would get wrong.
    private static func stepID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// The exercise table as far as a demo needs it. The row is the one flagged two-sided, which
    /// is what lets a launch-argument session show the left/right pair on a simulator with no
    /// account, no backend and no migration applied.
    static let builderExercises: [UUID: ExerciseInfo] = [
        benchID: ExerciseInfo(name: "Flat Dumbbell Bench Press"),
        pulldownID: ExerciseInfo(name: "Neutral-Grip Lat Pulldown"),
        squatID: ExerciseInfo(name: "Goblet Squat"),
        rowID: ExerciseInfo(name: "One-Arm Dumbbell Row", hasTwoSides: true),
    ]

    /// Shaped the way `save_plan` writes a plan: `exercise_id` set, `label` null throughout.
    static func builderShaped() -> Plan {
        Plan(
            id: UUID(),
            name: "Demo — Built in the web app",
            blocks: [
                PlanBlock(name: "Warm-up", steps: [
                    PlanStep(id: stepID(7), exerciseID: squatID, mode: .time, duration: 90),
                ]),
                PlanBlock(name: "Main work", steps: [
                    PlanStep(id: stepID(8), exerciseID: benchID, sets: 4, mode: .reps, reps: 8,
                             targetWeightKg: 20, restAfter: 90),
                    PlanStep(id: stepID(9), exerciseID: pulldownID, sets: 3, mode: .reps, reps: 10,
                             targetWeightKg: 50, restAfter: 60),
                ]),
                PlanBlock(name: "Finisher", rounds: 4, steps: [
                    PlanStep(id: stepID(10), exerciseID: squatID, mode: .time, duration: 30, restAfter: 15),
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
                    PlanStep(id: stepID(11), label: "Sprint", mode: .time, duration: 3),
                    PlanStep(id: stepID(12), label: "Breathe", mode: .time, duration: 3),
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
                    PlanStep(id: stepID(1), label: "Warm-up", mode: .time, duration: 120, intensity: .low),
                ]),
                PlanBlock(name: "Main work", steps: [
                    PlanStep(id: stepID(2), label: "Flat Dumbbell Bench Press", sets: 4, mode: .reps,
                             reps: 8, targetWeightKg: 20, restAfter: 90),
                    PlanStep(id: stepID(3), label: "Neutral-Grip Lat Pulldown", sets: 4, mode: .reps,
                             reps: 6, targetWeightKg: 50, restAfter: 90),
                    // The one step carrying an exercise id rather than a label, so the session
                    // runs the two-sided path — left, right, rest — with no backend behind it.
                    PlanStep(id: stepID(4), exerciseID: rowID, sets: 3, mode: .reps,
                             reps: 10, targetWeightKg: 22, restAfter: 60),
                ]),
                // The effort used to be spelled into the labels ("Hard — 20 sec"), which was the
                // only place it could live. It is a field now, and the label names the movement.
                PlanBlock(name: "HIIT", rounds: 6, steps: [
                    PlanStep(id: stepID(5), label: "Sprint", mode: .time, duration: 20, intensity: .hard),
                    PlanStep(id: stepID(6), label: "Recover", mode: .time, duration: 40, intensity: .low),
                ]),
            ]
        )
    }
}

#Preview("Session runner") {
    // Built here rather than by `SessionHost`, because a preview has no app lifetime to hang a
    // session on — and nothing in the runner needs one, now that it does not own its controller.
    // The store is the one the app injects, and the runner reads it for the plan a saved
    // adjustment changes.
    SessionRunner(
        controller: SessionController(plan: DemoPlan.make(), exercises: DemoPlan.builderExercises)
    )
    .environment(PlanStore.seeded(DemoPlan.builderExercises))
}
#endif
