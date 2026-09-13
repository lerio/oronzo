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
        .task { await auth.restore() }
    }
}
