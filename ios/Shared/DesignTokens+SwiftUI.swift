import OronzoCore
import SwiftUI

/// Maps the shared vocabulary onto SwiftUI.
///
/// **One file, compiled into both surfaces** — the iPhone app and the Watch app. It lives in
/// `Shared/` rather than inside either of them precisely so that happens: `ios/project.yml` lists
/// this folder in each target's sources.
///
/// It cannot live in `OronzoCore`, because `Package.swift` is explicit that the package has no
/// SwiftUI dependency — that is what keeps `swift test` running the whole engine on macOS in a
/// second. So the values live there and the conversion lives here, which is the same split the
/// rest of the vocabulary uses.
///
/// The conversion is mechanical and generic over the roles: adding a ninth colour or a fifth
/// spacing step needs no change here, and the *values* are never restated. It was written into a
/// shared folder when a third surface made duplicating it intolerable; that surface is gone and the
/// folder stays, because two copies were already one too many.
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
    /// Reinforcement only, never the carrier: the state **word** says what is happening and is
    /// always drawn in `text`, so it survives a bright gym. Colour here is the redundant second
    /// signal, which is why `accent` and `rest` are required to differ in *luminance* — see
    /// `DesignTokenTests`.
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
