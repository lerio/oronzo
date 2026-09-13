// swift-tools-version: 6.0
import PackageDescription

/// Pure logic shared by the iOS app and the Watch app: the plan model, the flattening
/// rule, and the session execution engine.
///
/// It is a package rather than a folder of shared sources for one specific reason: it has
/// no UIKit/SwiftUI/WatchKit dependency, so `swift test` runs the whole engine on macOS in
/// under a second — no simulator, no device, no signing. The trickiest logic in the project
/// (pause/resume arithmetic, auto-advance across a suspension) is therefore the easiest to
/// test.
let package = Package(
    name: "OronzoCore",
    platforms: [
        // Lower than the apps' iOS 26 / watchOS 26 targets — a package's minimum only has
        // to be at or below its consumers'. macOS is here so the tests run locally.
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v13),
    ],
    products: [
        .library(name: "OronzoCore", targets: ["OronzoCore"]),
    ],
    targets: [
        .target(name: "OronzoCore"),
        .testTarget(name: "OronzoCoreTests", dependencies: ["OronzoCore"]),
    ]
)
