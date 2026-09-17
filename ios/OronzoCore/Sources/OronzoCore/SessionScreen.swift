import Foundation

/// What the Watch screen shows, decided in one testable place.
///
/// The decisions live here rather than in the view for the same reason the engine takes `now`
/// as a parameter: **extract the decision, inject the effect.** The rules most likely to be got
/// wrong — what rest promotes, when `LAST` appears, that a rep interval never shows a time —
/// are then proved on macOS instead of being eyeballed on a wrist.
public struct SessionScreen: Equatable, Sendable {

    /// The colour-independent signal that both the glance metrics depend on. Never omitted.
    public enum StateWord: String, Sendable {
        case work = "WORK"
        case rest = "REST"
        case paused = "PAUSED"
        case done = "DONE"
    }

    public enum Primary: Equatable, Sendable {
        case clock(TimeInterval)
        case reps(Int)
        case elapsed(TimeInterval)
    }

    public enum Next: Equatable, Sendable {
        case exercise(String)
        case last
    }

    public let stateWord: StateWord
    public let name: String
    /// `nil` where there is genuinely nothing to count — the view shows an em dash rather than
    /// an empty countdown.
    public let primary: Primary?
    /// The set/round progress line, or the block name when there is no progress to report.
    public let context: String?
    public let next: Next?
    /// Spoken by VoiceOver. Built here because it needs the progress form ("Set 2 of 4") and the
    /// block-name fallback that `context` may carry instead.
    public let accessibilityAnnouncement: String
}

public enum SessionPresentation {

    /// The whole screen, from the state the phone last sent.
    ///
    /// Returns `nil` when there is nothing to show, so the view falls back to its idle state
    /// rather than being told to render an empty session.
    public static func screen(
        intervals: [Interval],
        index: Int,
        end: Date?,
        isPaused: Bool,
        isFinished: Bool,
        planName: String?,
        startedAt: Date?,
        now: Date
    ) -> SessionScreen? {
        guard intervals.indices.contains(index) else { return nil }
        let interval = intervals[index]
        let upcoming = intervals.indices.contains(index + 1) ? intervals[index + 1] : nil

        // MARK: State word

        // Finished and paused outrank the underlying kind: the question the word exists to
        // answer is "am I working or resting", and paused is neither.
        let stateWord: SessionScreen.StateWord
        if isFinished {
            stateWord = .done
        } else if isPaused {
            stateWord = .paused
        } else if interval.kind == .rest {
            stateWord = .rest
        } else {
            stateWord = .work
        }

        // MARK: Name slot, and the rest promotion

        // During rest the name slot promotes **what is next**, because "Break" tells you what
        // you already know and what you actually want mid-rest is what you are resting toward.
        // Reusing the slot rather than adding one is what keeps the layout from changing shape.
        //
        // Which also means the next line is suppressed in exactly that case — otherwise the
        // same word would appear twice. Everywhere else, "what's next" still needs an answer;
        // on the final interval the answer is that there isn't one, and knowing the last
        // interval is the last one is the most motivating fact this screen can carry, so it
        // gets the slot rather than a blank.
        let promotesNext = !isFinished && interval.kind == .rest && upcoming != nil

        let name: String = if isFinished {
            planName ?? interval.name
        } else if promotesNext, let upcoming {
            upcoming.name
        } else {
            interval.name
        }

        let nextLine: SessionScreen.Next? = if isFinished || promotesNext {
            nil
        } else {
            upcoming.map { .exercise($0.name) } ?? .last
        }

        // MARK: Primary

        let primary: SessionScreen.Primary?
        if isFinished {
            primary = .elapsed(max(0, now.timeIntervalSince(startedAt ?? now)))
        } else if let end {
            // Paused arrives here too: `WatchLink.position` returns `now + remainingWhenPaused`,
            // so a paused session simply reads a frozen remainder rather than a running clock.
            primary = .clock(max(0, end.timeIntervalSince(now)))
        } else if let reps = interval.reps {
            // A rep interval has no length, so it shows its target and never a time.
            primary = .reps(reps)
        } else {
            primary = nil
        }

        return SessionScreen(
            stateWord: stateWord,
            name: name,
            primary: primary,
            context: interval.contextLabel,
            next: nextLine,
            accessibilityAnnouncement: announcement(
                stateWord: stateWord,
                name: name,
                primary: primary,
                progress: progress(of: interval),
                next: nextLine
            )
        )
    }

    // MARK: - Spoken form

    /// Only *progress* is spoken — never the block name.
    ///
    /// A sighted user can ignore a small label; a VoiceOver user has to sit through it. "Main"
    /// tells them nothing they need, so the announcement carries "Set 2 of 4" and stays silent
    /// about the block.
    private static func progress(of interval: Interval) -> String? {
        if interval.setCount > 1 { return "Set \(interval.setIndex) of \(interval.setCount)" }
        if interval.blockRoundCount > 1 { return "Round \(interval.blockRound) of \(interval.blockRoundCount)" }
        return nil
    }

    private static func announcement(
        stateWord: SessionScreen.StateWord,
        name: String,
        primary: SessionScreen.Primary?,
        progress: String?,
        next: SessionScreen.Next?
    ) -> String {
        var parts = [spoken(stateWord), name]
        if let primary { parts.append(spoken(primary)) }
        if let progress { parts.append(progress) }
        if let next { parts.append(spoken(next)) }
        return parts.joined(separator: ". ") + "."
    }

    private static func spoken(_ stateWord: SessionScreen.StateWord) -> String {
        switch stateWord {
        case .work: "Working"
        case .rest: "Resting"
        case .paused: "Paused"
        case .done: "Finished"
        }
    }

    private static func spoken(_ primary: SessionScreen.Primary) -> String {
        switch primary {
        case .clock(let remaining): "\(spokenDuration(remaining)) remaining"
        case .reps(let reps): "\(reps) reps"
        case .elapsed(let elapsed): "Total \(spokenDuration(elapsed))"
        }
    }

    private static func spoken(_ next: SessionScreen.Next) -> String {
        switch next {
        case .exercise(let name): "Next: \(name)"
        case .last: "Next: Last interval"
        }
    }

    /// Durations in words, because "47m 0s" read aloud is noise.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 { return plural(total, "second") }

        let minutes = total / 60
        if minutes < 60 { return plural(minutes, "minute") }

        let hours = minutes / 60
        let remainder = minutes % 60
        let hourPhrase = plural(hours, "hour")
        return remainder == 0 ? hourPhrase : "\(hourPhrase) \(plural(remainder, "minute"))"
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
