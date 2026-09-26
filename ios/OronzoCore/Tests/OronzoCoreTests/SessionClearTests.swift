import XCTest
@testable import OronzoCore

/// The rule that decides whether "the phone has nothing" may erase what the wrist is showing.
///
/// The failure it prevents has happened: a workout running on the phone, a clear that predated it
/// sitting in the single-slot application context, and a wrist reading **"No workout"** with the
/// workout going perfectly well on the phone. These tests pin each side of that boundary, because
/// the rule is one comparison and the cost of getting it backwards is the most expensive bug this
/// project has.
final class SessionClearTests: XCTestCase {

    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The case that cost the hours

    /// **A clear stamped before the workout began is not about the workout.** This is the whole
    /// point of dating it: the phone said "nothing is running" *before* it had anything to run.
    func testAClearFromBeforeTheSessionStartedIsStale() {
        XCTAssertEqual(
            SessionClear.decide(
                clearedAt: started.addingTimeInterval(-30),
                showingSince: started,
                isLive: true
            ),
            .stale
        )
    }

    /// And one stamped after it is the phone's current word, so the wrist clears.
    func testAClearFromAfterTheSessionStartedIsBelieved() {
        XCTAssertEqual(
            SessionClear.decide(
                clearedAt: started.addingTimeInterval(30),
                showingSince: started,
                isLive: true
            ),
            .believe
        )
    }

    /// The same instant means the phone wrote both at once — `SessionHost.begin` and a
    /// `clearIfIdle` a moment later — and the session is the later word. It must survive.
    func testAClearInTheSameInstantAsTheStartIsBelieved() {
        XCTAssertEqual(
            SessionClear.decide(clearedAt: started, showingSince: started, isLive: true),
            .believe
        )
    }

    // MARK: - When there is nothing to protect

    /// Nothing on screen: the worst a clear can do is redraw a screen that has nothing to lose, so
    /// it is never worth a round trip to double-check.
    func testAClearAgainstAnIdleScreenIsAlwaysBelieved() {
        XCTAssertEqual(
            SessionClear.decide(clearedAt: started.addingTimeInterval(-30), showingSince: nil, isLive: false),
            .believe
        )
    }

    /// DONE is the same answer as idle: the session has finished, so the screen carries no live
    /// state to erase — and this is the ordinary, legitimate clear, from `teardown`.
    func testAClearAgainstAFinishedSessionIsBelieved() {
        XCTAssertEqual(
            SessionClear.decide(
                clearedAt: started.addingTimeInterval(120),
                showingSince: started,
                isLive: false
            ),
            .believe
        )
    }

    // MARK: - The undated clear, which cannot be ordered

    /// An older build's clear says nothing about *when*. Against a live screen it is never obeyed
    /// — the watch asks instead — because obeying it is the bug, and refusing it merely leaves the
    /// screen up until the phone answers.
    func testAnUndatedClearAgainstALiveScreenIsUnorderable() {
        XCTAssertEqual(
            SessionClear.decide(clearedAt: nil, showingSince: started, isLive: true),
            .unorderable
        )
    }

    /// Against an idle screen it is still just a clear: there is nothing to protect, and refusing
    /// it would leave a stale screen that no later message corrects.
    func testAnUndatedClearAgainstAnIdleScreenIsBelieved() {
        XCTAssertEqual(
            SessionClear.decide(clearedAt: nil, showingSince: nil, isLive: false),
            .believe
        )
    }

    /// A live screen with no session identity to compare against cannot happen through `apply` —
    /// intervals and `startedAt` arrive together — but the rule answers rather than trapping.
    func testALiveScreenWithNoStartTimeIsBelieved() {
        XCTAssertEqual(
            SessionClear.decide(clearedAt: started, showingSince: nil, isLive: true),
            .believe
        )
    }
}
