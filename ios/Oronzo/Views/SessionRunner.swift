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
/// draws from, so the two cannot disagree about the state word, what rest promotes, or `LAST`.
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
            stateWordBadge(screen)
            intervalName(screen)
            primary(screen)

            if let label = screen.context {
                Text(label)
                    .font(.system(size: labelSize, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
                    .padding(.top, SpacingStep.snug.points)
            }

            if let next = screen.next {
                Text(label(for: next))
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
    /// This element did not exist before: rest used to be signalled by *dimming the clock*, which
    /// is colour-only signalling and gives nothing to a colour-blind user or a dimmed screen. The
    /// word is drawn in `text` at maximum contrast, and the state colour goes on the stroke.
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
                .lineLimit(2)

            // Phone-only detail: the watch has no room for it, and the shared model carries
            // only what the two surfaces must agree on.
            if let weight = controller.current?.weightDisplay, controller.current?.kind == .exercise {
                Text(weight)
                    .font(.system(size: captionSize))
                    .foregroundStyle(ColorRole.muted.color(colorScheme))
            }
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
            VStack(spacing: 0) {
                Text("\(reps)")
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                Text("reps")
                    .font(.system(size: labelSize))
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

    private func label(for next: SessionScreen.Next) -> String {
        switch next {
        case .exercise(let name): "NEXT · \(name)"
        case .last: "LAST"
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

            Button {
                controller.advance()
            } label: {
                // "Done" for a rep set, "skip ahead" for a timed one.
                Image(systemName: controller.current?.advancesAutomatically == true
                      ? "forward.fill" : "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ColorRole.accent.color(colorScheme))
                    .frame(width: 60, height: 60)
                    .background(ColorRole.accent.color(colorScheme).opacity(0.14), in: .circle)
            }
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
