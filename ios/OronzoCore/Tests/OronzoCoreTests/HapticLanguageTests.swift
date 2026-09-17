import XCTest
@testable import OronzoCore

/// S6 — the haptic vocabulary.
///
/// Haptics are the one part of this system that cannot be tested anywhere but a wrist, so the
/// *decision* is separated from the *effect*: which cue a transition deserves is a pure function
/// here, and the watch does nothing but play what it returns. Same trick the engine uses for
/// time — extract the decision, inject the effect — and it means the vocabulary is proved on
/// macOS even though the feel is not.
///
/// What these tests cannot cover: whether two taps are actually distinguishable from one on a
/// real wrist while you are out of breath. That is the whole point of the cue, and only a wrist
/// can answer it.
final class HapticLanguageTests: XCTestCase {

    private func moment(_ index: Int, _ kind: StepKind, finished: Bool = false) -> SessionMoment {
        SessionMoment(index: index, kind: kind, isFinished: finished)
    }

    // MARK: - The vocabulary

    func testThereAreExactlyThreeCues() {
        XCTAssertEqual(
            HapticCue.allCases.count, 3,
            """
            3 is the budget from UI design §6. The bar for a fourth is "does this distinction \
            change what you do next?" — every extra cue dilutes the ones that do.
            """
        )
    }

    // MARK: - The transitions that earned a cue

    /// You can stop. The one cue that lets you relax.
    func testWorkToRestIsStop() {
        XCTAssertEqual(
            HapticLanguage.cue(from: moment(0, .exercise), to: moment(1, .rest)),
            .stop
        )
    }

    /// You must start — "the only cue that changes what you do *right now*".
    func testRestToWorkIsStart() {
        XCTAssertEqual(
            HapticLanguage.cue(from: moment(1, .rest), to: moment(2, .exercise)),
            .start
        )
    }

    /// A step with no rest after it goes straight to the next exercise. The design names only
    /// work→rest and rest→work, but this transition needs a cue for the same reason rest→work
    /// does: you have to start the next thing. It maps to `start` because the *action* is
    /// identical, which is what the cue is for.
    func testExerciseToExerciseIsStart() {
        XCTAssertEqual(
            HapticLanguage.cue(from: moment(0, .exercise), to: moment(1, .exercise)),
            .start
        )
    }

    func testFinishingIsItsOwnCue() {
        XCTAssertEqual(
            HapticLanguage.cue(from: moment(2, .exercise), to: moment(2, .exercise, finished: true)),
            .finished
        )
    }

    // MARK: - The transitions that deliberately earned nothing

    /// Rest followed by rest — which really happens, because a step's `restAfter` and its
    /// block's `restBetweenRounds` can land back to back. You are already resting and nothing
    /// changes what you do, so buzzing would be noise.
    func testRestToRestIsSilent() {
        XCTAssertNil(HapticLanguage.cue(from: moment(1, .rest), to: moment(2, .rest)))
    }

    /// The first moment the watch ever sees is not a transition. A buzz when the session arrives
    /// would be startling rather than informative.
    func testTheFirstMomentIsSilent() {
        XCTAssertNil(HapticLanguage.cue(from: nil, to: moment(0, .exercise)))
    }

    /// The finish is announced once. Every subsequent observation is silent, or the watch would
    /// buzz forever after a workout ended.
    func testAnAlreadyFinishedSessionIsSilent() {
        XCTAssertNil(
            HapticLanguage.cue(
                from: moment(2, .exercise, finished: true),
                to: moment(2, .exercise, finished: true)
            )
        )
    }

    func testStandingStillIsSilent() {
        XCTAssertNil(HapticLanguage.cue(from: moment(3, .exercise), to: moment(3, .exercise)))
    }

    // MARK: - Exhaustiveness

    /// Every combination the watch can actually observe, asserted to land on a known cue or on
    /// silence. The return type already prevents a cue *outside* the vocabulary; what this
    /// catches is a transition that should speak and doesn't, or vice versa.
    func testEveryReachableTransitionHasADecidedOutcome() {
        let kinds: [StepKind] = [.exercise, .rest]

        for previousKind in kinds {
            for currentKind in kinds {
                for indexAdvanced in [false, true] {
                    for finished in [false, true] {
                        let from = moment(1, previousKind)
                        let to = moment(indexAdvanced ? 2 : 1, currentKind, finished: finished)
                        let cue = HapticLanguage.cue(from: from, to: to)

                        let expected: HapticCue? = if finished {
                            .finished
                        } else if !indexAdvanced {
                            nil
                        } else {
                            switch (previousKind, currentKind) {
                            case (.exercise, .rest): .stop
                            case (.rest, .exercise), (.exercise, .exercise): .start
                            case (.rest, .rest): nil
                            }
                        }

                        XCTAssertEqual(
                            cue, expected,
                            "\(previousKind) → \(currentKind), advanced=\(indexAdvanced), finished=\(finished)"
                        )
                    }
                }
            }
        }
    }
}
