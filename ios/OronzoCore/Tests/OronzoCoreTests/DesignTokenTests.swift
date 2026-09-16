import XCTest
@testable import OronzoCore

/// S2 — the shared visual vocabulary.
///
/// These tests are **metric 3 mechanised**: they turn "one design, not seven screens" from a
/// discipline someone has to remember into a property of the code. The budgets asserted here
/// (8 colour roles, 4 type roles, 4 spacing steps) come from `docs/ui-design/0001-ui-polish.md` §2,
/// where a fifth spacing step is described as a design failure rather than a need.
///
/// What these tests deliberately *cannot* check: that no view hardcodes a size of its own. That
/// lives in the app targets, which have no test target. See the note in the file that defines
/// the vocabulary.
final class DesignTokenTests: XCTestCase {

    // MARK: - Colour roles

    func testThereAreExactlyEightColourRoles() {
        XCTAssertEqual(
            ColorRole.allCases.count, 8,
            "8 is the budget from UI design §2. Adding a role is a design decision, not a convenience."
        )
    }

    func testEveryColourRoleHasAValidValueInBothAppearances() {
        for role in ColorRole.allCases {
            for appearance in Appearance.allCases {
                let colour = Palette.color(role, appearance)
                for (name, component) in [
                    ("red", colour.red), ("green", colour.green),
                    ("blue", colour.blue), ("alpha", colour.alpha),
                ] {
                    XCTAssertTrue(
                        (0...1).contains(component),
                        "\(role.rawValue)/\(appearance.rawValue): \(name) is \(component), outside 0...1"
                    )
                }
            }
        }
    }

    /// The rule from UI design §2: the two state colours must differ in **perceived luminance**,
    /// not merely in hue.
    ///
    /// This is what lets work and rest stay distinguishable on a dimmed always-on display *and*
    /// to a colour-blind user, simultaneously — two constraints that a hue-only difference fails.
    /// Greyscale is the proxy for both, because it collapses hue and leaves luminance.
    func testTheTwoStateColoursDifferInLuminanceInBothAppearances() {
        for appearance in Appearance.allCases {
            let work = Palette.color(.accent, appearance).relativeLuminance
            let rest = Palette.color(.rest, appearance).relativeLuminance

            XCTAssertGreaterThan(
                abs(work - rest), 0.10,
                """
                \(appearance.rawValue): accent and rest are too close in luminance \
                (\(work) vs \(rest)). They would read as the same grey when dimmed or to a \
                colour-blind user, which is exactly what the state word must not depend on.
                """
            )
        }
    }

    func testTheTextColourOutcontrastsTheBackgroundItSitsOn() {
        // The no-mid-tones rule, mechanised for the one pairing that matters everywhere:
        // essential information uses `text`, so `text` on `background` is the floor.
        for appearance in Appearance.allCases {
            let text = Palette.color(.text, appearance).relativeLuminance
            let background = Palette.color(.background, appearance).relativeLuminance
            let ratio = (max(text, background) + 0.05) / (min(text, background) + 0.05)

            XCTAssertGreaterThanOrEqual(
                ratio, 7.0,
                "\(appearance.rawValue): text on background is only \(ratio):1. The design "
                + "requires the highest contrast available, because this is read in a gym."
            )
        }
    }

    // MARK: - Type roles

    func testThereAreExactlyFourTypeRoles() {
        XCTAssertEqual(TypeRole.allCases.count, 4, "4 is the budget from UI design §2.")
    }

    /// The resolution to the one real accessibility conflict named in `docs/ui-design/0001-ui-polish.md` §3:
    /// **text scales, the clock does not.**
    ///
    /// The primary element is a fixed-purpose instrument, not prose, which is what makes capping
    /// it defensible where capping body text would not be. This test exists so that property
    /// cannot be lost by accident.
    func testOnlyThePrimaryTypeRoleIsCappedAgainstDynamicType() {
        XCTAssertFalse(
            TypeRole.primary.scalesWithDynamicType,
            "The clock/reps figure must not scale unboundedly — it would break the density that "
            + "makes direction A work on a 41mm screen."
        )

        for role in TypeRole.allCases where role != .primary {
            XCTAssertTrue(role.scalesWithDynamicType, "\(role.rawValue) must scale with Dynamic Type.")
        }
    }

    func testEveryTypeRoleHasASizeOnBothPlatforms() {
        for role in TypeRole.allCases {
            for platform in DisplayPlatform.allCases {
                XCTAssertGreaterThan(
                    TypeScale.size(role, on: platform), 0,
                    "\(role.rawValue) has no size on \(platform.rawValue)"
                )
            }
        }
    }

    /// The hierarchy is the point of the scale, so it is asserted rather than assumed.
    func testTypeRolesDescendInSizeOnBothPlatforms() {
        for platform in DisplayPlatform.allCases {
            let sizes = TypeRole.allCases.map { TypeScale.size($0, on: platform) }
            XCTAssertEqual(
                sizes, sizes.sorted(by: >),
                "\(platform.rawValue): sizes must descend primary > title > label > caption; got \(sizes)"
            )
            XCTAssertEqual(Set(sizes).count, sizes.count, "\(platform.rawValue): two roles share a size, so the hierarchy is ambiguous.")
        }
    }

    /// A watch and a phone need different absolute sizes for the same role — that is why the
    /// roles are shared and the values are per-platform. This asserts they are genuinely tuned
    /// rather than copied across.
    func testTheWatchScaleIsSmallerThanThePhoneScale() {
        for role in TypeRole.allCases {
            XCTAssertLessThan(
                TypeScale.size(role, on: .watch), TypeScale.size(role, on: .phone),
                "\(role.rawValue) is not smaller on the watch"
            )
        }
    }

    // MARK: - Spacing

    func testThereAreExactlyFourSpacingSteps() {
        XCTAssertEqual(SpacingStep.allCases.count, 4, "4 is the budget from UI design §2.")
    }

    func testSpacingStepsAscend() {
        let points = SpacingStep.allCases.map(Spacing.points)
        XCTAssertEqual(
            points, points.sorted(),
            "Spacing steps must ascend tight < snug < roomy < edge; got \(points)"
        )
        XCTAssertEqual(Set(points).count, points.count, "Two spacing steps share a value.")
    }
}

// MARK: - Test helpers

private extension TokenColor {
    /// WCAG relative luminance: linearise each sRGB channel, then weight by human sensitivity.
    ///
    /// Deliberately test-only. Nothing in the apps needs it yet, and promoting it to the
    /// vocabulary would be adding API for a hypothetical consumer.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
