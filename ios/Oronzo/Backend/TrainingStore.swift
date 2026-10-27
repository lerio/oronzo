import Foundation
import OronzoCore
import SwiftUI

/// Holds the workouts and weekly plans the app is showing, with a disk cache so a workout can be
/// started without a network — which is the normal case in a basement gym.
@MainActor
@Observable
final class TrainingStore {

    private(set) var workouts: [Workout] = []
    private(set) var weekPlans: [WeekPlan] = []
    /// What flattening resolves against: each exercise's name, whether it is done per side, and
    /// whether it is done alternatingly.
    private(set) var exercises: [UUID: ExerciseInfo] = [:]
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository = TrainingRepository()
    private let cache = TrainingCache()

    /// Load the cache immediately, then refresh from the network in the background.
    func load() async {
        if workouts.isEmpty, let cached = cache.load() {
            workouts = cached.plans
            weekPlans = cached.weekPlans ?? []
            exercises = Self.exerciseInfo(names: cached.exerciseNames,
                                          twoSided: cached.twoSidedExerciseIDs,
                                          alternating: cached.alternatingExerciseIDs ?? [])
            invalidateIntervals()
        }
        await refresh()
    }

    /// The in-memory map and the cached fields are two shapes of one thing — see `CachedTraining`
    /// for why they are not the same shape, and for why one id list is required there and the
    /// other is not.
    private static func exerciseInfo(
        names: [UUID: String],
        twoSided: [UUID],
        alternating: [UUID]
    ) -> [UUID: ExerciseInfo] {
        let sides = Set(twoSided)
        let alternatingIDs = Set(alternating)
        var info: [UUID: ExerciseInfo] = [:]
        for (id, name) in names {
            info[id] = ExerciseInfo(name: name,
                                    hasTwoSides: sides.contains(id),
                                    alternatesSides: alternatingIDs.contains(id))
        }
        return info
    }

