import XCTest
@testable import OronzoCore

/// S3 — what the Watch screen shows.
///
/// The *decisions* live in `OronzoCore` as a pure function so they can be proved on macOS,
/// leaving the view to do nothing but render. That is the same split the engine already uses:
/// extract the decision, inject the effect. It means the rules most likely to be got wrong —
/// what the next line says, when `LAST` appears, that a rep interval never shows a time — are
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

    // MARK: - Each slot means what it says

    /// A rest names itself, and the next line carries the exercise.
    ///
    /// The name slot used to *promote* the upcoming exercise during rest, on the reasoning that
    /// "Break" tells you what you already know. Removing the `REST` badge retired that reasoning:
    /// with the promotion in place a rest screen showed the **next** exercise's name and nothing
    /// anywhere said you were resting. Naming the rest puts a real word back on that screen, and
    /// it costs the next line nothing.
    func testARestNamesItselfAndTheNextLineCarriesTheExercise() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 1,          // the rest after "Row"
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.name, "Break", "the rest says what it is")
        XCTAssertEqual(screen?.next, .exercise("Bench Press"), "and next says what it is for")
    }

    /// The next line is present on **every** running screen, rest included.
    ///
    /// The promotion forced it away: it was suppressed while resting to stop it repeating the
    /// promoted name, so the line vanished and the layout changed shape at exactly the moment you
    /// started resting.
    func testTheNextLineIsPresentOnARestScreenToo() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertNotNil(screen?.next, "a rest screen keeps its next line")
    }

    /// A rest is announced with the same word and the same order as it is drawn: what this is,
    /// how long is left, then what it is for. Nothing is said twice, and nothing is dropped.
    func testARestIsAnnouncedInTheOrderItIsDrawn() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(
            screen?.accessibilityAnnouncement,
            "Resting. Break. 30 seconds remaining. Next: Bench Press."
        )
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

    /// The final interval is a rest whenever the last step carries a `restAfter` — which is every
    /// step that carries one, since it fires after the final set too. `LAST` must still appear:
    /// knowing the last interval is the last one is the most motivating fact this screen carries,
    /// and a blank slot would swallow it.
    func testTheFinalRestStillShowsLast() {
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
        XCTAssertEqual(screen?.name, "Break", "the rest names itself here too")
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

    // MARK: - Which states are drawn as a word

    /// `WORK` and `REST` are the ordinary flow of a session and the name slot already says which
    /// one you are in, so neither is drawn. `PAUSED` is carried by the **blinking timer** instead
    /// — a badge is a line that appears and pushes the title and the clock down as it does, and
    /// this screen has just spent a pass getting rid of exactly that movement. `DONE` is the one
    /// left: the name slot has become the plan name and no clock is running to blink.
    func testOnlyDoneIsDrawnAsAWord() {
        XCTAssertFalse(SessionScreen.StateWord.work.showsBadge)
        XCTAssertFalse(SessionScreen.StateWord.rest.showsBadge)
        XCTAssertFalse(SessionScreen.StateWord.paused.showsBadge)
        XCTAssertTrue(SessionScreen.StateWord.done.showsBadge)
    }

    // MARK: - The target load

    /// A weighted set carries its load, and a rest does not — the weight belongs to the exercise,
    /// so the interval you rest between two weighted sets of the same exercise has none.
    func testAWeightedExerciseCarriesItsLoadAndARestDoesNot() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Bench Press", mode: .reps, reps: 8,
                         targetWeightKg: 20, restAfter: 30),
            ]),
        ])
        let intervals = PlanFlattener.flatten(plan)   // [Bench, Break]

        let bench = SessionPresentation.screen(
            intervals: intervals, index: 0, end: nil,
            isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )
        let rest = SessionPresentation.screen(
            intervals: intervals, index: 1,
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(bench?.weight, "20 kg")
        XCTAssertNil(rest?.weight)
    }

    /// The load is spoken, and in the position it is drawn — straight after the primary and
    /// before the progress. Both surfaces now hide this text behind the composed label, so a
    /// weight left out of the announcement would be one VoiceOver could not reach at all.
    func testTheLoadIsAnnouncedAfterThePrimary() {
        let plan = Plan(name: "P", blocks: [
            PlanBlock(steps: [
                PlanStep(label: "Bench Press", sets: 4, mode: .reps, reps: 8,
                         targetWeightKg: 20, restAfter: 30),
            ]),
        ])
        let intervals = PlanFlattener.flatten(plan)

        let screen = SessionPresentation.screen(
            intervals: intervals, index: 0, end: nil,
            isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(
            screen?.accessibilityAnnouncement,
            "Working. Bench Press. 8 reps. 20 kg. Set 1 of 4. Next: Break."
        )
    }

    /// An exercise with no target load says nothing about one — no stray unit, no empty slot in
    /// the sentence.
    func testAnUnweightedExerciseAnnouncesNoLoad() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,          // the rep step, no target weight
            end: nil, isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertNil(screen?.weight)
        XCTAssertEqual(
            screen?.accessibilityAnnouncement, "Working. Bench Press. 8 reps. Next: Last interval."
        )
    }

    // MARK: - The paused timer's blink

    /// Visible for the first half of each cycle, hidden for the second, so the two surfaces
    /// cannot blink out of step — they read the same clock, not two copies of a timer.
    func testTheBlinkIsVisibleForTheFirstHalfOfEachCycleAndHiddenForTheSecond() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)   // a whole second
        let half = PausedTimerBlink.period / 2

        XCTAssertTrue(PausedTimerBlink.isVisible(at: t), "start of the cycle")
        XCTAssertTrue(PausedTimerBlink.isVisible(at: t.addingTimeInterval(half - 0.01)))
        XCTAssertFalse(PausedTimerBlink.isVisible(at: t.addingTimeInterval(half)), "second half")
        XCTAssertFalse(PausedTimerBlink.isVisible(at: t.addingTimeInterval(PausedTimerBlink.period - 0.01)))
        XCTAssertTrue(PausedTimerBlink.isVisible(at: t.addingTimeInterval(PausedTimerBlink.period)), "and it wraps")
    }

    /// A running session does not blink, whatever the clock says — otherwise the timer would
    /// disappear for half of every second of the workout.
    func testARunningSessionIsAlwaysAtFullOpacity() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in stride(from: 0.0, through: PausedTimerBlink.period, by: 0.1) {
            XCTAssertEqual(PausedTimerBlink.opacity(isPaused: false, at: t.addingTimeInterval(offset)), 1)
        }
    }

    /// The blink has to be sampled often enough that its halves land on whole frames, or the
    /// timer jitters instead of blinking.
    func testTheSampleRateGivesWholeFramesPerHalfCycle() {
        XCTAssertGreaterThanOrEqual(PausedTimerBlink.period / PausedTimerBlink.sampleInterval, 2)
    }

    /// The word still reaches VoiceOver in **every** state, the two undrawn ones included.
    ///
    /// Speech has no layout to save, and a listener who joins mid-interval has no colour and no
    /// position to infer the state from. The spoken form is the same content as the screen, in the
    /// order it reads — the word, the name, the count, then what is next.
    func testTheSpokenWordSurvivesForTheStatesThatAreNoLongerDrawn() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 1,          // the synthetic rest
            end: t0.addingTimeInterval(30), isPaused: false, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .rest, "the model still carries it")
        XCTAssertEqual(
            screen?.accessibilityAnnouncement,
            "Resting. Break. 30 seconds remaining. Next: Bench Press.",
            "and it is still spoken"
        )
    }

    // MARK: - Where a pause control applies

    /// Pause is a statement about a clock, so a rep set — whose `primary` is the rep target and
    /// whose length is whatever you take — does not offer it. Timed work and rest both do.
    func testPauseAppliesOnlyWhereThereIsAClock() {
        let intervals = mixedIntervals()   // [Row 60s, Break 30s, Bench 8 reps]

        func screen(_ index: Int) -> SessionScreen? {
            SessionPresentation.screen(
                intervals: intervals, index: index,
                // A rep interval has no end date at all. An earlier version of this fixture
                // substituted zero and handed a rep set a clock it never has in a session.
                end: intervals[index].duration.map { t0.addingTimeInterval($0) },
                isPaused: false, isFinished: false,
                planName: "P", startedAt: t0, now: t0
            )
        }

        XCTAssertEqual(screen(0)?.allowsPause, true, "timed work has a clock")
        XCTAssertEqual(screen(1)?.allowsPause, true, "so does rest")
        XCTAssertEqual(screen(2)?.allowsPause, false, "a rep set has none")
    }

    /// The case that makes the rule more than a negation of "is this a rep set".
    ///
    /// `ExecutionEngine.advance` and `goBack` both run in the paused phase, so a session can be
    /// paused on a rest and then moved onto a rep set. Refusing the control there would leave it
    /// paused with nothing on screen able to resume it — the demo cannot reach this state, which
    /// is exactly why it is pinned here rather than eyeballed.
    func testARepSetStillAllowsPauseWhenTheSessionIsAlreadyPaused() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,          // the rep step
            end: nil, isPaused: true, isFinished: false,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.stateWord, .paused)
        XCTAssertEqual(screen?.primary, .reps(8), "still a rep set, not a clock")
        XCTAssertEqual(screen?.allowsPause, true, "but the way out must stay reachable")
    }

    /// A finished session has no clock either, so it refuses pause on the same grounds — there
    /// is nothing left to stop.
    func testAFinishedSessionRefusesPause() {
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: true,
            planName: "P", startedAt: t0, now: t0
        )

        XCTAssertEqual(screen?.allowsPause, false)
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

extension SessionScreenTests {

    /// Found by looking: the DONE screen read `0:24` for a six-second session, because the
    /// elapsed time was computed from the live clock and simply kept growing. The watch needs
    /// the moment the session actually ended, or "total elapsed" is not a total at all.
    func testTheElapsedTimeIsFrozenAtTheFinishNotTheCurrentTime() {
        let finishedAt = t0.addingTimeInterval(47 * 60)
        let screen = SessionPresentation.screen(
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
        let screen = SessionPresentation.screen(
            intervals: mixedIntervals(), index: 2,
            end: nil, isPaused: false, isFinished: true,
            planName: "P", startedAt: t0, finishedAt: nil,
            now: t0.addingTimeInterval(120)
        )

        XCTAssertEqual(screen?.primary, .elapsed(120))
    }
}

// MARK: - S4: the wire format must stay readable by an older snapshot

extension SessionScreenTests {

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
