import Foundation
import OronzoCore
import SwiftUI

/// Holds the plans the app is showing, with a disk cache so a workout can be started
/// without a network — which is the normal case in a basement gym.
@MainActor
@Observable
final class PlanStore {

    private(set) var plans: [Plan] = []
    /// What flattening resolves against: each exercise's name, and whether it is done per side.
    private(set) var exercises: [UUID: ExerciseInfo] = [:]
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository = PlanRepository()
    private let cache = PlanCache()

    /// Load the cache immediately, then refresh from the network in the background.
    func load() async {
        if plans.isEmpty, let cached = cache.load() {
            plans = cached.plans
            exercises = Self.exerciseInfo(names: cached.exerciseNames, twoSided: cached.twoSidedExerciseIDs)
            invalidateIntervals()
        }
        await refresh()
    }

    /// The in-memory map and the cached pair of fields are two shapes of one thing — see
    /// `CachedPlanList` for why they are not the same shape.
    private static func exerciseInfo(names: [UUID: String], twoSided: [UUID]) -> [UUID: ExerciseInfo] {
        let flagged = Set(twoSided)
        var info: [UUID: ExerciseInfo] = [:]
        for (id, name) in names {
            info[id] = ExerciseInfo(name: name, hasTwoSides: flagged.contains(id))
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
            // what made the plan list fall back to the cache so often.
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
        async let plans = repository.fetchPlans()
        async let exercises = repository.fetchExercises()

        let loadedPlans = try await plans
        let loadedExercises = try await exercises

        self.plans = loadedPlans
        self.exercises = loadedExercises
        invalidateIntervals()
        cache.save(plans: loadedPlans, exercises: loadedExercises)
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
            Log.debug("plan refresh: could not renew the session: \(error)")
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
        Log.debug("plan refresh failed: \(raw)")

        return aboutTheSession
            ? "Your session has expired. Sign out and sign in again to renew it."
            : raw
    }

    /// The flattened intervals for a plan — **cached, because this is called from view bodies.**
    ///
    /// It used to be a bare `PlanFlattener.flatten` on every call, and the callers are not
    /// occasional: `PlanListView` asks once per row per redraw, and `PlanDetailView` asks from two
    /// computed properties that four places in one `body` read. Flattening allocates a fresh
    /// `[Interval]` of size blocks × rounds × sets, so a list of eight plans was re-deriving the
    /// same eight arrays every frame, and the detail screen four times per frame.
    ///
    /// Keyed by plan id and thrown away whenever the plans or the exercise info are replaced,
    /// which is the only thing that can change the answer — a plan is a value, and the exercises
    /// are what flattening resolves against, name and side count alike.
    func intervals(for plan: Plan) -> [Interval] {
        if let cached = intervalCache[plan.id] { return cached }
        let intervals = PlanFlattener.flatten(plan, exercises: exercises)
        intervalCache[plan.id] = intervals
        return intervals
    }

    private var intervalCache: [UUID: [Interval]] = [:]

    /// Any change to the plans or the exercises invalidates every entry: both are inputs to
    /// flattening, so a refresh that only replaced `exercises` would otherwise leave every plan
    /// running its old names and its old interval count.
    private func invalidateIntervals() {
        intervalCache.removeAll(keepingCapacity: true)
    }
}

#if DEBUG
extension PlanStore {
    /// A store holding only exercise info, for the launch-argument entry points that bypass the
    /// backend. Lives here because `exercises` is `private(set)`.
    static func seeded(_ exercises: [UUID: ExerciseInfo]) -> PlanStore {
        let store = PlanStore()
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
/// cannot be read is discarded instead, so the plan list is empty until one fetch succeeds —
/// visible, and recoverable by going online. See `docs/known-issues.md` §3 for what that empty
/// state currently says, which is a known and separate problem.
private struct CachedPlanList: Codable {
    let plans: [Plan]
    let exerciseNames: [UUID: String]
    let twoSidedExerciseIDs: [UUID]
}

private struct PlanCache {
    private let url: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("plan-cache.json")
    }()

    func load() -> CachedPlanList? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(CachedPlanList.self, from: data)
        } catch {
            // **Logged, and it is the only place in this codebase that used to swallow a failure
            // without saying so** (`docs/known-issues.md` §4). The cache is unversioned, so a
            // renamed `Codable` property invalidates every entry and this is the only trace it
            // leaves. A `nil` here is indistinguishable from "no cache yet" — which reads on screen
            // as an empty plan list, and offline that is the difference between a workout and none.
            Log.debug("plan cache: could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    func save(plans: [Plan], exercises: [UUID: ExerciseInfo]) {
        guard let url else { return }
        let payload = CachedPlanList(
            plans: plans,
            exerciseNames: exercises.mapValues(\.name),
            // Sorted so the file is the same bytes for the same data rather than following
            // dictionary order, which is worth having when the only way to read it is a text
            // editor on a device.
            twoSidedExerciseIDs: exercises
                .filter { $0.value.hasTwoSides }
                .keys
                .sorted { $0.uuidString < $1.uuidString }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
