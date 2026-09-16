// **Spike only — S1.** The Live Activity UI for the feasibility question. S7 replaces this.
//
// It is a widget extension because that is the only thing that can render a Live Activity:
// ActivityKit relays the content state, and the system asks this extension to draw it. Note
// that no App Groups are involved — the app does not hand the extension any data through a
// shared container, which is exactly why this is expected to work on a free personal team
// where App Groups are unavailable.

import ActivityKit
import SwiftUI
import WidgetKit
import OronzoCore

@main
struct OronzoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SpikeLiveActivity()
    }
}

struct SpikeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpikeActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            VStack(alignment: .leading, spacing: 4) {
                Text("ORONZO SPIKE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(context.state.message)
                    .font(.headline)
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("ORONZO")
                        .font(.caption2.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.message)
                        .font(.caption2)
                }
            } compactLeading: {
                Text("OR").font(.caption2.weight(.bold))
            } compactTrailing: {
                Text("SPK").font(.caption2)
            } minimal: {
                Text("OR").font(.caption2.weight(.bold))
            }
        }
    }
}
