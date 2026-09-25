import Foundation
import OronzoCore

/// Who owns the workout.
///
/// **This type exists to take session ownership out of a view.** Until now the only
/// `SessionController` in the app was built by `SessionRunner` in `@State(initialValue:)`, which
/// SwiftUI re-evaluates on every re-render of the view presenting it — and which it can re-create
/// with fresh state, tearing the old one down on the way. Four separate guards grew up around that
/// fact, each with a paragraph explaining which failure it prevented: `SessionController.init`'s
/// deliberate emptiness, `PhoneConnectivity.claim`'s refusal, `pushState`'s `isAdvertising` check,
/// and `resign`'s. They are good guards and they contain the problem, but containing it is not the
/// same as not having it, and one of them — a runner reappearing onto its own live session — was
/// the mechanism by which a wrist got cleared and never told again.
///
/// A session is not a view's business. It outlives the screen that started it: it keeps ticking
/// while the phone is in a pocket, it must survive the runner being re-created, and it is written
/// down so it can survive the app itself. So it lives here, created once by `OronzoApp` and handed
/// to whoever needs it, exactly like `AuthStore` and `PlanStore`.
///
/// The guards stay. They cost nothing and they catch a regression. What changes is that nothing
/// new needs them.
@MainActor
@Observable
final class SessionHost {

    /// The session being run, if any. `nil` is the ordinary case: no workout.
    private(set) var controller: SessionController?

    /// Whether the runner should be on screen. The one thing a view has to ask.
    var isPresented: Bool { controller != nil }

    /// The plan a live session belongs to, so a plan's own screen can tell whether *it* started it.
    var planID: UUID? { controller?.planID }

    /// Starts a workout, or returns the one already running.
    ///
    /// **Idempotent, and that is the point.** The runner is built and thrown away repeatedly; if
    /// every build could start a session, the app would hand the watch a workout from a controller
    /// it is about to discard. Asking for the session that is already running returns *that* one,
    /// so there is exactly one engine per workout no matter how often the UI asks.
    @discardableResult
    func begin(
        plan: Plan,
        exercises: [UUID: ExerciseInfo],
        persistsRecord: Bool = true,
        recordsHealth: Bool = true
    ) -> SessionController {
        if let controller, controller.planID == plan.id { return controller }

        // A different plan is only reachable by ending the one on screen first, which `end()` does.
        // Replacing rather than stacking is the single-owner rule: there is one workout at a time.
        let started = SessionController(
            plan: plan,
            exercises: exercises,
            persistsRecord: persistsRecord,
            recordsHealth: recordsHealth
        )
        controller = started
        Log.debug("host: began a session for \"\(plan.name)\"")
        return started
    }

    /// Picks up a workout the phone was already in the middle of.
    ///
    /// Called once at launch. Returns whether anything was resumed, which is the one thing the
    /// caller needs to know — the runner is presented from `isPresented`, not from this.
    @discardableResult
    func restore(at now: Date = .now) -> Bool {
        guard controller == nil else { return false }
        guard let record = SessionRecordFile.load() else { return false }

        // **`isLive`, the same rule the link answers the watch from.** A record this refuses is
        // one `PhoneConnectivity` has already declined to tell the watch about, so the two halves
        // cannot disagree: nothing is resumed that the watch was not told about, and nothing is
        // told about that cannot be resumed.
        guard record.isLive(at: now) else {
            Log.debug("host: a record was found but is not live (phase \(record.phase.rawValue))")
            return false
        }
        guard let restored = SessionController(restoring: record) else {
            // The engine refused it — a shape that does not describe a real session. Forget it
            // rather than leaving a file that will be refused on every future launch.
            Log.debug("host: the record could not be restored; discarding it")
            SessionRecordFile.clear()
            return false
        }

        controller = restored
        Log.debug("host: resumed \"\(record.planName)\" at interval \(record.currentIndex) of \(record.intervals.count)")
        return true
    }

    /// The runner is finished with the session. Safe to call at any point, including when there is
    /// nothing to end — a dismissal binding will call it more than once.
    ///
    /// The ordinary path is a **finished** session: the workout ran its course or was ended, the
    /// runner showed the summary, and Done dismissed it. `teardown` then clears the record and
    /// tells the watch, which is what stops a completed workout answering the wrist forever.
    ///
    /// A **live** session reaching here would mean the runner went away mid-workout. That is not
    /// reachable from the UI — the only way out of the runner is End, which ends the session first —
    /// so it is treated as the safe direction rather than the tidy one: `teardown` deliberately
    /// leaves a live session's record alone, so the workout stays answerable to the watch and is
    /// still there to resume. Logged loudly, because if it ever does happen it means a path exists
    /// that nobody knew about.
    func end() {
        guard let controller else { return }
        let wasLive = !controller.isFinished
        controller.teardown()
        self.controller = nil
        if wasLive {
            Log.debug("host: a live session's runner went away; its record is kept for resume")
        } else {
            Log.debug("host: ended the session")
        }
    }
}
