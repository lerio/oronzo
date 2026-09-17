import OronzoCore
import SwiftUI

/// What the watch is for: which exercise or break you are on, and how long is left.
///
/// Every *decision* — what rest promotes, when `LAST` appears, that a rep interval never shows
/// a time — lives in `OronzoCore.SessionPresentation`, where it is tested on macOS. This file only
/// draws the result. That split is what stops the layout quietly disagreeing with the rules,
/// which is the failure mode a screen this small invites.
struct WatchSessionView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var link = WatchLink()
    @State private var runtime = WatchRuntime()

    // Text scales with Dynamic Type; the clock deliberately does not. `@ScaledMetric` is how
    // SwiftUI scales a custom size, and `primarySize` being a plain constant *is* the cap the
    // design asks for — capping a fixed-purpose instrument is defensible where capping body
    // text would not be. Verified at the largest accessibility size: `primary`, the name and
    // the state word must all stay visible without scrolling.
    @ScaledMetric(relativeTo: .headline) private var titleSize = TypeScale.size(.title, on: .watch)
    @ScaledMetric(relativeTo: .body) private var labelSize = TypeScale.size(.label, on: .watch)
    @ScaledMetric(relativeTo: .caption) private var captionSize = TypeScale.size(.caption, on: .watch)
    private let primarySize = TypeScale.size(.primary, on: .watch)

    var body: some View {
        Group {
            if link.intervals.isEmpty {
                idle
            } else {
                running
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoSession") {
                link.loadDemoSession()
            }
            #endif
            link.activate()
        }
        // Coming back from a wrist-drop suspension is a *resume*, not a re-activation, so
        // nothing else would tell the watch the phone had started something. See
        // `refreshFromContext`.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.refreshFromContext() }
        }
        // Only keep the app alive when there is something to keep it alive for.
        .onChange(of: link.intervals.isEmpty) { _, isEmpty in
            if isEmpty {
                runtime.stop()
            } else {
                runtime.start()
            }
        }
    }

    // MARK: - Nothing running

    private var idle: some View {
        VStack(spacing: SpacingStep.snug.points) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(ColorRole.muted.color(colorScheme))
            Text("No workout")
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(colorScheme))
            Text("Start a plan on your iPhone")
                .font(.system(size: captionSize))
                .foregroundStyle(ColorRole.muted.color(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, SpacingStep.tight.points)
    }

    // MARK: - Running

    private var running: some View {
        // A quarter-second tick keeps the seconds from looking stuck; the phone does not
        // need to send anything for this to stay correct.
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            if let screen = screen(at: context.date) {
                content(screen)
            }
        }
    }

    private func screen(at now: Date) -> SessionScreen? {
        let (index, end) = link.position(at: now)
        return SessionPresentation.screen(
            intervals: link.intervals,
            index: index,
            end: end,
            isPaused: link.state?.isPaused ?? false,
            isFinished: link.state?.isFinished ?? false,
            planName: link.planName,
            startedAt: link.startedAt,
            finishedAt: link.finishedAt,
            now: now
        )
    }

    private func content(_ screen: SessionScreen) -> some View {
        VStack(spacing: SpacingStep.tight.points) {
            info(screen)
            controls

            // Only ever set when watchOS ended the runtime session itself. Without this
            // the workout just stops advancing and nothing says why.
            if let note = runtime.note {
                Text(note)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(ColorRole.danger.color(colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, SpacingStep.tight.points)
    }

    /// The information block, as **one** accessibility element.
    ///
    /// Read as separate elements, VoiceOver would announce a state word, a name, a number and a
    /// context in sequence with no relationship between them. The composed label states the same
    /// thing in the order a person would say it — and, for a rep interval, omits the time rather
    /// than announcing a stale one.
    private func info(_ screen: SessionScreen) -> some View {
        VStack(spacing: SpacingStep.tight.points) {
            stateWordBadge(screen)
            name(screen)
            primary(screen)

            if let context = screen.context {
                Text(context)
                    .font(.system(size: captionSize, weight: .semibold))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
                    .textCase(.uppercase)
                    .lineLimit(1)
            }

            if let next = screen.next {
                Text(next.label)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(screen.accessibilityAnnouncement)
    }

    /// The state word carries the meaning; the colour only reinforces it.
    ///
    /// The word is drawn in `text` — maximum contrast — because it is the colour-independent
    /// signal both glance metrics depend on, and nothing essential is allowed to be a mid-tone
    /// that dies in a bright gym. The state colour goes on the capsule instead, where it costs
    /// no legibility. `accent` and `rest` are required by test to differ in *luminance*, so the
    /// reinforcement still reads as two states when dimmed or in greyscale.
    private func stateWordBadge(_ screen: SessionScreen) -> some View {
        Text(screen.stateWord.rawValue)
            .font(.system(size: labelSize, weight: .bold))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .padding(.horizontal, SpacingStep.snug.points)
            .overlay(
                Capsule().stroke(
                    ColorRole.reinforcement(for: screen.stateWord).color(colorScheme),
                    lineWidth: 2
                )
            )
    }

    private func name(_ screen: SessionScreen) -> some View {
        Text(screen.name)
            .font(.system(size: titleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.55)
            .lineLimit(2)
    }

    @ViewBuilder
    private func primary(_ screen: SessionScreen) -> some View {
        switch screen.primary {
        case .clock(let remaining):
            Text(MeasurementFormat.clock(remaining: remaining))
                .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))

        case .reps(let reps):
            VStack(spacing: -2) {
                Text("\(reps)")
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                Text("reps")
                    .font(.system(size: captionSize))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
            }

        case .elapsed(let elapsed):
            // The same M:SS shape as the clock, read as a duration rather than a countdown.
            Text(MeasurementFormat.clock(remaining: elapsed))
                .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))

        case nil:
            Text("—")
                .font(.system(size: primarySize, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(colorScheme))
        }
    }

    // MARK: - Controls

    /// Hand-rolled rather than `.bordered`: the system style makes buttons wide enough that
    /// three of them run off both edges of the screen.
    private var controls: some View {
        HStack(spacing: 7) {
            controlButton("backward.fill", label: "Previous") { link.send(.previous) }
            controlButton(
                isPaused ? "play.fill" : "pause.fill",
                label: isPaused ? "Resume" : "Pause",
                prominent: true
            ) { link.send(.togglePause) }
            controlButton("forward.fill", label: "Next") { link.send(.next) }
        }
    }

    private func controlButton(
        _ symbol: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // A filled button, as on the phone: `.plain` overrides the tint, so the
                // glyph colour has to be set explicitly rather than inherited.
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(ColorRole.muted.color(colorScheme)))
                .frame(width: 38, height: 34)
                .background(
                    // The shared `accent` role rather than `Color.accentColor`. The system
                    // accent never resolved on this target — the watch has no asset catalogue
                    // declaring one — so it used to render as a plain fill. The vocabulary
                    // fixes that without needing an asset.
                    prominent
                        ? AnyShapeStyle(ColorRole.accent.color(colorScheme))
                        : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
        // These are icon-only, so without a label VoiceOver announces three anonymous buttons.
        .accessibilityLabel(label)
    }

    private var isPaused: Bool { link.state?.isPaused ?? false }
}

#Preview {
    WatchSessionView()
}
