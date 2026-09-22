import OronzoCore
import SwiftUI

struct PlanListView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(PlanStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.plans.isEmpty && store.isLoading {
                    ProgressView("Loading plans…")
                } else if store.plans.isEmpty {
                    ContentUnavailableView {
                        Label("No plans yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Build one in the web app, then pull to refresh here.")
                    }
                } else {
                    List {
                        if let error = store.error {
                            Section {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Showing cached plans").font(.subheadline.weight(.semibold))
                                        Text(error).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                                }
                            }
                        }

                        ForEach(store.plans) { plan in
                            NavigationLink(value: plan.id) {
                                PlanRowView(plan: plan, intervals: store.intervals(for: plan))
                            }
                        }
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Plans")
            .navigationDestination(for: UUID.self) { id in
                if let plan = store.plans.first(where: { $0.id == id }) {
                    PlanDetailView(plan: plan)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await store.load() }
    }
}

private struct PlanRowView: View {
    let plan: Plan
    let intervals: [Interval]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan.name)
                .font(.headline)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Defined once, in `OronzoCore`, and shared with the plan summary — a row that disagreed
    /// with the screen it opens would be worse than either one being slightly wrong.
    private var summary: String {
        PlanSummary(plan: plan, intervals: intervals).metaLine
    }
}
