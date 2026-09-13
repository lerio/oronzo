import SwiftUI

/// Shown when the app was built without `ios/Local.xcconfig` — which is what a fresh
/// clone looks like. Better than a crash inside a network call.
struct ConfigurationView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Not configured", systemImage: "gearshape")
        } description: {
            Text("This build has no Supabase project configured.")
        } actions: {
            VStack(alignment: .leading, spacing: 8) {
                Text("From the repository root:")
                    .font(.footnote.weight(.semibold))
                Text("cp ios/Local.xcconfig.example ios/Local.xcconfig")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Fill in your project ref and publishable key, then rebuild.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
}
