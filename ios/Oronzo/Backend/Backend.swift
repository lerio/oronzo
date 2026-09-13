import Foundation
import Supabase

/// Backend configuration.
///
/// The values are substituted into Info.plist at build time from `ios/Local.xcconfig`,
/// which is gitignored — this repository is public, so the project ref and key stay local.
/// A fresh clone therefore has empty placeholders, which is why `isConfigured` exists:
/// the app says what to do rather than crashing inside a network call.
enum Backend {

    static let projectRef = infoValue("SupabaseProjectRef")
    static let publishableKey = infoValue("SupabasePublishableKey")

    static var isConfigured: Bool {
        !projectRef.isEmpty && !publishableKey.isEmpty
    }

    /// Lazily built, so an unconfigured build never reaches the precondition below.
    ///
    /// Only the publishable key is ever used here. It is safe in a shipped client — it
    /// carries no privileges of its own, and row-level security protects every table. The
    /// secret key must never be in the app.
    static let client: SupabaseClient = {
        guard let url = URL(string: "https://\(projectRef).supabase.co") else {
            preconditionFailure("'\(projectRef)' is not a usable Supabase project ref")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }()

    private static func infoValue(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
