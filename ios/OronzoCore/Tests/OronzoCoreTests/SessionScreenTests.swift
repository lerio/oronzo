import XCTest
@testable import OronzoCore

/// S3 — what the Watch screen shows.
///
/// The *decisions* live in `OronzoCore` as a pure function so they can be proved on macOS,
/// leaving the view to do nothing but render. That is the same split the engine already uses:
/// extract the decision, inject the effect. It means the rules most likely to be got wrong —
/// what rest promotes, when `LAST` appears, that a rep interval never shows a time — are
/// tested rather than eyeballed on a wrist.
///
/// What these tests cannot cover: whether it is *readable*. Metrics 1 and 4 are judged by a
/// person looking at a watch, and no test substitutes for that.
final class SessionScreenTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// One timed exercise, one rest, one rep exercise — the three primaries.
    private func mixedIntervals() -> [Interval] {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(name: "Main", steps: [
                PlanStep(label: "Row", mode: .time, duration: 60, restAfter: 30),
                PlanStep(label: "Bench Press", mode: .reps, reps: 8),
            ]),
        ])
        return PlanFlattener.flatten(plan)
    }

    // MARK: - The state word

    func testTimedWorkShowsTheWorkStateWordAndAClock() {
        let intervals = mixedIntervals()
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 0,
            end: t0.addingTimeInterval(42), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .work)
        XCTAssertEqual(screen?.name, "Row")
        XCTAssertEqual(screen?.primary, .clock(42))
        // `Interval.contextLabel` falls back to the block name when there is no set or round
        // progress to report, and that is deliberately reused rather than reinvented here.
        XCTAssertEqual(screen?.context, "Main")
    }

    func testRestShowsTheRestStateWord() {
        let intervals = mixedIntervals()   // index 1 is the synthetic rest
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .rest)
    }

    /// The state word is the colour-independent signal that metrics 1 and 5 both depend on, so
    /// it is never omitted — including while paused.
    ///
    /// Note the shape of a real paused state: `WatchLink.position` returns
    /// `now + remainingWhenPaused`, so an end date *is* present and the clock simply reads the
    /// frozen remainder. The design's "frozen remaining" is that, and nothing more.
    func testPausedOverridesTheUnderlyingKindAndFreezesTheClock() {
        for index in [0, 1] {
            let screen = SessionPresentation.screen(
                intervals: mixedIntervals(), index: index,
                end: t0.addingTimeInterval(20), isPaused: true, isFinished: false,
                planName: "P", startedAt: t0, now: t0
            )
            XCTAssertEqual(screen?.stateWord, .paused, "index \(index)")
            XCTAssertEqual(screen?.primary, .clock(20), "index \(index)")
        }
    }

    func testFinishedShowsDoneWithTotalElapsedAndThePlanName() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: true,
            planName: "Monday — Upper Body A", startedAt: t0,
            now: t0.addingTimeInterval(2_820)
        )

        XCTAssertEqual(screen?.stateWord, .done)
        XCTAssertEqual(screen?.name, "Monday — Upper Body A")
        XCTAssertEqual(screen?.primary, .elapsed(2_820))
        XCTAssertNil(screen?.next)
    }

    func testNothingIsShownWhenThereIsNoSession() {
        XCTAssertNil(SessionPresentation.screen(
            intervals: [], index: 0,
            end: nil, isPaused: false, isFinished: false,
            planName: nil, startedAt: nil, now: t0
        ))
    }

    // MARK: - The rest promotion (the design's one non-obvious decision)

    /// During rest the name slot shows **the next exercise**, because "Break" tells you what you
    /// already know and what you actually want mid-rest is what you are resting *toward*.
    func testRestPromotesTheNextExerciseIntoTheNameSlot() {
        let intervals = mixedIntervals()
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 1,          // the rest after "Row"
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.name, "Bench Press", "rest must promote what is next")
    }

    /// And because the name slot now carries it, the next line is suppressed rather than
    /// repeating the same word twice.
    func testRestSuppressesTheNextLineBecauseTheNameSlotCarriesIt() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertNil(screen?.next)
    }

    // MARK: - The next line

    func testTheNextLineNamesTheFollowingExercise() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 0,
            end: t0.addingTimeInterval(10), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.next, .exercise("Break"))
    }

    /// `LAST` answers "what's next" when the answer is "nothing". Knowing the final interval is
    /// the final one is the most motivating fact the watch can carry, so it gets the slot
    /// rather than a blank.
    func testTheFinalIntervalShowsLastInsteadOfANextName() {
        let intervals = mixedIntervals()
        let screen = SessionPresentation.screen(
            intervals: intervals, index: intervals.count - 1,
            end: nil, isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.next, .last)
    }

    /// The edge case the promotion rule creates: resting on the very last interval means there
    /// is nothing to promote, so the name slot keeps the current name — and `LAST` must still
    /// appear, or the promotion would have silently swallowed the one fact worth having.
    func testTheFinalRestStillShowsLastBecauseThereIsNothingToPromote() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [PlanStep(label: "Row", mode: .time, duration: 60, restAfter: 30)]),
        ])
        let intervals = PlanFlattener.flatten(plan)   // [Row, Break]
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .rest)
        XCTAssertEqual(screen?.name, "Break", "nothing to promote, so the current name stays")
        XCTAssertEqual(screen?.next, .last, "and the last interval must still be announced")
    }

    // MARK: - Rep intervals never imply a duration

    func testARepIntervalShowsRepsAndNeverAClock() {
        let intervals = mixedIntervals()
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 2,          // the rep step
            end: nil, isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .work)
        XCTAssertEqual(screen?.primary, .reps(8))

        if case .clock = screen?.primary {
            XCTFail("a rep interval has no length, so it must never show a clock")
        }
    }

    // MARK: - VoiceOver

    /// The design calls this out explicitly: a rep interval must **omit** the time rather than
    /// announce a stale or zero one, which would be a lie.
    func testTheAnnouncementOmitsTimeForARepInterval() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        let spoken = try? XCTUnwrap(screen?.accessibilityAnnouncement)
        XCTAssertEqual(spoken, "Working. Bench Press. 8 reps. Next: Last interval.")
        XCTAssertFalse(spoken?.contains("second") ?? true, "a rep interval must not speak a time")
    }

    func testTheAnnouncementSpeaksStateNameTimeContextAndNext() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Bench Press", sets: 4, mode: .time,
                         duration: 60, restAfter: 30),
            ]),
        ])
        let intervals = PlanFlattener.flatten(plan)   // set 1, rest, set 2, ...
        let screen = SessionPresentation.screen(
            intervals: intervals, index: 0,
            end: t0.addingTimeInterval(42), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(
            screen?.accessibilityAnnouncement,
            "Working. Bench Press. 42 seconds remaining. Set 1 of 4. Next: Break."
        )
    }
}

