import OronzoCore
import SwiftUI

/// Maps the shared vocabulary onto SwiftUI.
///
/// Deliberately a near-copy of `ios/OronzoWatch/DesignTokens+SwiftUI.swift`. `OronzoCore` holds
/// the values but cannot hold this, because `Package.swift` is explicit that the package has no
/// SwiftUI dependency — that is what keeps `swift test` running on macOS in a second.
///
/// Duplicating ~40 lines of mechanical, generic conversion is the cheaper trade: the *values*
/// are never restated, a new colour role needs no change here at all, and the alternative — a
/// third target importing SwiftUI — would contradict the package's stated purpose. If this
/// grows beyond trivial conversion, it should become that target and the manifest comment
/// should be updated with it.
extension Color {
    init(_ token: TokenColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}

extension ColorRole {

    func color(_ scheme: ColorScheme) -> Color {
        Color(Palette.color(self, scheme == .dark ? .dark : .light))
    }

    /// The colour that reinforces a given state. Reinforcement only, never the carrier: the
    /// state **word** says what is happening and is always drawn in `text`, so it survives a
    /// bright room. See `DesignTokenTests` for the luminance rule this depends on.
    static func reinforcement(for stateWord: SessionScreen.StateWord) -> ColorRole {
        switch stateWord {
        case .work, .paused: .accent
        case .rest: .rest
        case .done: .good
        }
    }
}

extension SpacingStep {
    var points: CGFloat { CGFloat(Spacing.points(self)) }
}
