import XCTest
@testable import OronzoCore

/// S7 — the Lock Screen Live Activity.
///
/// What is testable here is the *payload*: the small value the extension is handed, and which
/// the app must keep under ActivityKit's 4 KB ceiling. The rendering itself needs a Lock Screen.
final class SessionActivityTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func screen(
        intervals: [Interval], index: Int, end: Date?, paused: Bool = false
    ) -> SessionScreen {
        SessionPresentation.screen(
            intervals: intervals, index: index, end: end,
            isPaused: paused, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )!
    }

    private func twoStepPlan() -> [Interval] {
        PlanFlattener.flatten(Plan(name: "P", blocks: [
            PlanBlock(name: "Main", steps: [
                PlanStep(label: "Row", mode: .time, duration: 60, restAfter: 30),
                PlanStep(label: "Bench Press", mode: .reps, reps: 8),
            ]),
        ]))
    }

    // MARK: - The label lives in one place

    /// `NEXT · X` was written out separately in the watch and the phone runner. A third copy for
    /// the Lock Screen is exactly the drift the shared vocabulary exists to stop, so it moved
    /// into the model and all three read it from here.
    func testTheNextLabelIsWordedOnce() {
        XCTAssertEqual(
            SessionScreen.Next.exercise("Lat Pulldown", weight: nil).label,
            "NEXT · Lat Pulldown"
        )
        XCTAssertEqual(
            SessionScreen.Next.exercise("Lat Pulldown", weight: "20 kg").label,
            "NEXT · Lat Pulldown · 20 kg"
        )
        XCTAssertEqual(SessionScreen.Next.last.label, "LAST")
    }

    // MARK: - What the Lock Screen needs, and nothing more

    func testATimedIntervalCarriesAnAbsoluteEndForTheSystemTimer() {
        let end = t0.addingTimeInterval(42)
        let state = SessionActivityContent(
            screen: screen(intervals: twoStepPlan(), index: 0, end: end),
            intervalEnd: end,
            remainingWhenPaused: nil
        )

        XCTAssertEqual(state.stateWord, "WORK")
        XCTAssertEqual(state.name, "Row")
        XCTAssertEqual(state.context, "Main")
        XCTAssertEqual(state.next, "NEXT · Break")
        // Absolute rather than a countdown, so the system renders the timer and the app does not
        // have to send anything per second — the same principle as the watch.
        XCTAssertEqual(state.intervalEnd, end)
    }

    /// The Lock Screen reads the same next-up line as the two runners, the load included — it is
    /// `Next.label` verbatim, so a load dropped here would be a load the three surfaces word
    /// differently.
    ///
    /// This payload has no load field of its own, so the next-up line is the only place a weight
    /// can appear on the Lock Screen at all. It is worth most on the rest before an exercise,
    /// which is the interval pinned here.
    func testTheLockScreenCarriesTheUpcomingLoadInItsNextLine() {
        let intervals = PlanFlattener.flatten(Plan(name: "P", blocks: [
            PlanBlock(name: "Main", steps: [
                PlanStep(label: "Row", mode: .time, duration: 60, restAfter: 30),
                PlanStep(label: "Bench Press", mode: .reps, reps: 8, targetWeightKg: 20),
            ]),
        ]))

        let state = SessionActivityContent(
            screen: screen(intervals: intervals, index: 1, end: t0.addingTimeInterval(30)),
            intervalEnd: t0.addingTimeInterval(30),
            remainingWhenPaused: nil
        )

        XCTAssertEqual(state.next, "NEXT · Bench Press · 20 kg")
    }

    /// A rep interval has no length, so it carries its target and no end date. Otherwise the
    /// system would render a countdown to nowhere.
    func testARepIntervalCarriesItsTargetAndNoEnd() {
        let state = SessionActivityContent(
            screen: screen(intervals: twoStepPlan(), index: 2, end: nil),
            intervalEnd: nil,
            remainingWhenPaused: nil
        )

        XCTAssertEqual(state.reps, 8)
        XCTAssertNil(state.intervalEnd, "a rep interval must not imply a duration")
    }

    /// Paused needs the frozen remainder as text, because the system's timer cannot be paused.
    func testPausedCarriesTheFrozenRemainder() {
        let state = SessionActivityContent(
            screen: screen(intervals: twoStepPlan(), index: 0, end: t0.addingTimeInterval(20), paused: true),
            intervalEnd: nil,
            remainingWhenPaused: 20
        )

        XCTAssertEqual(state.stateWord, "PAUSED")
        XCTAssertEqual(state.remainingWhenPaused, 20)
        XCTAssertNil(state.intervalEnd)
    }

    // MARK: - The 4 KB ceiling

    /// `ActivityAttributes` has a hard limit and exceeding it throws `dataTooLarge` at runtime,
    /// on a device, at the moment a workout starts. This asserts the payload against a
    /// deliberately worst-case plan rather than a friendly one: long names, a long plan name, and
    /// the deepest nesting the model allows.
    ///
    /// It also pins the design decision that the Lock Screen gets **current plus next only** —
    /// the interval list belongs to the watch, whose transport is a single slot with no size
    /// ceiling, and must never be sent here.
    func testThePayloadStaysWellUnderTheActivityKitLimit() throws {
        let longName = String(repeating: "Incline Dumbbell Bench Press ", count: 6)
        let steps = (0..<40).map { i in
            PlanStep(label: "\(longName)\(i)", mode: .time, duration: 60, restAfter: 30)
        }
        let intervals = PlanFlattener.flatten(Plan(name: longName, blocks: [PlanBlock(steps: steps)]))
        XCTAssertGreaterThan(intervals.count, 40, "the worst case should be a big plan")

        let state = SessionActivityContent(
            screen: screen(intervals: intervals, index: 12, end: t0.addingTimeInterval(3600)),
            intervalEnd: t0.addingTimeInterval(3600),
            remainingWhenPaused: nil
        )

        let encoded = try JSONEncoder().encode(state)

        XCTAssertLessThan(
            encoded.count, 4096,
            "the payload is \(encoded.count) bytes; ActivityKit refuses anything over 4 KB"
        )
        // And comfortably under, because the ceiling is a hard throw rather than a truncation.
        XCTAssertLessThan(encoded.count, 2048, "leave headroom — this is a hard runtime failure")
    }
}