    func refresh() async {
        guard Backend.isConfigured else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await fetchLatest()
        } catch {
            // One second chance, and only when the failure is *about the session*.
            //
            // The access token lives an hour and this app is opened in a basement gym, so a
            // request that arrives holding a just-expired token fails — and what it fails *with*
            // is the "weird JWT" text: "invalid JWT: unable to parse or verify signature, token
            // is unverifiable…". That is a renewable session reading as a broken one, which is
            // what made the workout list fall back to the cache so often.
            //
            // Gated on the diagnosis rather than run unconditionally: `refreshSession()` rotates
            // the refresh token, and rotating it after, say, a `400` from a column that does not
            // exist would be a needless rotation — the very thing that produces "Invalid Refresh
            // Token: Already Used" when two of them race.
            let aboutTheSession = Self.looksLikeASessionProblem(error)

            if aboutTheSession, await renewSession() {
                do {
                    try await fetchLatest()
                    return
                } catch {
                    self.error = Self.readable(error, aboutTheSession: Self.looksLikeASessionProblem(error))
                    return
                }
            }

            self.error = Self.readable(error, aboutTheSession: aboutTheSession)
        }
    }

    /// The fetch itself, so it can be attempted twice without repeating the assignments.
    /// (`load()` above is the cache entry point — this is the network half of a refresh.)
    private func fetchLatest() async throws {
        async let workouts = repository.fetchWorkouts()
        async let weekPlans = repository.fetchWeekPlans()
        async let exercises = repository.fetchExercises()

        let loadedWorkouts = try await workouts
        let loadedWeekPlans = try await weekPlans
        let loadedExercises = try await exercises

        self.workouts = loadedWorkouts
        self.weekPlans = loadedWeekPlans
        self.exercises = loadedExercises
        invalidateIntervals()
        cache.save(workouts: loadedWorkouts, weekPlans: loadedWeekPlans, exercises: loadedExercises)
    }

    /// True when the session was renewed, so another attempt is worth making.
    ///
    /// A signed-out app is not a refresh problem — `AuthStore` owns that state — so this does
    /// nothing when there is no session to renew.
    private func renewSession() async -> Bool {
        guard Backend.client.auth.currentSession != nil else { return false }
        do {
            try await Backend.client.auth.refreshSession()
            return true
        } catch {
            Log.debug("training refresh: could not renew the session: \(error)")
            return false
        }
    }

    /// Whether a failure is *about the session*, rather than about the data.
    ///
    /// The check is on the message text because the SDK does not surface a status code this layer
    /// can read — a heuristic, and a deliberately narrow one: only the words a Supabase auth
    /// failure actually uses. It decides two things, and both are better for being narrow: whether
    /// to spend a refresh-token rotation on a retry, and whether the banner should say "your
    /// session has expired" instead of repeating a server's sentence about keyfunc.
    private static func looksLikeASessionProblem(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return ["jwt", "unauthorized", "refresh token", "401"].contains { text.contains($0) }
    }

    /// The SDK's own words are accurate and unreadable, and they are what shows in the banner.
    ///
    /// A 401 arrives as "invalid JWT: unable to parse or verify signature, token is unverifiable:
    /// error while executing keyfunc: …", which reads like a bug in the app rather than a session
    /// that needs renewing. The original goes to the debug log, where it is worth having.
    private static func readable(_ error: Error, aboutTheSession: Bool) -> String {
        let raw = error.localizedDescription
        Log.debug("training refresh failed: \(raw)")

        return aboutTheSession
            ? "Your session has expired. Sign out and sign in again to renew it."
            : raw
    }

    /// The flattened intervals for a workout — **cached, because this is called from view bodies.**
    ///
    /// It used to be a bare `WorkoutFlattener.flatten` on every call, and the callers are not
    /// occasional: `TodayView` asks once per row per redraw, and `WorkoutDetailView` asks from two
    /// computed properties that four places in one `body` read. Flattening allocates a fresh
    /// `[Interval]` of size blocks × rounds × sets, so a list of eight workouts was re-deriving the
    /// same eight arrays every frame, and the detail screen four times per frame.
    ///
    /// Keyed by workout id and thrown away whenever the workouts or the exercise info are replaced,
    /// which is the only thing that can change the answer — a workout is a value, and the exercises
    /// are what flattening resolves against, name and side count alike.
    func intervals(for workout: Workout) -> [Interval] {
        if let cached = intervalCache[workout.id] { return cached }
        let intervals = WorkoutFlattener.flatten(workout, exercises: exercises)
        intervalCache[workout.id] = intervals
        return intervals
    }

    private var intervalCache: [UUID: [Interval]] = [:]

    /// Any change to the workouts or the exercises invalidates every entry: both are inputs to
    /// flattening, so a refresh that only replaced `exercises` would otherwise leave every workout
    /// running its old names and its old interval count.
    private func invalidateIntervals() {
        intervalCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Following a load adjustment

    /// Moves the app's own copy of a workout to match a load the runner has just written.
    ///
    /// **Without this the store contradicts the server.** `workouts` is what `SessionHost.begin`
    /// flattens from and what the Today screen and detail screen draw, and it is cached to disk —
    /// so an adjustment that reached the database and not this array would come back the next time
    /// the workout was started, in the same app run, with the old weight. A round trip would fix it
    /// too, but the write has already happened: re-fetching here would only add a race in which a
    /// stale read can win.
    ///
    /// Only the step named is touched, and only its load — the same blast radius the write has.
    func applyLoadEdit(_ edit: StepLoadEdit) {
        var changed = false
        let updated = workouts.map { workout in
            var workout = workout
            for blockIndex in workout.blocks.indices {
                for stepIndex in workout.blocks[blockIndex].steps.indices
                where workout.blocks[blockIndex].steps[stepIndex].id == edit.stepID {
                    workout.blocks[blockIndex].steps[stepIndex].targetWeightKg = edit.weightKg
                    workout.blocks[blockIndex].steps[stepIndex].intensity = edit.intensity
                    changed = true
                }
            }
            return workout
        }

        guard changed else { return }
        workouts = updated
        // The flattened intervals of that workout are now wrong — including the ones of the step
        // itself, which is what the arrows are about to be drawn from.
        invalidateIntervals()
        cache.save(workouts: workouts, weekPlans: weekPlans, exercises: exercises)
    }
}

