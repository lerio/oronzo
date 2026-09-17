import Foundation

/// The cues the watch can play. **Three, and that is the budget.**
///
/// The bar for a fourth: *does this distinction change what you do next?* Every extra cue
/// dilutes the ones that do, and a vocabulary nobody learns is just noise. A cue that cannot
/// clear that bar does not ship.
public enum HapticCue: String, CaseIterable, Sendable {
    /// One firm tap. **You can stop.**
    case stop
    /// Two firm taps. **You must start** — the only cue that changes what you do right now.
    case start
    /// A short rising pattern. The payoff, and the one moment worth noticing.
    case finished
}

/// Where the session is, as far as the haptic vocabulary is concerned.
///
/// Deliberately not the whole `SessionState`: a cue is decided by *what changed*, and this is the
/// smallest set of facts that answers the question "what should you do now?".
public struct SessionMoment: Equatable, Sendable {
    public let index: Int
    public let kind: StepKind
    public let isFinished: Bool

    public init(index: Int, kind: StepKind, isFinished: Bool = false) {
        self.index = index
        self.kind = kind
        self.isFinished = isFinished
    }
}

/// Which cue a transition deserves.
///
/// A pure function of (previous moment, current moment), for the same reason the engine takes
/// `now` as a parameter: **extract the decision, inject the effect.** Haptics are the one part of
/// this system that can only be judged on a wrist, so the part that *can* be proved on macOS is
/// separated out and tested — and only the buzz itself is left to a device.
///
/// Before this existed the watch distinguished only "the index changed", which meant work→rest
/// and rest→work felt identical — the two transitions that mean opposite things.
public enum HapticLanguage {

    /// Returns the cue to play, or `nil` when nothing worth a buzz changed.
    ///
    /// Note what is *not* here: pause and resume. A paused session is not a transition you act on
    /// — you already know you paused it — and `WatchLink.announce` skips paused state entirely.
    public static func cue(from previous: SessionMoment?, to current: SessionMoment) -> HapticCue? {
        // The first moment the watch ever sees is not a transition. A buzz when a session arrives
        // would be startling rather than informative.
        guard let previous else { return nil }

        // Checked before the index, because finishing does not move the index — the engine stays
        // on the last interval — and it must be announced exactly once.
        if current.isFinished, !previous.isFinished { return .finished }

        // Nothing moved, so nothing to say.
        guard current.index != previous.index else { return nil }

        switch (previous.kind, current.kind) {
        case (.exercise, .rest):
            // You can stop.
            return .stop

        case (.rest, .exercise), (.exercise, .exercise):
            // `start`, for both. A step with no rest after it goes straight to the next exercise,
            // which the design does not name — but the *action* is identical to rest→work: you
            // have to start the next thing. The cue is about what you do, not about what the
            // interval is called.
            return .start

        case (.rest, .rest):
            // Really happens: a step's `restAfter` and its block's `restBetweenRounds` can land
            // back to back. You are already resting and nothing changes what you do, so a buzz
            // here would be noise — which is exactly what the fourth-cue bar is meant to catch.
            return nil
        }
    }
}
