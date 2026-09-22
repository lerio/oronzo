import OronzoCore
import SwiftUI

/// What the watch is for: which exercise or break you are on, and how long is left.
///
/// Every *decision* — what the next line says, when `LAST` appears, that a rep interval never shows
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
                // Hermetic on purpose. The demo stands in for the phone, so it must not be
                // talked out of its own session by a real one — activation, the stored context
                // and the ask below would each do exactly that, and the screen would go blank
                // the moment a paired phone was in range.
                link.loadDemoSession()
                // Logged because a demo that silently failed to seed looks exactly like an
                // empty link, which is the ambiguity this whole file keeps having to remove.
                Log.debug("watch: demo seeded \(link.intervals.count) intervals")
                return
            }
            #endif
            link.activate()
            #if DEBUG
            if let every = Self.autoNextInterval {
                link.startAutoNext(everySeconds: every)
            }
            #endif
        }
        // Coming back from a wrist-drop suspension is a *resume*, not a re-activation, so
        // nothing else would tell the watch the phone had started something. See
        // `refreshFromContext`.
        //
        // It is also the one moment watchOS will grant an extended runtime session, so the
        // runtime is re-asserted here: a restart refused in the background succeeds now, and
        // without it a session lost mid-workout never comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                link.refreshFromContext()
                // And ask outright, rather than wait to be told again. The stored context is
                // what the phone sent *last*, which is no help when a push went missing — the
                // failure that reads as "No workout" for a whole workout. `askForState` is a
                // no-op when there is nothing worth asking about.
                link.askForState()
                runtime.setRunning(!link.intervals.isEmpty)
            }
        }
        // Only keep the app alive when there is something to keep it alive for.
        .onChange(of: link.intervals.isEmpty) { _, isEmpty in
            runtime.setRunning(!isEmpty)
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

    /// The information block. **Prev and next flank the primary**, and the primary is the pause
    /// control — there is no controls row underneath any more, which is the vertical space a
    /// 41 mm screen notices most.
    ///
    /// The text around the row is hidden from VoiceOver rather than re-announced: the composed
    /// label on the primary already states the same things in the order a person would say them,
    /// so leaving the pieces focusable would read all of it twice. Read as separate elements with
    /// no label at all, VoiceOver would announce a state word, a name, a number and a context in
    /// sequence with no relationship between them — which is what the composed form exists to fix.
    private func info(_ screen: SessionScreen) -> some View {
        VStack(spacing: SpacingStep.tight.points) {
            // Only the states the exercise name cannot say get a badge; see `showsBadge`. On a
            // 41 mm screen the line it frees goes to the name and the clock.
            if screen.stateWord.showsBadge {
                stateWordBadge(screen).accessibilityHidden(true)
            }
            name(screen).accessibilityHidden(true)

            primaryRow(screen)

            // The target load, under the primary and outside the row above, so it does not blink
            // with the timer. Always present — a rest and an unweighted exercise have none, and
            // the line coming and going would move the clock, which is the shifting this screen
            // has spent a pass removing. A space rather than an empty string, because `Text("")`
            // reserves less than a line of real text.
            Text(screen.weight ?? " ")
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(ColorRole.muted.color(colorScheme))
                .lineLimit(1, reservesSpace: true)
                .accessibilityHidden(true)

            if let context = screen.context {
                Text(context)
                    .font(.system(size: captionSize, weight: .semibold))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }

            if let next = screen.next {
                Text(next.label)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The primary, with the step controls either side of it.
    ///
    /// The clock is given `maxWidth: .infinity` and allowed to shrink, so the buttons keep their
    /// size and position as the primary grows to `62:30` or narrows to `8`. Sizing them by what
    /// the clock happens to say would move them under the thumb between intervals.
    private func primaryRow(_ screen: SessionScreen) -> some View {
        HStack(spacing: SpacingStep.snug.points) {
            stepControl("backward.fill", label: "Previous") { link.send(.previous) }

            primaryControl(screen)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            stepControl("forward.fill", label: "Next") { link.send(.next) }
        }
    }

    /// The primary, and the pause control when pausing means anything.
    ///
    /// Whether it is tappable is the model's decision, not this view's — see
    /// `SessionScreen.allowsPause`. A rep set has no clock to stop, so it is inert there. It stays
    /// live while the session is already paused, which keeps a session that was paused on a rest
    /// and then stepped onto a rep set recoverable; that is the job the old pause button did.
    ///
    /// The blink carries the paused state, so this is where it is applied. It gets its own
    /// `TimelineView` rather than borrowing the one around the whole screen: that one is there to
    /// move the countdown, and coupling a second, slower rhythm to it would make both harder to
    /// reason about — and the two would drift whenever either rate changed.
    private func primaryControl(_ screen: SessionScreen) -> some View {
        TimelineView(.periodic(from: .now, by: PausedTimerBlink.sampleInterval)) { context in
            let content = primary(screen)

            // Both branches carry the composed label: it belongs on the thing you are looking at,
            // whether or not that thing is also a button.
            Group {
                if screen.allowsPause {
                    Button { link.send(.togglePause) } label: { content }
                        .buttonStyle(.plain)
                        .accessibilityHint(isPaused ? "Double tap to resume" : "Double tap to pause")
                } else {
                    content
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(screen.accessibilityAnnouncement)
            .opacity(PausedTimerBlink.opacity(isPaused: isPaused, at: context.date))
        }
    }

    /// The state word carries the meaning; the colour only reinforces it.
    ///
    /// It appears only for the states the exercise name cannot express — `PAUSED` and `DONE`.
    /// The word is drawn in `text` — maximum contrast — because nothing essential is allowed to be
    /// a mid-tone that dies in a bright gym, and the state colour goes on the capsule instead,
    /// where it costs no legibility.
    ///
    /// It is kept for those two rather than dropped outright because they are the moments a glance
    /// is least reliable: the clock has stopped, and the countdown alone cannot say whether that is
    /// a rest, a pause, or the end. This is also the element that replaced signalling rest by
    /// *dimming the clock* — colour-only, and nothing to a colour-blind user or a dimmed screen.
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

    /// The name, always two rows tall whatever it needs.
    ///
    /// A one-line name and a two-line name must be the same interval to everything below them —
    /// the clock, the context and the next-up line all sit on a fixed line rather than stepping
    /// up and down as the session advances. On a 41 mm screen the alternative is a clock that
    /// moves between every interval, which is the one thing a glance cannot absorb.
    private func name(_ screen: SessionScreen) -> some View {
        Text(screen.name)
            .font(.system(size: titleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.55)
            .lineLimit(2, reservesSpace: true)
    }

    @ViewBuilder
    private func primary(_ screen: SessionScreen) -> some View {
        switch screen.primary {
        case .clock(let remaining):
            Text(MeasurementFormat.clock(remaining: remaining))
                .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))

        case .reps(let reps):
            // The unit rides beside the target instead of under it, freeing the line the name
            // needed more. `title` rather than `caption`: beside a figure this size a caption-
            // sized `x` reads as a footnote rather than as the unit.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(reps)")
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                Text("x")
                    .font(.system(size: titleSize, weight: .semibold))
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

    /// Hand-rolled rather than `.bordered`: the system style makes buttons wide enough that they
    /// run off both edges of the screen.
    ///
    /// Shrunk from the size these were when they sat in a row of three. They now share a line
    /// with a 48pt clock, and on a 41 mm screen that is the whole width — the glyph is what is
    /// aimed at, and the padding around it is the target.
    private func stepControl(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                // `.plain` overrides the tint, so the glyph colour is set explicitly rather than
                // inherited, and the shared `muted` role is what makes it subordinate to the
                // clock beside it. No `accent`: these are navigation, not the action this screen
                // is for.
                .foregroundStyle(ColorRole.muted.color(colorScheme))
                .frame(width: 32, height: 32)
                .background(.quaternary, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        // Icon-only, so without a label VoiceOver announces anonymous buttons.
        .accessibilityLabel(label)
    }

    private var isPaused: Bool { link.state?.isPaused ?? false }

    #if DEBUG
    /// The interval from `-autoNext <seconds>`. See `WatchLink.startAutoNext` for why the watch
    /// can press its own buttons in a debug build.
    private static var autoNextInterval: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autoNext"),
              arguments.indices.contains(flag + 1)
        else { return nil }
        return Double(arguments[flag + 1])
    }
    #endif
}

#Preview {
    WatchSessionView()
}