#if DEBUG
extension TrainingStore {
    /// A store holding only exercise info, for the launch-argument entry points that bypass the
    /// backend. Lives here because `exercises` is `private(set)`.
    static func seeded(_ exercises: [UUID: ExerciseInfo]) -> TrainingStore {
        let store = TrainingStore()
        store.exercises = exercises
        return store
    }
}
#endif

// MARK: - Disk cache

/// A JSON file in Application Support. Deliberately dumb: the whole point is that the last
/// successful fetch survives, so the app is usable offline.
///
/// **The shape on disk is not the shape in memory, on purpose.** Holding an `ExerciseInfo` per id
/// here would turn each JSON value from a string into an object and invalidate every file on a
/// device. Keeping the names exactly as they were, plus which of them are two-sided, means the
/// only thing an older file is missing is the list of ids.
///
/// `twoSidedExerciseIDs` is **required**, and that is the decision rather than an oversight. It
/// could have been optional — Swift's synthesised decoder tolerates a missing key only for an
/// optional property — and an older file would then have kept working, with every exercise
/// reading as one-sided. That is a workout that quietly runs half its sets: the phone would show
/// three intervals where the builder showed six, and nothing anywhere would say why. A file that
/// cannot be read is discarded instead, so the workout list is empty until one fetch succeeds —
/// visible, and recoverable by going online. See `docs/known-issues.md` §3 for what that empty
/// state currently says, which is a known and separate problem.
///
/// **`alternatingExerciseIDs` is optional, and the difference is the point.** The same argument
/// would give the same answer only if the two flags failed the same way, and they do not: an
/// alternating exercise is *not* two-sided, so a file that has never heard of the flag still
/// flattens it into the right number of intervals, and all that is lost is the `(alt)` on the
/// name. Per `AGENTS.md`, a field whose absence costs a display name may be optional; one whose
/// absence changes the workout may not. Keeping it optional is also what stops every device
/// emptying its workout list once, which is what a required key added here would do.
///
/// That reasoning holds only while `WorkoutFlattener.sideSuffixes` never reads the alternating
/// flag — `WorkoutFlattenerTests.testAnAlternatingExerciseIsNotTwoSided` is the assertion that it
/// does not.
///
/// **The top-level key `plans` is historical and stays.** The values are now `Workout`s, but a
/// file written before `0018` is still a valid workout list (same `id`/`name`/`blocks` keys), and
/// `preferredTime` is optional, so renaming the key would throw away every device's offline copy
/// for nothing. `weekPlans` is new and optional, so the same file decodes on both sides of the
/// update.
private struct CachedTraining: Codable {
    let plans: [Workout]
    let exerciseNames: [UUID: String]
    let twoSidedExerciseIDs: [UUID]
    /// Absent from every file written before `0016`, which is the case it exists to tolerate.
    let alternatingExerciseIDs: [UUID]?
    /// Absent from every file written before `0018`; Today falls back to All Workouts offline.
    let weekPlans: [WeekPlan]?
}

private struct TrainingCache {
    private let url: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("plan-cache.json")
    }()

    func load() -> CachedTraining? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(CachedTraining.self, from: data)
        } catch {
            // **Logged, and it is the only place in this codebase that used to swallow a failure
            // without saying so** (`docs/known-issues.md` §4). The cache is unversioned, so a
            // renamed `Codable` property invalidates every entry and this is the only trace it
            // leaves. A `nil` here is indistinguishable from "no cache yet" — which reads on screen
            // as an empty workout list, and offline that is the difference between a workout and none.
            Log.debug("plan cache: could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    func save(workouts: [Workout], weekPlans: [WeekPlan], exercises: [UUID: ExerciseInfo]) {
        guard let url else { return }
        let payload = CachedTraining(
            plans: workouts,
            exerciseNames: exercises.mapValues(\.name),
            // Sorted so the file is the same bytes for the same data rather than following
            // dictionary order, which is worth having when the only way to read it is a text
            // editor on a device.
            twoSidedExerciseIDs: exercises
                .filter { $0.value.hasTwoSides }
                .keys
                .sorted { $0.uuidString < $1.uuidString },
            alternatingExerciseIDs: exercises
                .filter { $0.value.alternatesSides }
                .keys
                .sorted { $0.uuidString < $1.uuidString },
            weekPlans: weekPlans
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
