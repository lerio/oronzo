#if DEBUG
import ActivityKit
import Foundation
import OronzoCore

/// **Spike only — S1.** Starts a trivial Live Activity from a launch argument, so the
/// feasibility question ("does one provision, start and appear on the Lock Screen on a free
/// personal team?") can be answered without building any UI first.
///
/// Follows the same escape hatch as `-demoSession` / `-demoFinish`, and is compiled out of
/// release builds for the same reason. See `ios/Oronzo/Session/DemoPlan.swift`.
///
///     xcrun simctl launch booted com.lerio.oronzo -liveActivitySpike
///
/// The simulator cannot answer the real question — provisioning is the thing under test — so
/// this must run on a physical iPhone.
enum LiveActivitySpike {

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isRequested: Bool { arguments.contains("-liveActivitySpike") }
    static var endIsRequested: Bool { arguments.contains("-liveActivitySpikeEnd") }

    /// Starts the spike activity, replacing any left over from a previous run.
    ///
    /// It never surfaces an error to the user, and that is deliberate rather than lazy: a "no"
    /// is an answer to the feasibility question, not a failure. It also matches how the real
    /// surface must behave — an unavailable enhancement is never an error state
    /// (`docs/ui-design/0001-ui-polish.md` §5).
    static func runIfRequested() {
        guard isRequested || endIsRequested else { return }

        Task {
            // Clear first either way, so repeated runs do not stack up.
            await endAll()

            guard isRequested else { return }

            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                Log.debug("spike: Live Activities are disabled for this app")
                return
            }

            do {
                let activity = try Activity.request(
                    attributes: SpikeActivityAttributes(),
                    content: .init(state: .init(message: "Spike running"), staleDate: nil)
                )
                Log.debug("spike: started activity \(activity.id)")
            } catch {
                Log.debug("spike: could not start activity: \(error)")
            }
        }
    }

    private static func endAll() async {
        for activity in Activity<SpikeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            Log.debug("spike: ended activity \(activity.id)")
        }
    }
}
#endif
