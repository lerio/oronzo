import SwiftUI

/// Milestone M0 placeholder. Replaced by the plan list and session engine in M4–M5.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(AppInfo.name)
                .font(.largeTitle.bold())
            Text("shared: \(AppInfo.buildLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("M0 toolchain check")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
