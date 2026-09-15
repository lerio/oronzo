import OronzoCore
import SwiftUI

/// What the watch is for: which exercise or break you are on, and how long is left.
struct WatchSessionView: View {

    @Environment(\.scenePhase) private var scenePhase

    @State private var link = WatchLink()
    @State private var runtime = WatchRuntime()

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
        VStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No workout")
                .font(.headline)
            Text("Start a plan on your iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Running

    private var running: some View {
        // A quarter-second tick keeps the seconds from looking stuck; the phone does not
        // need to send anything for this to stay correct.
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let (index, end) = link.position(at: context.date)
            let interval = link.interval(at: index)

            VStack(spacing: 2) {
                if let label = contextLabel(interval, index: index) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text(interval?.name ?? "—")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .padding(.top, 1)

                clock(interval: interval, end: end, now: context.date)

                controls
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func clock(interval: Interval?, end: Date?, now: Date) -> some View {
        if let end {
            let remaining = max(0, end.timeIntervalSince(now))
            Text(clockText(remaining))
                .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(interval?.kind == .rest ? .secondary : .primary)
        } else if let reps = interval?.reps {
            VStack(spacing: -2) {
                Text("\(reps)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                Text("reps")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
        }
    }

    /// Hand-rolled rather than `.bordered`: the system style makes buttons wide enough that
    /// three of them run off both edges of the screen.
    private var controls: some View {
        HStack(spacing: 7) {
            controlButton("backward.fill") { link.send(.previous) }
            controlButton(isPaused ? "play.fill" : "pause.fill", prominent: true) {
                link.send(.togglePause)
            }
            controlButton("forward.fill") { link.send(.next) }
        }
    }

    private func controlButton(
        _ symbol: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // A filled button, as on the phone: `.plain` overrides the tint, so the
                // glyph colour has to be set explicitly rather than inherited.
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 38, height: 34)
                .background(
                    // Neither `.tint` nor `Color.accentColor` resolves to a blue accent on
                    // watchOS here — the watch target has no asset catalogue defining one —
                    // so this renders as a light fill rather than a coloured one. It still
                    // reads as the primary control, which is the point; set an AccentColor
                    // asset if you want it blue.
                    prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
    }

    private var isPaused: Bool { link.state?.isPaused ?? false }

    private func contextLabel(_ interval: Interval?, index: Int) -> String? {
        guard let interval else { return nil }
        if interval.setCount > 1 { return "Set \(interval.setIndex) of \(interval.setCount)" }
        if interval.blockRoundCount > 1 { return "Round \(interval.blockRound) of \(interval.blockRoundCount)" }
        return interval.blockName
    }

    private func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    WatchSessionView()
}
