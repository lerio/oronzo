import OronzoCore
import SwiftUI
import UIKit

/// The workout runner: a live countdown, the controls, and a summary at the end.
///
/// The logic lives in `SessionController` and, below that, in `OronzoCore`'s engine — this
/// file only decides what that looks like.
struct SessionRunner: View {

    @Environment(\.dismiss) private var dismiss

    @State private var controller: SessionController
    @State private var saving: SaveState = .idle
    @State private var confirmingFinish = false

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

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
        .onAppear {
            controller.start()
            // A workout is not the moment for the screen to lock.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            controller.teardown()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // Runs again when the session ends, which is when there is something to save.
        .task(id: controller.completed?.startedAt) {
            guard case .idle = saving, let session = controller.completed else { return }
            await persist(session)
        }
    }

    // MARK: - Running

    private var runner: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 16)
            context
            intervalName
            clock
            Spacer(minLength: 16)
            nextUp
            controls
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 28)
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

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.planName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(controller.position) of \(controller.totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("End") { confirmingFinish = true }
                .font(.subheadline)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var context: some View {
        if let interval = controller.current, let text = interval.contextLabel {
            Text(text)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                // AnyShapeStyle because the two branches are different style types.
                .foregroundStyle(interval.kind == .rest ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
    }

    @ViewBuilder
    private var intervalName: some View {
        if let interval = controller.current {
            Text(interval.name)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(.top, 4)

            if let weight = interval.weightDisplay, interval.kind == .exercise {
                Text(weight)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A timed interval counts down; a rep interval has no end, so it shows the target and
    /// waits for a tap.
    @ViewBuilder
    private var clock: some View {
        if let remaining = controller.remaining {
            Text(MeasurementFormat.clock(remaining: remaining))
                .font(.system(size: 84, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .padding(.vertical, 8)
        } else if let reps = controller.current?.reps {
            VStack(spacing: 0) {
                Text("\(reps)")
                    .font(.system(size: 84, weight: .semibold, design: .rounded).monospacedDigit())
                Text("reps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            Text("—")
                .font(.system(size: 84, weight: .semibold, design: .rounded))
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = controller.next {
            HStack(spacing: 6) {
                Text("Next")
                    .foregroundStyle(.tertiary)
                Text(next.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.footnote)
            .padding(.bottom, 20)
        } else {
            Spacer().frame(height: 20)
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button {
                controller.goBack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .background(.quaternary, in: .circle)
            }
            .disabled(controller.position <= 1)

            Button {
                controller.isPaused ? controller.resume() : controller.pause()
            } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(.tint, in: .circle)
            }

            Button {
                controller.advance()
            } label: {
                // "Done" for a rep set, "skip ahead" for a timed one.
                Image(systemName: controller.current?.advancesAutomatically == true
                      ? "forward.fill" : "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 60, height: 60)
                    .background(.tint.opacity(0.14), in: .circle)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

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
