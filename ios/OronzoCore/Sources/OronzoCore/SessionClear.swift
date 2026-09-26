import Foundation

/// Whether a "nothing is running" message may clear what the watch is showing.
///
/// **This exists because a clear cannot be trusted by its content.** `.sessionEnded` is the one
/// message in this protocol that carries no session and no time — it is a bare "the phone has
/// nothing" — and the application context it arrives in keeps its value across app launches and
/// installs. So a watch can be handed a clear that is *older than the workout it is displaying*,
/// at any moment, and it has no way to tell that from a real one. That is not hypothetical: this
/// project has been bitten by a clear written by a runner that was no longer live, and — measured
/// on paired simulators on 26 September 2026 — by a clear left in the context by a previous run
/// and delivered *after* the workout that replaced it.
///
/// The fix is to give the message something to be ordered by. `WatchMessage.idle(at:)` carries the
/// instant the phone decided it had nothing, which is comparable with the instant the session on
/// screen began — and that comparison settles every case without asking anybody:
///
/// - A clear stamped **before** the session on screen started cannot be about that session. It is
///   stale, and believing it is what puts **"No workout"** on a wrist mid-workout.
/// - A clear stamped **after** it began is the phone's current word on the matter, and the phone
///   is the authority. Believe it, and the wrist goes back to idle.
///
/// The older, undated `sessionEnded` is kept for compatibility and is **unorderable**, so it is
/// never allowed to clear a live screen: the watch asks instead, which is the recovery the two
/// apps already trust. That path is transitional — both apps are installed from Xcode together —
/// and it is conservative in the direction that matters: it can leave a screen up for one more
/// round trip, but it cannot erase a workout that is running.
///
/// A pure function with no clock of its own, like `SessionSchedule` and `AskSchedule`: the caller
/// has both times, this has the rule, and `swift test` proves it on macOS in a second.
public enum SessionClear {

    /// What to do with a clear, given what the watch is showing.
    public enum Decision: Equatable, Sendable {
        /// Take it: nothing is running, and the screen goes back to idle.
        case believe
        /// It is older than the session on screen, so it is not about it. Drop it silently.
        case stale
        /// Undated, and a live session is on screen. Ask the phone rather than guess.
        case unorderable
    }

    /// The rule.
    ///
    /// - Parameters:
    ///   - clearedAt: when the phone decided it had nothing, or `nil` for an undated clear.
    ///   - showingSince: when the session on screen started, or `nil` when there is none.
    ///   - isLive: whether a workout that has not finished is on screen — the only state with
    ///     anything to protect. A clear against an idle or a DONE screen is believed whatever it
    ///     says, because the worst it can do is redraw a screen that has nothing left to lose.
    public static func decide(
        clearedAt: Date?,
        showingSince: Date?,
        isLive: Bool
    ) -> Decision {
        guard isLive else { return .believe }
        guard let clearedAt else { return .unorderable }
        guard let showingSince else { return .believe }

        // Strictly before, not `<=`: a phone that clears in the same instant a session starts has
        // said the two things at the same moment, and the later write is the one that describes
        // now — which is the session.
        return clearedAt < showingSince ? .stale : .believe
    }
}
