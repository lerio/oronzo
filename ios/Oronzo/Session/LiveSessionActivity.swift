// `Activity` is not `Sendable`, and ActivityKit is not annotated for Swift 6 — so *any*
// `await activity.update(...)` is a send across a suspension, and the compiler is right to
// object. `@preconcurrency` is the sanctioned way to say "this framework's concurrency
// annotations are not trustworthy yet, and I am taking responsibility": the alternatives are
// `nonisolated(unsafe)` on the stored property, which is a worse lie because it also permits
// access from anywhere, or not doing the update at all, which loses the surface.
//
// What makes it safe here is that everything below is MainActor-isolated and there is exactly
// one Activity per session.
@preconcurrency import ActivityKit
import Foundation
import OronzoCore

/// Keeps a Live Activity alive on the Lock Screen for the duration of a session.
///
/// **Every failure here is silent, and that is deliberate.** Live Activities are an enhancement:
/// if the user has them switched off, or the system refuses a request, the workout must run
/// exactly as it would have. An unavailable enhancement is not an error state, and nothing about
/// it belongs on screen — the same reasoning as the watch link.
///
/// The countdown is *not* driven from here. The content carries an absolute end date and the
/// system renders the timer itself, so this only speaks when something actually changes — which
/// is why the design needs no per-second traffic on this surface either.
@MainActor
final class LiveSessionActivity {

    private var activity: Activity<SessionActivityAttributes>?

    /// Whether *this process* owns an Activity.
    ///
    /// The launch-time orphan sweep needs this. Without it, a session that starts in the same
    /// moment as the sweep — which `-demoSession` does every time — has its brand-new Activity
    /// ended a beat after it was created, and the Lock Screen quietly shows nothing.
    private static var ownsActivity = false

    /// Replaces any existing Activity with one for the session that is starting.
    func start(_ content: SessionActivityContent) {
        // There is only ever one session, so there is only ever one Activity.
        end()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.debug("activity: Live Activities are disabled for this app")
            return
        }

        do {
            let requested = try Activity.request(
                attributes: SessionActivityAttributes(),
                content: .init(state: content, staleDate: nil)
            )
            activity = requested
            Self.ownsActivity = true
            // The system's own verdict. A request can succeed and still be presented as nothing —
            // a state other than `active` means it was accepted and then withdrawn, which looks
            // identical to a rendering bug from outside.
            Log.debug("activity: started, state=\(String(describing: requested.activityState))")
        } catch {
            // `dataTooLarge`, `tooManyActivities`, `unsupported` — all of them mean "no Lock
            // Screen surface this time", none of them mean the workout is in trouble.
            Log.debug("activity: could not start: \(error)")
        }
    }

    func update(_ content: SessionActivityContent) {
        guard let activity else { return }
        // `Task { @MainActor in }` rather than a plain `Task { }`: `Activity` is not `Sendable`,
        // so hopping off the main actor with it is a real data race and Swift 6 rejects it.
        // Staying put keeps the value where it belongs.
        Task { @MainActor in
            await activity.update(.init(state: content, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Self.ownsActivity = false
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Clears anything left behind by a previous run.
    ///
    /// The application context taught this lesson once already: it has no expiry, so a phone that
    /// was force-quit mid-workout leaves the watch showing a session that no longer exists. An
    /// Activity outlives the app in exactly the same way — it would sit on the Lock Screen
    /// counting down a workout that ended hours ago.
    static func endOrphans() {
        // Never while a session of ours is running: those Activities are current, not orphaned.
        guard !ownsActivity else {
            Log.debug("activity: sweep skipped, this process owns one")
            return
        }

        let orphans = Activity<SessionActivityAttributes>.activities
        guard !orphans.isEmpty else { return }
        Log.debug("activity: ending \(orphans.count) orphaned from a previous run")
        for activity in orphans {
            Task { @MainActor in
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