// MARK: - S4: the elapsed time must be frozen, not counting up

extension WatchScreenTests {

    /// Found by looking: the DONE screen read `0:24` for a six-second session, because the
    /// elapsed time was computed from the live clock and simply kept growing. The watch needs
    /// the moment the session actually ended, or "total elapsed" is not a total at all.
    func testTheElapsedTimeIsFrozenAtTheFinishNotTheCurrentTime() {
        let finishedAt = t0.addingTimeInterval(47 * 60)
        let screen = WatchPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: true,
            planName: "P", startedAt: t0, finishedAt: finishedAt,
            // Ten minutes after it ended — a phone in a pocket, a watch raised later.
            now: finishedAt.addingTimeInterval(600)
        )

        XCTAssertEqual(screen?.primary, .elapsed(47 * 60), "elapsed must not grow after the finish")
    }

    /// And when the finish time is missing — an older build's snapshot — it must degrade to the
    /// current time rather than showing nothing at all.
    func testTheElapsedFallsBackToNowWhenTheFinishTimeIsUnknown() {
        let screen = WatchPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: true,
            planName: "P", startedAt: t0, finishedAt: nil,
            now: t0.addingTimeInterval(120)
        )

        XCTAssertEqual(screen?.primary, .elapsed(120))
    }
}

// MARK: - S4: the wire format must stay readable by an older snapshot

extension WatchScreenTests {

    /// The reason `SessionState` decodes by hand. The application context persists across
    /// launches, so a snapshot encoded by a build that predates `finishedAt` can still be
    /// sitting there — and a synthesised decoder would reject it for the missing key, leaving
    /// the watch blank. This is the trap `docs/known-issues.md` records for `Interval`, and it
    /// was observed happening on a real device during this slice.
    func testASnapshotPredatingFinishedAtStillDecodes() throws {
        let older = """
        {"currentIndex":2,"isPaused":false,"isFinished":false,
         "intervalEnd":null,"remainingWhenPaused":null}
        """

        let state = try JSONDecoder().decode(SessionState.self, from: Data(older.utf8))

        XCTAssertEqual(state.currentIndex, 2)
        XCTAssertNil(state.finishedAt, "a missing key must default, not throw")
    }

    func testTheCurrentSessionStateShapeRoundTrips() throws {
        let original = SessionState(
            currentIndex: 3, isPaused: true, isFinished: true,
            intervalEnd: t0, remainingWhenPaused: 12, finishedAt: t0.addingTimeInterval(60)
        )

        let decoded = try JSONDecoder().decode(
            SessionState.self, from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
