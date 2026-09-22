import OronzoCore
import SwiftUI

/// The session runner: what you are doing now, how long is left, and what is coming.
///
/// Direction B — *quiet coach* — with the distance requirement from
/// `docs/ui-design/0001-ui-polish.md` §4: the phone sits on a surface and is read from 1–2
/// metres, so `primary` is sized by **that** rather than by how much room is left over. Where
/// calm and the requirement conflict, the requirement wins: generous whitespace around a very
/// large figure, not a uniformly small screen.
///
/// What is shown comes from `SessionPresentation` in `OronzoCore`, the same model the watch
/// draws from, so the two cannot disagree about the state word, what the next line says, or `LAST`.
struct SessionRunner: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var controller: SessionController
    @State private var saving: SaveState = .idle
    @State private var confirmingFinish = false

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    // Text scales with Dynamic Type; the distance-critical figure deliberately does not, for the
    // same reason the watch caps its clock. Capping a fixed-purpose instrument is defensible
    // where capping body text would not be.
    @ScaledMetric(relativeTo: .title2) private var titleSize = TypeScale.size(.title, on: .phone)
    @ScaledMetric(relativeTo: .body) private var labelSize = TypeScale.size(.label, on: .phone)
    @ScaledMetric(relativeTo: .caption) private var captionSize = TypeScale.size(.caption, on: .phone)
    private let primarySize = TypeScale.size(.primary, on: .phone)

    @MainActor
    init(plan: Plan, exerciseNames: [UUID: String]) {
        _controller = State(initialValue: SessionController(plan: plan, exerciseNames: exerciseNames))
    }

    var body: some View {
        Group {
            if let completed = controller.completed {
                summary(completed)
            } else {
                runner
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.teardown() }
    }

    // MARK: - Running

    private var runner: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: SpacingStep.roomy.points)
            live
            Spacer(minLength: SpacingStep.roomy.points)
            controls
        }
        .padding(.horizontal, SpacingStep.edge.points)
        .padding(.top, SpacingStep.roomy.points)
        .padding(.bottom, SpacingStep.edge.points)
        .confirmationDialog(
            "End this workout early?",
            isPresented: $confirmingFinish,
            titleVisibility: .visible
        ) {
            Button("End workout", role: .destructive) { controller.finishEarly() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("What you have done so far is still recorded.")
        }
    }

    @ViewBuilder
    private var live: some View {
        if let screen = controller.screen(at: .now) {
            // Only the states the exercise name cannot say get a badge — which on this surface
            // means `PAUSED` alone. A finished session replaces the runner with the summary, so
            // `DONE` never reaches here.
            if screen.stateWord.showsBadge {
                stateWordBadge(screen)
            }
            intervalName(screen)
            // The paused state is carried by the timer blinking, not by a badge: a badge is a
            // line that appears and pushes the title and the clock down as it does, which is the
            // shifting this screen has just spent a pass getting rid of.
            //
            // Its own `TimelineView` because the runner's re-render is driven by the session tick,
            // and the tick stops when the session is paused — so a paused screen would never
            // redraw, and the blink would sit at whichever half it happened to be caught in.
            //
            // The same construct and the same rule as the watch. A `.repeatForever` opacity
            // animation was tried first and settles rather than oscillating, leaving the timer
            // invisible for the whole pause.
            TimelineView(.periodic(from: .now, by: PausedTimerBlink.sampleInterval)) { context in
                primary(screen)
                    .opacity(PausedTimerBlink.opacity(isPaused: controller.isPaused, at: context.date))
            }

            // The target load sits under the primary, not under the name: the two are one figure
            // — "8x at 20 kg" — and a weight that names the exercise above the number reads as
            // part of the title. `label` rather than `caption`, a step up, because a load is a
            // number you act on rather than chrome you read past.
            //
            // Outside the timeline above, so it does not blink with the timer, and always
            // present: a rest and an unweighted exercise have no weight, and letting the line
            // come and go moved the clock by the same 33pt a one-row name did. A space rather
            // than an empty string — `Text("")` reserves 6px less than a line of real text.
            Text(screen.weight ?? " ")
                .font(.system(size: labelSize))
                .foregroundStyle(ColorRole.muted.color(colorScheme))
                .lineLimit(1, reservesSpace: true)

            if let label = screen.context {
                Text(label)
                    .font(.system(size: labelSize, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
                    .padding(.top, SpacingStep.snug.points)
            }

            if let next = screen.next {
                Text(next.label)
                    // `label`, not `caption`. The type-role table names the next-up line as
                    // caption-sized, but §4's distance rule is the stricter constraint and it
                    // says nothing essential may sit below `label` — and §2 lists the next-up
                    // line as essential. At 15pt this was illegible at 1–2 metres, which is the
                    // one thing this screen exists to survive.
                    .font(.system(size: labelSize, weight: .medium))
                    // Essential, so `text` rather than a dimmed tone — subordination here is
                    // carried by size. A mid-tone is what dies across a room.
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, SpacingStep.roomy.points)
            }
        }
    }

    /// The state word carries the meaning; the colour only reinforces it.
    ///
    /// It exists for the states the exercise name cannot express, and here that is `PAUSED` —
    /// where the clock has stopped and nothing else on screen says why. The word is drawn in
    /// `text` at maximum contrast and the state colour goes on the stroke, so the badge never
    /// depends on colour to be read: this element replaced signalling rest by *dimming the
    /// clock*, which is colour-only and gives nothing to a colour-blind user or a dimmed screen.
    private func stateWordBadge(_ screen: SessionScreen) -> some View {
        Text(screen.stateWord.rawValue)
            .font(.system(size: labelSize, weight: .bold))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .padding(.horizontal, SpacingStep.snug.points)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(
                    ColorRole.reinforcement(for: screen.stateWord).color(colorScheme),
                    lineWidth: 2
                )
            )
            .padding(.bottom, SpacingStep.snug.points)
    }

    private func intervalName(_ screen: SessionScreen) -> some View {
        VStack(spacing: SpacingStep.tight.points) {
            Text(screen.name)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                // Two rows' height whatever the name needs.
                //
                // A one-line name and a two-line name must be the same interval to everything
                // below them, or the figure underneath moves up and down as the session advances
                // and has to be re-found each time. This screen is read from a metre away, which
                // is exactly where a moving target costs the most.
                .lineLimit(2, reservesSpace: true)
        }
    }

    /// A timed interval counts down; a rep interval has no end, so it shows the target and waits.
    @ViewBuilder
    private func primary(_ screen: SessionScreen) -> some View {
        switch screen.primary {
        case .clock(let remaining):
            Text(MeasurementFormat.clock(remaining: remaining))
                .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .contentTransition(.numericText(countsDown: true))
                .padding(.vertical, SpacingStep.snug.points)

        case .reps(let reps):
            // The unit rides beside the target instead of under it. That row was a full line of
            // the screen's height, and the line it frees is one the name needed more. `title`
            // rather than `caption`: at `caption` beside a figure this size the `x` reads as a
            // footnote rather than as the unit, and the number stops looking like a target.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(reps)")
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                Text("x")
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
            }
            .padding(.vertical, SpacingStep.snug.points)

        case .elapsed(let elapsed):
            Text(MeasurementFormat.clock(remaining: elapsed))
                .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .padding(.vertical, SpacingStep.snug.points)

        case nil:
            Text("—")
                .font(.system(size: primarySize, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .padding(.vertical, SpacingStep.snug.points)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.planName)
                    .font(.system(size: captionSize, weight: .semibold))
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                    .lineLimit(1)
                Text("\(controller.position) of \(controller.totalCount)")
                    .font(.system(size: captionSize).monospacedDigit())
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
            }
            Spacer()
            Button("End") { confirmingFinish = true }
                .font(.system(size: captionSize))
                .buttonStyle(.bordered)
        }
    }

    /// Whether a pause control applies, from the shared model so the watch cannot disagree.
    ///
    /// Defaults to offering it: a screen that failed to build is no reason to take a control
    /// away, and `allowsPause` needs a real `SessionScreen` to answer.
    private var allowsPause: Bool {
        controller.screen(at: .now)?.allowsPause ?? true
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button {
                controller.goBack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
                    .frame(width: 60, height: 60)
                    .background(.quaternary, in: .circle)
            }
            .disabled(controller.position <= 1)
            .accessibilityLabel("Previous")

            if allowsPause {
                Button {
                    controller.isPaused ? controller.resume() : controller.pause()
                } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(ColorRole.accent.color(colorScheme), in: .circle)
                }
                .accessibilityLabel(controller.isPaused ? "Resume" : "Pause")
            } else {
                // The slot is held open rather than closed up. Recentring the two remaining
                // controls would move them between every interval, and a control that moves is
                // one you have to look for — on a screen read from a metre away, mid-set.
                Color.clear.frame(width: 84, height: 84)
            }

            Button {
                controller.advance()
            } label: {
                // One glyph for both meanings. The checkmark it used to show on a rep set read as
                // "confirm what you just saw", which is not what the tap does — it moves you on,
                // the same as on a timed interval. The meanings differ; the glyph does not have to.
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ColorRole.accent.color(colorScheme))
                    .frame(width: 60, height: 60)
                    .background(ColorRole.accent.color(colorScheme).opacity(0.14), in: .circle)
            }
            // The label still carries the distinction the glyph no longer does: on a rep set the
            // tap finishes *your* set, and saying "skip ahead" there would invite you to think you
            // were abandoning it.
            .accessibilityLabel(
                controller.current?.advancesAutomatically == true ? "Skip ahead" : "Done with this set"
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary
    //
    // Deferred: the design scoped the live runner and left the seconds-long screens to a
    // follow-up, so this keeps the system styles and the existing copy.

    private func summary(_ session: CompletedSession) -> some View {
        let done = session.steps.count { $0.status == .completed }
        let skipped = session.steps.count { $0.status == .skipped }
        let notReached = session.steps.count { $0.status == .notReached }

        return VStack(spacing: 20) {
            Spacer()

            Image(systemName: session.status == .completed ? "checkmark.circle.fill" : "flag.checkered")
                .font(.system(size: 60))
                .foregroundStyle(session.status == .completed ? .green : .orange)

            VStack(spacing: 4) {
                Text(session.status == .completed ? "Workout complete" : "Session ended early")
                    .font(.title2.bold())
                Text(controller.planName)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 26) {
                stat(MeasurementFormat.clock(remaining: session.totalDuration), "time")
                stat("\(done)", "done")
                if skipped > 0 { stat("\(skipped)", "skipped") }
                if notReached > 0 { stat("\(notReached)", "not reached") }
            }
            .padding(.top, 4)

            saveStatus

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch saving {
        case .idle, .saving:
            Label("Saving to history…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .saved:
            Label("Saved to history", systemImage: "checkmark.icloud.fill")
                .font(.footnote)
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(spacing: 8) {
                Label("Not saved — \(message)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    guard let session = controller.completed else { return }
                    Task { await persist(session) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func persist(_ session: CompletedSession) async {
        saving = .saving
        do {
            try await SessionLogger().log(
                session,
                planID: controller.planID,
                planName: controller.planName
            )
            saving = .saved
        } catch {
            saving = .failed(error.localizedDescription)
        }
    }
}
