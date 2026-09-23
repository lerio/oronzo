import Foundation
import OronzoCore
import SwiftUI

/// Holds the plans the app is showing, with a disk cache so a workout can be started
/// without a network — which is the normal case in a basement gym.
@MainActor
@Observable
final class PlanStore {

    private(set) var plans: [Plan] = []
    private(set) var exerciseNames: [UUID: String] = [:]
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository = PlanRepository()
    private let cache = PlanCache()

    /// Load the cache immediately, then refresh from the network in the background.
    func load() async {
        if plans.isEmpty, let cached = cache.load() {
            plans = cached.plans
            exerciseNames = cached.exerciseNames
            invalidateIntervals()
        }
        await refresh()
    }

    func refresh() async {
        guard Backend.isConfigured else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let plans = repository.fetchPlans()
            async let names = repository.fetchExerciseNames()

            let loadedPlans = try await plans
            let loadedNames = try await names

            self.plans = loadedPlans
            self.exerciseNames = loadedNames
            invalidateIntervals()
            cache.save(plans: loadedPlans, exerciseNames: loadedNames)
        } catch {
            // Keep whatever the cache gave us; a stale plan list beats an empty screen.
            self.error = error.localizedDescription
        }
    }

    /// The flattened intervals for a plan — **cached, because this is called from view bodies.**
    ///
    /// It used to be a bare `PlanFlattener.flatten` on every call, and the callers are not
    /// occasional: `PlanListView` asks once per row per redraw, and `PlanDetailView` asks from two
    /// computed properties that four places in one `body` read. Flattening allocates a fresh
    /// `[Interval]` of size blocks × rounds × sets, so a list of eight plans was re-deriving the
    /// same eight arrays every frame, and the detail screen four times per frame.
    ///
    /// Keyed by plan id and thrown away whenever the plans or the exercise names are replaced,
    /// which is the only thing that can change the answer — a plan is a value, and the names are
    /// what flattening resolves against.
    func intervals(for plan: Plan) -> [Interval] {
        if let cached = intervalCache[plan.id] { return cached }
        let intervals = PlanFlattener.flatten(plan, exerciseNames: exerciseNames)
        intervalCache[plan.id] = intervals
        return intervals
    }

    private var intervalCache: [UUID: [Interval]] = [:]

    /// Any change to the plans or the names invalidates every entry: the names are an input to
    /// flattening, so a refresh that only replaced `exerciseNames` would otherwise leave every plan
    /// showing its old exercise names.
    private func invalidateIntervals() {
        intervalCache.removeAll(keepingCapacity: true)
    }
}

#if DEBUG
extension PlanStore {
    /// A store holding only exercise names, for the launch-argument entry points that bypass
    /// the backend. Lives here because `exerciseNames` is `private(set)`.
    static func seeded(_ exerciseNames: [UUID: String]) -> PlanStore {
        let store = PlanStore()
        store.exerciseNames = exerciseNames
        return store
    }
}
#endif

// MARK: - Disk cache

/// A JSON file in Application Support. Deliberately dumb: the whole point is that the last
/// successful fetch survives, so the app is usable offline.
private struct CachedPlanList: Codable {
    let plans: [Plan]
    let exerciseNames: [UUID: String]
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

    func save(plans: [Plan], exerciseNames: [UUID: String]) {
        guard let url else { return }
        let payload = CachedPlanList(plans: plans, exerciseNames: exerciseNames)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
