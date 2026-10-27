import OronzoCore
import SwiftUI

/// The workout library, in the order arranged in the web builder.
///
/// Reachable from Today's toolbar and from every empty state, so a workout can always be started
/// even when no weekly plan exists or today has nothing scheduled.
struct AllWorkoutsView: View {
    @Environment(TrainingStore.self) private var store

    @State private var openedWorkoutID: UUID?

    var body: some View {
        Group {
            if store.workouts.isEmpty && store.isLoading {
                ProgressView("Loading workouts…")
            } else if store.workouts.isEmpty, let error = store.error {
                ContentUnavailableView {
                    Label("Can't reach your workouts", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await store.refresh() } }
                }
            } else if store.workouts.isEmpty {
                ContentUnavailableView {
                    Label("No workouts yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Build one in the web app, then pull to refresh here.")
                }
            } else {
                List {
                    if let error = store.error {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Showing cached workouts").font(.subheadline.weight(.semibold))
                                    Text(error).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                            }
                        }
                    }

                    ForEach(store.workouts) { workout in
                        WorkoutRowView(workout: workout, showsSchedule: true) { id in
                            openedWorkoutID = id
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.refresh() }
            }
        }
        .navigationTitle("All workouts")
        .navigationDestination(item: $openedWorkoutID) { id in
            if let workout = store.workouts.first(where: { $0.id == id }) {
                WorkoutDetailView(workout: workout)
            } else {
                ContentUnavailableView("Workout not found", systemImage: "questionmark")
            }
        }
    }
}
