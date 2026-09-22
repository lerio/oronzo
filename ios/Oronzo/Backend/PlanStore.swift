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
            cache.save(plans: loadedPlans, exerciseNames: loadedNames)
        } catch {
            // Keep whatever the cache gave us; a stale plan list beats an empty screen.
            self.error = error.localizedDescription
        }
    }

    func intervals(for plan: Plan) -> [Interval] {
        PlanFlattener.flatten(plan, exerciseNames: exerciseNames)
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
        return try? JSONDecoder().decode(CachedPlanList.self, from: data)
    }

    func save(plans: [Plan], exerciseNames: [UUID: String]) {
        guard let url else { return }
        let payload = CachedPlanList(plans: plans, exerciseNames: exerciseNames)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
