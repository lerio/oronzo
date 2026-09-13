import OronzoCore
import SwiftUI

/// Milestone M0 screen. Proves four things at once on real hardware:
///   1. the watch app installs and launches on a free personal team,
///   2. `ios/Shared/` is genuinely compiled into the watch target,
///   3. an extended-runtime session starts (the workout-viability question), and
///   4. session-driven haptics work.
///
/// This view is scaffolding and gets replaced by the real interval display in M6.
struct WatchProbeView: View {
    @State private var probe = ExtendedRuntimeProbe()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                status
                Divider()
                controls
                if let error = probe.lastError {
                    Divider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppInfo.name)
                .font(.headline)
            // Renders only if ios/Shared/ reached this target.
            Text("shared: \(AppInfo.buildLabel) • M0 probe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 9, height: 9)
                Text(probe.phase.rawValue)
                    .font(.system(.body, design: .rounded).bold())
            }
            Text(probe.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let expiration = probe.expirationDate {
                Text("expires \(expiration, style: .relative)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Button {
                probe.start()
            } label: {
                Label("Start session", systemImage: "play.fill")
            }
            .disabled(probe.isActive)

            Button(role: .destructive) {
                probe.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!probe.isActive)

            Button {
                probe.fireTestHaptic()
            } label: {
                Label("Test haptic", systemImage: "hand.tap.fill")
            }
            .disabled(probe.phase != .running)
        }
        .font(.system(size: 13))
    }

    private var indicatorColor: Color {
        switch probe.phase {
        case .running: .green
        case .starting: .yellow
        case .idle, .stopped: .gray
        default: .red
        }
    }
}

#Preview {
    WatchProbeView()
}
