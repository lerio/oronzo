import SwiftUI

@main
struct OronzoApp: App {
    @State private var auth = AuthStore()
    @State private var plans = PlanStore()
    /// The workout, owned here rather than by the screen that started it. See `SessionHost`.
    @State private var session = SessionHost()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(plans)
                .environment(session)
                // Activated once, early, and left alone: there is exactly one WCSession and
                // it has to be running before a workout starts, not when one does.
                //
                // The host is handed over at the same moment, and before anything can be asked —
                // an answer has to be built from the session this app *has*, not only from the one
                // that has claimed the link. See `PhoneConnectivity.currentWatchMessage` for the
                // bug that gap was producing.
                .task {
                    PhoneConnectivity.shared.activate()
                    PhoneConnectivity.shared.host = session
                }
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(SessionHost.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            // `-demoSummary` shows the plan summary rather than the runner, so it can be looked at
            // without an account or a backend. See DemoPlan. (`-demoSession` no longer has a branch
            // of its own — it starts a session like any other, just one that is not written down,
            // so it cannot leave a fixture behind that a real launch would resume.)
            if DemoPlan.wantsSummary {
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
        // **Presented here rather than from the plan's own screen**, for two reasons. A workout
        // resumed at launch has no plan screen to be presented from; and a cover at the root
        // leaves the navigation stack intact underneath it, so finishing a workout puts you back
        // where you started rather than at the top of the list.
        .fullScreenCover(isPresented: presentation) {
            // Guarded, because `end()` clears the controller while the cover is dismissing, and
            // the two moments are not ordered.
            if let controller = session.controller {
                SessionRunner(controller: controller)
            }
        }
        .task {
            #if DEBUG
            if let demo = DemoPlan.launchArgumentPlan {
                // A fixture must not inherit a workout, and — unless it is the one flag that asks
                // to be written down — must not leave one either, or the next ordinary launch
                // resumes a session nobody started. Launch arguments can only be passed to an app
                // that is not running, so there is never a real session here to discard.
                if !DemoPlan.persistsRecord { SessionRecordFile.clear() }
                session.begin(
                    plan: demo,
                    exercises: DemoPlan.builderExercises,
                    persistsRecord: DemoPlan.persistsRecord,
                    // **Nobody did this workout, so nothing about it goes to Apple Health** — not
                    // even for `-demoRecord`, which is the one fixture that wants to be written
                    // down. It runs the full-length `DemoPlan.make()`, so the three-minute bar
                    // does not filter it, and a Health entry would outlive the phone: it would be
                    // a workout nobody did, sitting in the Fitness app, deleted by hand.
                    recordsHealth: false
                )
                await auth.restore()
                return
            }
            #endif
            // **The whole point of the record.** A workout that was in flight when the app went
            // away comes back, and with it the phone's ability to tell the watch the truth about
            // it. Nothing is resumed that the link would not also answer for — both go through
            // `SessionRecord.isLive`.
            session.restore()
            await auth.restore()
        }
        // Coming forward with nothing running tells the watch so. This is what clears a
        // phantom session left behind by a force-quit or a crash mid-workout.
        .onChange(of: scenePhase) { _, phase in
            // Guarded by `hasActiveSession` inside the link, which now counts the session this app
            // *has* rather than only the one that has claimed the link — so a workout that is
            // still starting cannot be cleared. See `PhoneConnectivity.currentWatchMessage`.
            if phase == .active { PhoneConnectivity.shared.clearIfIdle() }
        }
    }

    /// The runner is on screen exactly when there is a session — one rule, in one place.
    ///
    /// Dismissing it ends the session, which is what `SessionRunner`'s Done button does through
    /// `dismiss()`. So there is no longer any path by which a view going away takes a live workout
    /// with it: the only thing that ends a session is the thing that says it is ending one.
    private var presentation: Binding<Bool> {
        Binding(
            get: { session.isPresented },
            set: { presented in if !presented { session.end() } }
        )
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
