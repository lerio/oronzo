import SwiftUI

@main
struct OronzoApp: App {
    @State private var auth = AuthStore()
    @State private var plans = PlanStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(plans)
                // Activated once, early, and left alone: there is exactly one WCSession and
                // it has to be running before a workout starts, not when one does.
                .task { PhoneConnectivity.shared.activate() }
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            // `-demoSession` goes straight to the runner, and `-demoSummary` to the plan
            // summary, so both can be looked at without an account or a backend. See DemoPlan.
            if let demo = DemoPlan.launchArgumentPlan {
                SessionRunner(plan: demo, exercises: DemoPlan.builderExercises)
            } else if DemoPlan.wantsSummary {
                NavigationStack {
                    PlanDetailView(plan: DemoPlan.builderShaped())
                }
                .environment(PlanStore.seeded(DemoPlan.builderExercises))
            } else {
                content
            }
            #else
            content
            #endif
        }
        .task { await auth.restore() }
        // Coming forward with nothing running tells the watch so. This is what clears a
        // phantom session left behind by a force-quit or a crash mid-workout.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PhoneConnectivity.shared.clearIfIdle() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !Backend.isConfigured {
            ConfigurationView()
        } else {
            switch auth.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn:
                PlanListView()
            }
        }
    }
}
