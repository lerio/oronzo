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
import UIKit

/// Keeps a Live Activity alive on the Lock Screen for the duration of a session.
///
/// **Every failure here is silent to the user, and that is deliberate.** Live Activities are an
/// enhancement:
/// if the user has them switched off, or the system refuses a request, the workout must run
/// exactly as it would have. An unavailable enhancement is not an error state, and nothing about
/// it belongs on screen — the same reasoning as the watch link.
///
/// The countdown is *not* driven from here. The content carries an absolute end date and the
/// system renders the timer itself, so this only speaks when something actually changes — which
/// is why the design needs no per-second traffic on this surface either.
@MainActor
final class LiveSessionActivity {

    /// **The one instance, because there is one session and therefore one Activity.**
    ///
    /// This was per-`SessionController`, and that is how the Lock Screen came to show a card that
    /// nothing was updating. `SessionController` is rebuilt on every re-render of the runner, and
    /// more than one of those copies can end up holding a live session — the state the whole
    /// `claim`/`isAdvertising` dance exists to contain. With a `LiveSessionActivity` each, every
    /// one of them could request its *own* Activity: the card on screen belonged to one controller
    /// while the session was driven by another, and the second controller's updates went to an
    /// Activity nobody was looking at.
    ///
    /// `ownsActivity` below was already static — the author had worked out that the Activity is a
    /// process-wide fact. The handle was not, and the handle is what decides who can update it.
    static let shared = LiveSessionActivity()

    private init() {}

    private var activity: Activity<SessionActivityAttributes>?

    /// What was last handed to the system, so a repeat is not sent again.
    ///
    /// **Here rather than in the caller, and that is the point of it.** The dedupe used to live in
    /// `SessionController.pushState`, behind the guard that decides which session may speak to the
    /// *watch* — so the card could only be refreshed by the session the watch link happened to be
    /// pointed at, which is not the session running the workout. There is one Activity; whoever
    /// holds its handle is who may drive it, and this is what keeps that to once per change.
    private var lastSent: SessionActivityContent?

    /// Whether *this process* owns an Activity.
    ///
    /// The launch-time orphan sweep needs this. Without it, a session that starts in the same
    /// moment as the sweep — which `-demoSession` does every time — has its brand-new Activity
    /// ended a beat after it was created, and the Lock Screen quietly shows nothing.
    private static var ownsActivity = false

    /// Requests the Activity for a session that is starting, or refreshes it if this process
    /// already has one.
    ///
    /// The refresh is not a nicety. A second controller calling `start()` means *the same session
    /// has a second controller*, not that a new workout has begun — and requesting a second
    /// Activity for it is precisely how the card and the work came apart.
    func start(_ content: SessionActivityContent) {
        guard activity == nil else {
            Log.debug("activity: already started by this process; refreshing it instead")
            update(content)
            return
        }

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
            lastSent = content
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

    /// Hands the system the card's content, if it has moved.
    ///
    /// Called from `SessionController` on **every** state change, whoever caused it and whether or
    /// not that controller is the one the watch link is pointed at — there is one Activity, this
    /// owns it, and this is what decides whether a write is owed. The caller used to decide, behind
    /// the watch's guard, and the Lock Screen paid for it: a locked phone kept showing the interval
    /// it started with while the workout moved on, and skipping an interval *from the watch* moved
    /// the card only because that path happens to run on the session the link knows about.
    func update(_ content: SessionActivityContent) {
        guard let activity else {
            Log.debug("activity: update skipped, this process has none")
            return
        }
        guard content != lastSent else { return }
        lastSent = content
        // `Task { @MainActor in }` rather than a plain `Task { }`: `Activity` is not `Sendable`,
        // so hopping off the main actor with it is a real data race and Swift 6 rejects it.
        // Staying put keeps the value where it belongs.
        Task { @MainActor in
            // This is the one write site that had no line of its own, and it is the one the Lock
            // Screen's whole correctness rests on: with the phone locked a write either lands or
            // it does not, and from outside the two look identical — the card simply keeps what
            // it was last handed. Logged at all, and with the app's state, because that state is
            // the fact that decides the outcome.
            Log.debug("activity: update \(content.name), app \(Self.appState)")
            // `staleDate: nil` on purpose — see `SessionActivityContent`. A stale date at
            // `intervalEnd` lands on the very moment this update has to be applied.
            await activity.update(.init(state: content, staleDate: nil))
        }
    }

    /// The app's state, for the log above — the fact that decides whether a write can land.
    private static var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastSent = nil
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
