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
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            #if DEBUG
            // `-demoSession` goes straight to the runner, so it can be looked at without an
            // account or a backend. See DemoPlan.
            if let demo = DemoPlan.launchArgumentPlan {
                SessionRunner(plan: demo, exerciseNames: [:])
            } else {
                content
            }
            #else
            content
            #endif
        }
        .task { await auth.restore() }
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
