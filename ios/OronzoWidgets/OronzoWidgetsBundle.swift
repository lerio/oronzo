import ActivityKit
import OronzoCore
import SwiftUI
import WidgetKit

/// The Lock Screen surface.
///
/// A Live Activity is rendered by a widget extension and by nothing else: the app hands over a
/// small `SessionActivityContent` and the system asks this extension to draw it. No App Groups
/// are involved, which is the whole reason this works on a free personal team — the content state
/// is relayed by ActivityKit rather than shared through a container.
@main
struct OronzoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenSession(state: context.state)
                .padding()
                .activityBackgroundTint(Color(Palette.color(.background, .dark)))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StateWord(state: context.state, scheme: .dark)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Primary(state: context.state, scheme: .dark, size: TypeScale.size(.title, on: .phone))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.name)
                        .font(.system(size: TypeScale.size(.caption, on: .phone), weight: .semibold))
                        .foregroundStyle(ColorRole.text.color(.dark))
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(context.state.stateWord)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ColorRole.text.color(.dark))
            } compactTrailing: {
                Primary(state: context.state, scheme: .dark, size: TypeScale.size(.caption, on: .phone))
            } minimal: {
                Text(context.state.stateWord)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ColorRole.text.color(.dark))
            }
        }
    }
}

/// The Lock Screen presentation.
///
/// Direction A, like the watch: dense, high contrast, and state carried by a **word** rather than
/// by colour — which matters more here than anywhere, because this is read dimmed.
private struct LockScreenSession: View {

    let state: SessionActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingStep.tight.points) {
            HStack(alignment: .firstTextBaseline, spacing: SpacingStep.snug.points) {
                StateWord(state: state, scheme: .dark)
                Spacer(minLength: SpacingStep.snug.points)
                Primary(state: state, scheme: .dark, size: TypeScale.size(.title, on: .phone))
            }

            Text(state.name)
                .font(.system(size: TypeScale.size(.label, on: .phone), weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(.dark))
                .lineLimit(2)

            HStack(spacing: SpacingStep.snug.points) {
                if let context = state.context {
                    Text(context)
                        .font(.system(size: TypeScale.size(.caption, on: .phone), weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(ColorRole.muted.color(.dark))
                }
                if let next = state.next {
                    Spacer(minLength: SpacingStep.tight.points)
                    Text(next)
                        .font(.system(size: TypeScale.size(.caption, on: .phone), weight: .medium))
                        .foregroundStyle(ColorRole.text.color(.dark))
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The state word, built from `SessionScreen.StateWord` so all three surfaces spell it the same.
private struct StateWord: View {

    let state: SessionActivityContent
    let scheme: ColorScheme

    private var word: SessionScreen.StateWord {
        SessionScreen.StateWord(rawValue: state.stateWord) ?? .work
    }

    var body: some View {
        Text(state.stateWord)
            .font(.system(size: TypeScale.size(.caption, on: .phone), weight: .bold))
            // Maximum contrast, never a mid-tone: this is the signal that survives a bright room
            // and a dimmed screen, and colour is only reinforcement — the tint goes on the stroke.
            .foregroundStyle(ColorRole.text.color(scheme))
            .padding(.horizontal, SpacingStep.snug.points)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(ColorRole.reinforcement(for: word).color(scheme), lineWidth: 2)
            )
    }
}

/// The one thing that is actually *live*.
///
/// A timed interval hands the system an absolute end date and lets **it** run the countdown — no
/// per-second updates from the app, and it stays correct while the app is suspended. That is the
/// same principle that keeps the watch working with the phone in a pocket, and it is why the
/// payload carries a date rather than a number.
private struct Primary: View {

    let state: SessionActivityContent
    let scheme: ColorScheme
    let size: Double

    var body: some View {
        Group {
            if let remaining = state.remainingWhenPaused {
                // Paused: a running timer cannot be paused, so this is static text.
                Text(MeasurementFormat.clock(remaining: remaining))
            } else if let end = state.intervalEnd, end.timeIntervalSinceNow > 0 {
                // Guarded, because `Date()...end` traps if the end has already passed — and a
                // crash inside a widget extension is about as visible as a silent failure.
                Text(timerInterval: Date()...end, countsDown: true)
            } else if let reps = state.reps {
                // A rep interval has no length, so it shows its target and never a time.
                Text("\(reps) reps")
            } else {
                Text("—")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(ColorRole.text.color(scheme))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
