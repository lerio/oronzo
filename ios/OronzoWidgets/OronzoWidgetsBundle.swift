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
                    if context.state.stateWordValue.showsBadge {
                        StateWord(state: context.state, scheme: .dark)
                            .padding(.leading, 4)
                    }
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
                // `compactLabel`, not the state word: these two presentations have room for one
                // string, so dropping `WORK`/`REST` without putting something in its place would
                // leave this slot empty and `minimal` — which is only the word — entirely blank.
                Text(context.state.compactLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ColorRole.text.color(.dark))
            } compactTrailing: {
                Primary(state: context.state, scheme: .dark, size: TypeScale.size(.caption, on: .phone))
            } minimal: {
                Text(context.state.compactLabel)
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
                // Only the states the exercise name cannot say; the name gets its own line just
                // below, so `WORK`/`REST` here would only restate it.
                if state.stateWordValue.showsBadge {
                    StateWord(state: state, scheme: .dark)
                }
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

private extension SessionActivityContent {

    /// The wire form is a `String`, because the payload crosses into a widget extension. Parsing
    /// it back is how this surface reads the same `showsBadge` rule as the phone and the watch
    /// rather than restating it — the fallback is `work`, which is what an older build's payload
    /// means by default.
    var stateWordValue: SessionScreen.StateWord {
        SessionScreen.StateWord(rawValue: stateWord) ?? .work
    }

    /// The one string the compact and minimal presentations have room for.
    ///
    /// Both showed only the state word, so removing `WORK`/`REST` would leave the Dynamic Island's
    /// leading slot empty and `minimal` — which is nothing but the word — entirely blank. The
    /// exercise name answers the same question, and there is always one.
    var compactLabel: String {
        stateWordValue.showsBadge ? stateWord : name
    }
}

/// The state word, built from `SessionScreen.StateWord` so all three surfaces spell it the same.
private struct StateWord: View {

    let state: SessionActivityContent
    let scheme: ColorScheme

    private var word: SessionScreen.StateWord {
        state.stateWordValue
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
                // A rep interval has no length, so it shows its target and never a time. The unit
                // is a suffix rather than a word, as on the two runners.
                //
                // One size here, where the runners draw the `x` smaller than the number. This
                // view is used at 34pt on the Lock Screen and 15pt in the compact Dynamic Island,
                // and a glyph sized as a fraction of a number that swings across that range is
                // illegible at the bottom of it. The runners have a 48–96pt figure, where an
                // equal-sized unit would dominate it; at 34pt and below it does not.
                Text("\(reps)x")
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
