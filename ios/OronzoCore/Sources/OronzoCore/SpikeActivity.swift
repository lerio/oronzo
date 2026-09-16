import Foundation

// Guarded on `os(iOS)`, NOT on `canImport(ActivityKit)`.
//
// ActivityKit *can* be imported on macOS — the module exists — but `ActivityAttributes` is
// marked unavailable there, so `canImport` alone compiles the guard and fails at the symbol.
// `OronzoCore` is a plain SwiftPM package that must keep building and testing on macOS
// (`swift test` is the only check in this repo that needs no device), so the type has to be
// absent there rather than merely unavailable. The Watch target is excluded too — it has no
// use for it and no ActivityKit.
//
// Discovered by the S1 spike; S7 depends on the same guard.
#if os(iOS)
import ActivityKit

/// **Spike only — S1.** Answers one question: does a Live Activity provision, start, and appear
/// on the Lock Screen on a free personal Apple team?
///
/// It carries no session data and renders fixed text. Plan slice S7 replaces this wholesale with
/// the real thing. It lives in `OronzoCore` rather than in either target because *both* need it —
/// the app starts the activity, the extension renders it — which is the same reason the flattener
/// lives here. See `docs/plan/0001-ui-polish.md`.
///
/// Deliberately not named after the session it will eventually describe, so nothing downstream
/// mistakes a throwaway for a contract.
public struct SpikeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var message: String

        public init(message: String) {
            self.message = message
        }
    }

    public init() {}
}
#endif
