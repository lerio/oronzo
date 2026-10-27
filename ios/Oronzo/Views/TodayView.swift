import OronzoCore
import SwiftUI

extension Weekday {
    /// Localised short label for the week strip and a plan badge.
    ///
    /// `Calendar.shortWeekdaySymbols` is Sunday-indexed regardless of `firstWeekday` (verified
    /// for en_US and it_IT), so ISO Monday = 1 maps to index 1 and ISO Sunday = 7 to index 0.
    var shortLabel: String {
        Calendar.current.shortWeekdaySymbols[rawValue % 7].capitalized
    }

    var longLabel: String {
        Calendar.current.weekdaySymbols[rawValue % 7].capitalized
    }
}

/// The phone's home: what is scheduled today, and one-tap Start.
///
/// This is deliberately not a plan list. The active plan is a device preference, chosen in the
/// title menu; the weekday strip previews the other days of the same template. A plan is a weekly
/// template, not a calendar — there are no dates anywhere on this screen.
struct TodayView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(TrainingStore.self) private var store

    @AppStorage("activePlanID") private var activePlanID = ""

    @State private var selectedDay = WeekSchedule.isoWeekday(of: .now)
    @State private var openedWorkoutID: UUID?

    private var today: Weekday { WeekSchedule.isoWeekday(of: .now) }

    private var activePlan: WeekPlan? {
        store.weekPlans.first { $0.id.uuidString == activePlanID } ?? store.weekPlans.first
    }

    private var dayWorkouts: [Workout] {
        guard let activePlan else { return [] }
        return WeekSchedule.workouts(on: selectedDay, in: activePlan, from: store.workouts)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.workouts.isEmpty && store.isLoading {
                    ProgressView("Loading workouts…")
                } else if store.workouts.isEmpty, let error = store.error {
                    // A failed fetch is not an empty account (docs/known-issues.md §3).
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
                    VStack(spacing: 0) {
                        if activePlan != nil { weekStrip }

                        List {
                            banners

                            if activePlan == nil {
                                noPlanSection
                            } else {
                                daySection
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await store.refresh() }
                    }
                }
            }
            .navigationTitle("Today")
            .navigationDestination(item: $openedWorkoutID) { id in
                if let workout = store.workouts.first(where: { $0.id == id }) {
                    WorkoutDetailView(workout: workout)
                } else {
                    ContentUnavailableView("Workout not found", systemImage: "questionmark")
                }
            }
            .toolbar { toolbarContent }
        }
        .task { await store.load() }
    }

    // MARK: - The week strip

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let isSelected = day == selectedDay
                let isToday = day == today
                let count = activePlan?.slots.filter { $0.weekday == day }.count ?? 0

                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 4) {
                        Text(day.shortLabel)
                            .font(.caption.weight(isToday ? .bold : .regular))
                        Circle()
                            .fill(count > 0 ? Color.accentColor : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.15) : .clear,
                        in: .rect(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day, count: count, isToday: isToday))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func accessibilityLabel(for day: Weekday, count: Int, isToday: Bool) -> String {
        let workouts = count == 1 ? "1 workout" : "\(count) workouts"
        return "\(day.longLabel), \(workouts)\(isToday ? ", today" : "")"
    }

    // MARK: - Sections

    @ViewBuilder
    private var banners: some View {
        if let note = PhoneConnectivity.shared.watchNote {
            Section { WatchLinkWarning(note: note) }
        }

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
    }

    private var noPlanSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                // A failed plan fetch is not "no plan yet" (docs/known-issues.md §3). With an old
                // cache the workouts can be present while the schedule is missing; say which.
                Text(store.error == nil ? "No weekly plan yet" : "Can't reach your weekly plan")
                    .font(.headline)
                Text(store.error == nil
                     ? "Build one in the web app, or browse the workouts you already have."
                     : "The workouts you already have are still available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink("All workouts") { AllWorkoutsView() }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var daySection: some View {
        Section {
            if let plan = activePlan, plan.slots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This plan is empty").font(.headline)
                    Text("Add workouts to it in the web app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NavigationLink("All workouts") { AllWorkoutsView() }
                }
                .padding(.vertical, 4)
            } else if dayWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDay == today
                         ? "Nothing scheduled today"
                         : "Nothing scheduled on \(selectedDay.longLabel)")
                        .font(.headline)
                    Text("Rest day, or pick a workout from the library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NavigationLink("All workouts") { AllWorkoutsView() }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(dayWorkouts) { workout in
                    WorkoutRowView(workout: workout, showsSchedule: false) { id in
                        openedWorkoutID = id
                    }
                }
            }
        } header: {
            Text(selectedDay == today ? "Today · \(selectedDay.longLabel)" : selectedDay.longLabel)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                AllWorkoutsView()
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("All workouts")
        }

        if !store.weekPlans.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(store.weekPlans) { plan in
                        Button {
                            activePlanID = plan.id.uuidString
                        } label: {
                            if plan.id == activePlan?.id {
                                Label(plan.name, systemImage: "checkmark")
                            } else {
                                Text(plan.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activePlan?.name ?? "Plan")
                            .font(.subheadline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .accessibilityLabel("Choose weekly plan")
            }
        }

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

/// One workout on Today or in All Workouts.
///
/// The text is a button that opens the detail, and the play button starts immediately — one tap,
/// which is the point of the home screen. No `NavigationLink` around the row, so there is no
/// disclosure chevron between the text and the play button.
struct WorkoutRowView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(SessionHost.self) private var session

    let workout: Workout
    let showsSchedule: Bool
    let onOpen: (UUID) -> Void

    private var intervals: [Interval] { store.intervals(for: workout) }

    private var time: String {
        workout.preferredTime?.display ?? "Anytime"
    }

    private var memberships: String {
        let parts = store.weekPlans.compactMap { plan -> String? in
            let days = plan.slots
                .filter { $0.workoutID == workout.id }
                .map { $0.weekday.shortLabel }
            return days.isEmpty ? nil : "\(days.joined(separator: ", ")) · \(plan.name)"
        }
        return parts.isEmpty ? "Not in a plan" : parts.joined(separator: "; ")
    }

    var body: some View {
        // Built once: `metaLine` and `spokenMetaLine` are two readings of one estimate.
        let summary = WorkoutSummary(workout: workout, intervals: intervals, exercises: store.exercises)

        HStack(alignment: .center, spacing: 10) {
            Text(time)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .leading)
                .accessibilityLabel(workout.preferredTime.map { "preferred time \($0.display)" } ?? "anytime")

            Button {
                onOpen(workout.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.name)
                        .font(.headline)
                    Text(summary.metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(summary.spokenMetaLine)
                    if showsSchedule {
                        Text(memberships)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                session.begin(workout: workout, exercises: store.exercises)
            } label: {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.accentColor)
            .accessibilityLabel("Start \(workout.name)")
            .disabled(intervals.isEmpty)
        }
        .padding(.vertical, 2)
    }
}
