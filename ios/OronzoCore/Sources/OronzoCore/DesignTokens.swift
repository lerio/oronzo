import Foundation

// MARK: - The shared visual vocabulary
//
// Defined once, here, and consumed by the iPhone app, the Watch app and the Lock Screen
// extension. This is the same argument `project.yml` makes for the flattener: putting shared
// logic in one package makes drift between the surfaces *impossible* rather than merely
// discouraged. A token file per target would reintroduce exactly the mirrored-model problem
// `docs/integration-contracts.md` exists to warn about — for values instead of fields.
//
// Three rules govern everything in this file, all from `docs/ui-design/0001-ui-polish.md` §2:
//
//   1. The counts are budgets. 8 colour roles, 4 type roles, 4 spacing steps. A fifth spacing
//      step is a design failure, not a need.
//   2. Subordination is carried by size and weight, never by dimming, for anything the user
//      needs. `muted` is reserved for chrome that can be lost. This is what makes the
//      sunlight requirement structural rather than a per-screen judgement — a mid-tone is
//      what dies on a bright screen, so nothing essential is allowed to be one.
//   3. The two state colours (`accent`, `rest`) must differ in *perceived luminance*, not
//      merely in hue, so work and rest stay distinguishable on a dimmed always-on display and
//      to a colour-blind user at the same time.
//
// Everything here is a **plain value**, never a platform colour type. That is what keeps
// `OronzoCore` a plain SwiftPM package that `swift test` can exercise on macOS — the only
// check in this project that needs no device. Each app maps these values into its own colour
// type at the boundary.

// MARK: - Colour

/// A colour as plain components.
///
/// Deliberately not `UIColor`, `Color` or `NSColor`: `OronzoCore` is tested on macOS precisely
/// because it holds no platform frameworks, and S1 established that even a `canImport` guard is
/// not enough for frameworks whose *symbols* are unavailable there.
public struct TokenColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#rrggbb`, so the definitions below read as the colours a designer would write.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The eight colour roles. The budget, not a starting point.
public enum ColorRole: String, CaseIterable, Sendable {
    case background
    case surface
    case text
    /// Chrome only. **Never** for anything the user has to read — see rule 2 above.
    case muted
    /// The working state.
    case accent
    /// The resting state. Must differ from `accent` in luminance; asserted in the tests.
    case rest
    case danger
    case good
}

public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
}

public enum Palette {

    /// The seven colours that already existed are adopted **verbatim** from
    /// `web/src/styles.css`, so the phone, the watch and the plan builder share one palette
    /// rather than three. Only `rest` is new — the web had no state colours because it does
    /// not run a session.
    ///
    /// Values are provisional: the design spec leaves exact colours to implementation, and
    /// `docs/spec/0001-ui-polish.md` says they are verified by looking at the UI. Expect S3 to
    /// adjust the hues — but not the roles, and not the luminance rule.
    public static func color(_ role: ColorRole, _ appearance: Appearance) -> TokenColor {
        switch (role, appearance) {
        case (.background, .light): TokenColor(hex: 0xF6F7F9)
        case (.surface, .light): TokenColor(hex: 0xFFFFFF)
        case (.text, .light): TokenColor(hex: 0x1A1D21)
        case (.muted, .light): TokenColor(hex: 0x6B7280)
        case (.accent, .light): TokenColor(hex: 0x2F6DF6)
        // Pale and low-contrast on purpose: on a light background, "quiet" means closer to the
        // background, which is how rest reads as calm rather than as a second alarm. It also
        // puts it far from `accent` in luminance, which is the rule that has to hold.
        case (.rest, .light): TokenColor(hex: 0x93C4BD)
        case (.danger, .light): TokenColor(hex: 0xC0392B)
        case (.good, .light): TokenColor(hex: 0x1F8A4C)

        case (.background, .dark): TokenColor(hex: 0x16181C)
        case (.surface, .dark): TokenColor(hex: 0x1E2126)
        case (.text, .dark): TokenColor(hex: 0xE9EAEC)
        case (.muted, .dark): TokenColor(hex: 0x969BA5)
        case (.accent, .dark): TokenColor(hex: 0x5B8DFF)
        // Deep and desaturated: dimmer than `accent`, so it recedes rather than competes.
        case (.rest, .dark): TokenColor(hex: 0x35776F)
        case (.danger, .dark): TokenColor(hex: 0xFF7B6B)
        case (.good, .dark): TokenColor(hex: 0x56C98A)
        }
    }
}

// MARK: - Type

/// The four type roles. The budget, not a starting point.
public enum TypeRole: String, CaseIterable, Sendable {
    /// The clock, or the rep count. The single biggest thing on a surface.
    case primary
    /// The exercise name.
    case title
    /// The state word, and the context line ("Set 2 of 4").
    case label
    /// The next-up line, and chrome.
    case caption

    /// Whether this role grows with the user's Dynamic Type setting.
    ///
    /// The one real accessibility conflict named in `docs/ui-design/0001-ui-polish.md` §3:
    /// **text scales, the clock does not.** Unbounded scaling would break the density that
    /// makes direction A work on a 41mm screen, and capping a fixed-purpose instrument is
    /// defensible where capping body text would not be. Every other role scales.
    public var scalesWithDynamicType: Bool { self != .primary }
}

/// Which screen the size is for.
///
/// The roles are shared; the *values* are not. A 49mm watch and a 6.3" phone cannot use the same
/// point size for the same role, so sharing the numbers would produce a scale that is correct on
/// neither. What must not fork is the vocabulary — which roles exist and what each one means.
public enum DisplayPlatform: String, CaseIterable, Sendable {
    case phone
    case watch
}

public enum TypeScale {

    /// Sizes in points. Provisional until S3 and S5 look at them on a real screen — the design
    /// spec deliberately leaves final values to implementation.
    public static func size(_ role: TypeRole, on platform: DisplayPlatform) -> Double {
        switch (role, platform) {
        // The distance requirement lives here: PRD metric 5 asks that the phone be readable
        // from 1–2 metres on a surface, so `primary` is sized by that, not by available space.
        case (.primary, .phone): 96
        case (.title, .phone): 34
        case (.label, .phone): 20
        case (.caption, .phone): 15

        case (.primary, .watch): 48
        case (.title, .watch): 20
        case (.label, .watch): 15
        case (.caption, .watch): 12
        }
    }
}

// MARK: - Spacing

/// The four spacing steps. The budget, not a starting point.
public enum SpacingStep: String, CaseIterable, Sendable {
    /// Within a line group.
    case tight
    /// Between related lines.
    case snug
    /// Between groups.
    case roomy
    /// The screen margin.
    case edge
}

public enum Spacing {

    /// Spacing is shared across platforms rather than per-platform like type: points are points
    /// on both screens, and a shared scale is one fewer thing to reason about.
    public static func points(_ step: SpacingStep) -> Double {
        switch step {
        case .tight: 4
        case .snug: 8
        case .roomy: 16
        case .edge: 20
        }
    }
}
