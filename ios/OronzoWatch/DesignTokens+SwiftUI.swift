import OronzoCore
import SwiftUI

/// Maps the shared vocabulary onto SwiftUI.
///
/// This is the one place the two meet. `OronzoCore` holds plain values because the package
/// deliberately has **no SwiftUI dependency** — that is what lets `swift test` run the whole
/// engine on macOS in a second — so each app turns those values into its own types here.
///
/// The conversion is mechanical and generic over the roles: adding a ninth colour or a fifth
/// spacing step needs no change in this file, and the *values* are never restated. That is why
/// it is duplicated per app rather than extracted into a third shared target — sharing the
/// values is what matters, and they are already shared.
extension Color {
    init(_ token: TokenColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}

extension ColorRole {

    /// Resolves a role for the current appearance.
    func color(_ scheme: ColorScheme) -> Color {
        Color(Palette.color(self, scheme == .dark ? .dark : .light))
    }

    /// The colour that reinforces a given state.
    ///
    /// Reinforcement only, never the carrier: the state **word** is what says "working" or
    /// "resting", and it is always drawn in `text` so it survives a bright gym. Colour here is
    /// the redundant second signal, which is why `accent` and `rest` are required to differ in
    /// luminance — see `DesignTokenTests`.
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
