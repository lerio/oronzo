import Foundation

/// Compiled into **both** the iOS app and the Watch app.
///
/// This file exists so that a mistake in the shared-source wiring shows up as a build
/// failure rather than as a mysteriously empty Watch screen. Later iterations add the
/// interval model and the flattening engine here.
enum AppInfo {
    static let name = "Oronzo"
    static let version = "0.1.0"

    static var buildLabel: String { "\(name) \(version)" }
}
