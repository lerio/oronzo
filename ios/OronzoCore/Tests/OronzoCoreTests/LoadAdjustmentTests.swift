import XCTest
@testable import OronzoCore

/// The runner's load arrows: what one tap does, and where it stops.
///
/// All of it is arithmetic and a wrap, which is exactly why it is here rather than in the view —
/// the rules that are easy to get subtly wrong (where the weight floor is, what happens past
/// `hard`) are then proved on macOS instead of being discovered at the rack.
final class LoadAdjustmentTests: XCTestCase {

    // MARK: - Weight

    /// The step the request named, in both directions, from the loads plans actually carry.
    func testWeightStepsByTwoAndAHalfKilos() {
        XCTAssertEqual(LoadDial.weight(20, up: true), 22.5)
        XCTAssertEqual(LoadDial.weight(20, up: false), 17.5)
        XCTAssertEqual(LoadDial.weight(22.5, up: true), 25, "the grid holds after a first tap")
        XCTAssertEqual(LoadDial.weight(0, up: true), 2.5)
    }

    /// `plan_steps.target_weight_kg` is `check (target_weight_kg >= 0)`, so an arrow that could
    /// offer a negative weight would be offering a save the database refuses. It stops at zero.
    func testWeightFloorsAtZero() {
        XCTAssertEqual(LoadDial.weight(2.5, up: false), 0)
        XCTAssertEqual(LoadDial.weight(0, up: false), 0, "and stays there on a repeat tap")
        XCTAssertEqual(LoadDial.weight(1, up: false), 0, "an off-grid load clamps rather than going negative")
    }

    /// The column is `numeric(6, 2)`, so a value that is not on the half-kilo grid has to stay a
    /// two-decimal number across repeated taps — otherwise the load displayed drifts away from the
    /// load written, which is the kind of difference nobody notices until it is in the history.
    func testWeightStaysOnTheColumnsScaleAcrossRepeatedTaps() {
        var value = 21.33
        for _ in 0..<8 { value = LoadDial.weight(value, up: true) }

        XCTAssertEqual(value, 41.33)
        XCTAssertEqual(String(format: "%.2f", value), "41.33", "no drift below the stored precision")
    }

    /// A load that arrives as a whole number loses its `.0` when it is drawn, and stepping off it
    /// keeps that true — the display rule is `MeasurementFormat`'s and this must not fight it.
    func testWeightOffAWholeNumberDrawsWithoutADecimal() {
        XCTAssertEqual(MeasurementFormat.weight(LoadDial.weight(20, up: true)), "22.5 kg")
        XCTAssertEqual(MeasurementFormat.weight(LoadDial.weight(22.5, up: true)), "25 kg")
    }

    // MARK: - Effort

    /// **Wrapping, both ways.** Past `hard` is `low`, below `low` is `hard` — the arrows are each
    /// other's inverse and the three words are one closed loop.
    func testIntensityWrapsInBothDirections() {
        XCTAssertEqual(LoadDial.intensity(.low, up: true), .medium)
        XCTAssertEqual(LoadDial.intensity(.medium, up: true), .hard)
        XCTAssertEqual(LoadDial.intensity(.hard, up: true), .low, "past the top is the bottom")

        XCTAssertEqual(LoadDial.intensity(.hard, up: false), .medium)
        XCTAssertEqual(LoadDial.intensity(.medium, up: false), .low)
        XCTAssertEqual(LoadDial.intensity(.low, up: false), .hard, "below the bottom is the top")
    }

    /// The wrap is only meaningful if the order it wraps around is effort order. Nothing else in
    /// the codebase states that — the database's check constraint tests membership, not rank — so
    /// it is pinned here, next to the function whose meaning depends on it.
    func testTheCycleOrderIsEffortAscending() {
        XCTAssertEqual(Intensity.allCases, [.low, .medium, .hard])
    }

    /// Every one of the three words is reachable from every other by going one way, which is what
    /// "looping through different intensities" has to mean if a user is to get anywhere.
    func testEveryIntensityReachesEveryOtherOneWay() {
        for start in Intensity.allCases {
            var seen: [Intensity] = []
            var value = start
            for _ in Intensity.allCases { value = LoadDial.intensity(value, up: true); seen.append(value) }
            XCTAssertEqual(Set(seen), Set(Intensity.allCases), "the whole loop, from \(start)")
            XCTAssertEqual(value, start, "and it comes back round to where it started")
        }
    }

    // MARK: - An edit, and the intervals it applies to

    private func interval(index: Int, step: UUID?, weight: Double?, intensity: Intensity? = nil) -> Interval {
        Interval(
            index: index, kind: .exercise, name: "Press", mode: .reps, duration: nil,
            reps: 8, targetWeightKg: weight, setIndex: 1, setCount: 4,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil,
            stepID: step, intensity: intensity
        )
    }

    /// An edit is seeded from the interval the user is on, so the arrows start where the screen is.
    func testAnEditIsSeededFromTheIntervalItStartedOn() {
        let step = UUID()
        let edit = StepLoadEdit(interval: interval(index: 2, step: step, weight: 22.5, intensity: .hard))

        XCTAssertEqual(edit?.stepID, step)
        XCTAssertEqual(edit?.weightKg, 22.5)
        XCTAssertEqual(edit?.intensity, .hard)
    }

    /// An interval with no row behind it cannot be edited, and that is the guard rather than an
    /// error: a plan off an older cache has no step ids, and what that costs is the arrows.
    func testAnIntervalWithNoStepCannotBeEdited() {
        XCTAssertNil(StepLoadEdit(interval: interval(index: 0, step: nil, weight: 20)))
    }

    /// Applying an edit changes the load and **nothing else** — not the name, not the rep target,
    /// not the position. The interval is rebuilt rather than mutated, so the risk is a field that
    /// was dropped on the way through.
    func testApplyingAnEditChangesOnlyTheLoad() {
        let step = UUID()
        let before = interval(index: 3, step: step, weight: 20, intensity: .low)
        var edit = StepLoadEdit(interval: before)!
        edit.weightKg = LoadDial.weight(20, up: true)
        edit.intensity = LoadDial.intensity(.low, up: true)

        let after = edit.applying(to: before)

        XCTAssertEqual(after.targetWeightKg, 22.5)
        XCTAssertEqual(after.intensity, .medium)
        XCTAssertEqual(after.index, before.index)
        XCTAssertEqual(after.name, before.name)
        XCTAssertEqual(after.reps, before.reps)
        XCTAssertEqual(after.setCount, before.setCount)
        XCTAssertEqual(after.stepID, step, "the link back to the row survives the edit")
    }

    /// Which intervals the edit is about: the ones from its own step, and no others.
    func testAnEditAppliesToItsOwnStepAndNoOther() {
        let step = UUID()
        let edit = StepLoadEdit(interval: interval(index: 0, step: step, weight: 20))!

        XCTAssertTrue(edit.applies(to: interval(index: 0, step: step, weight: 20)))
        XCTAssertTrue(edit.applies(to: interval(index: 5, step: step, weight: 20)), "another set")
        XCTAssertFalse(edit.applies(to: interval(index: 1, step: UUID(), weight: 50)))
        XCTAssertFalse(edit.applies(to: interval(index: 2, step: nil, weight: nil)), "a rest")
    }
}
