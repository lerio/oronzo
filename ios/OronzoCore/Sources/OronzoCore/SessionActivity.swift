import Foundation

/// What the Lock Screen is handed for the duration of a session.
///
/// **Deliberately not the Watch's snapshot.** The watch is sent the entire interval list, because
/// its transport is a single slot and partial state can be lost. The Lock Screen gets *current
/// plus next only*, because `ActivityAttributes` has a hard 4 KB ceiling and exceeding it throws
/// `dataTooLarge` at runtime — on a device, at the moment a workout starts. Same principle
/// (absolute dates, no per-second stream), opposite conclusion, and both deliberate.
///
/// **Plain data, with no ActivityKit anywhere in it.** That is what lets `swift test` exercise
/// the payload and its 4 KB ceiling on macOS — the only check in this project that needs no
/// device. The platform binding is a one-line conformance in `SessionActivityAttributes` below.
/// Getting this wrong the other way round (guarding the whole payload on `os(iOS)`) would have
/// left the tests unable to see the type at all, and silently never run.
public struct SessionActivityContent: Codable, Hashable, Sendable {

    /// `WORK` / `REST` / `PAUSED` / `DONE`, carried as the raw string because the payload has to
    /// cross into a widget extension. Which of them is actually *drawn* as a word is
    /// `SessionScreen.StateWord.showsBadge`, so this surface cannot diverge from the Watch.
    public var stateWord: String
    public var name: String
    public var context: String?
    public var next: String?
    /// The rep target, for an interval with no length. Carried so the Lock Screen cannot imply a
    /// duration where there is none.
    public var reps: Int?
    /// The **absolute** end of the current interval.
    ///
    /// Absolute rather than "seconds remaining" is the whole point: the system renders the
    /// countdown itself from this, so the Activity stays correct with no per-second updates from
    /// the app — the same idea that makes the watch work with the phone in a pocket.
    public var intervalEnd: Date?
    /// Shown as static text while paused, because a running timer cannot be paused.
    public var remainingWhenPaused: TimeInterval?

    /// **Deliberately no `staleDate`.**
    ///
    /// One was added here for a reason that turned out to be false: the theory was that the app
    /// could not post a content update from a locked phone, so the card should at least stop
    /// claiming to be current. It *can* — and setting the stale date to `intervalEnd` put it at
    /// the exact instant the app sends the next interval's content, which is the one moment the
    /// update has to land. So the card stopped advancing: the write goes out, the activity has
    /// just been marked stale, and the card holds what it had. A skip from the watch, arriving
    /// mid-interval, moved it — which is how it was found.
    ///
    /// Staleness is for a card the app *cannot* refresh. This app can, from any state of the
    /// phone, so the right stale date is none at all.
    public init(
        stateWord: String,
        name: String,
        context: String? = nil,
        next: String? = nil,
        reps: Int? = nil,
        intervalEnd: Date? = nil,
        remainingWhenPaused: TimeInterval? = nil
    ) {
        self.stateWord = stateWord
        self.name = name
        self.context = context
        self.next = next
        self.reps = reps
        self.intervalEnd = intervalEnd
        self.remainingWhenPaused = remainingWhenPaused
    }

    /// Built from the shared model, so the Lock Screen cannot disagree with the watch about the
    /// state word, what the next line says, or `LAST`.
    public init(screen: SessionScreen, intervalEnd: Date?, remainingWhenPaused: TimeInterval?) {
        var reps: Int?
        if case .reps(let value) = screen.primary { reps = value }

        self.init(
            stateWord: screen.stateWord.rawValue,
            name: screen.name,
            context: screen.context,
            next: screen.next?.label,
            reps: reps,
            intervalEnd: intervalEnd,
            remainingWhenPaused: remainingWhenPaused
        )
    }
}

// The platform binding, and nothing else.
//
// Guarded on `os(iOS)`, NOT on `canImport(ActivityKit)`: the module imports fine on macOS while
// `ActivityAttributes` itself is unavailable there, so `canImport` compiles the guard and then
// fails on the symbol. Discovered by the S1 spike; the real thing needs the identical guard.
#if os(iOS)
import ActivityKit

public struct SessionActivityAttributes: ActivityAttributes {
    public typealias ContentState = SessionActivityContent
    public init() {}
}
#endif
