import Foundation

/// What the Watch screen shows, decided in one testable place.
///
/// The decisions live here rather than in the view for the same reason the engine takes `now`
/// as a parameter: **extract the decision, inject the effect.** The rules most likely to be got
/// wrong — what the next line says, when `LAST` appears, that a rep interval never shows a time —
/// are then proved on macOS instead of being eyeballed on a wrist.
public struct SessionScreen: Equatable, Sendable {

    /// The state, as one word.
    ///
    /// Drawn as a badge only where the exercise name cannot say it — see `showsBadge`. It is
    /// still *spoken* in every state, and it is still the one vocabulary all surfaces spell the
    /// same way.
    public enum StateWord: String, Sendable {
        case work = "WORK"
        case rest = "REST"
        case paused = "PAUSED"
        case done = "DONE"

        /// Whether a surface draws this state as a word.
        ///
        /// `work` and `rest` are the ordinary flow of a session, and the name slot already says
        /// which one you are in — a badge restating it is a line of chrome above every single
        /// interval. `paused` is carried by the **blinking timer** instead (see
        /// `PausedTimerBlink`), which signals it without adding a line that pushes the title and
        /// the clock around as it appears. What is left is `done`, where the name slot has become
        /// the plan name and no clock is running to blink.
        ///
        /// The word is still spoken in **every** state, `paused` included — see
        /// `accessibilityAnnouncement`. Speech costs no layout, and it is what keeps the state
        /// from resting on the blink alone for a listener.
        public var showsBadge: Bool {
            switch self {
            case .done: true
            case .work, .rest, .paused: false
            }
        }
    }

    public enum Primary: Equatable, Sendable {
        case clock(TimeInterval)
        case reps(Int)
        case elapsed(TimeInterval)
    }

    public enum Next: Equatable, Sendable {
        /// The exercise coming up, and the load it is prescribed at when it has one.
        ///
        /// The load belongs to the same question the name does — *what am I doing next, and with
        /// what* — and it is worth most on the rest before the exercise, where the current line
        /// has no weight of its own to show.
        case exercise(String, weight: String?)
        case last

        /// The wording of the next-up line.
        ///
        /// Defined once because it is now read by three surfaces. It was already written out
        /// separately in the watch view and the phone runner; the Lock Screen would have made
        /// three hand-written copies of the same two strings, which is the duplication this
        /// whole vocabulary exists to prevent.
        ///
        /// The load is held off the name by the same `·` the prefix uses. Run together — `Bench
        /// Press 20 kg` — a multi-word name and its number read as one phrase on a line this
        /// narrow, which is the misreading the main screen avoids by stacking them instead.
        public var label: String {
            switch self {
            case .exercise(let name, let weight):
                if let weight { "NEXT · \(name) · \(weight)" } else { "NEXT · \(name)" }
            case .last: "LAST"
            }
        }
    }

    public let stateWord: StateWord
    public let name: String
    /// `nil` where there is genuinely nothing to count — the view shows an em dash rather than
    /// an empty countdown.
    public let primary: Primary?
    /// The target load, e.g. `20 kg`. `nil` on a rest and on an exercise with no target.
    ///
    /// It sits **under the primary**, not under the name, so the two numbers read together as one
    /// figure. Both surfaces draw it now, which is why it lives here rather than in the phone's
    /// view — the rule is that this model carries what the two must agree on, and the weight
    /// moving onto the watch is what made it their business.
    public let weight: String?
    /// The set/round progress line, or the block name when there is no progress to report.
    public let context: String?
    public let next: Next?
    /// Whether a pause control applies to this screen.
    ///
    /// Pause is a statement about a clock, so it is offered only where there is one to stop —
    /// timed work and rest. A rep set has none: its length is whatever you take. **The control's
    /// slot is then left empty rather than closed up**, so the controls either side of it do not
    /// move between intervals.
    ///
    /// Derived from the interval rather than from `primary`. The two agree today, but `primary`
    /// depends on the caller passing `end` faithfully, and a control's availability silently
    /// depending on an argument some future caller gets wrong is the kind of coupling this model
    /// exists to avoid.
    ///
    /// A paused session allows it whatever the interval. `ExecutionEngine.advance` and `goBack`
    /// both run in the paused phase, so a session can be paused on a rest and then moved onto a
    /// rep set — and refusing the control there would strand it with no way to resume.
    public let allowsPause: Bool
    /// Spoken by VoiceOver. Built here because it needs the progress form ("Set 2 of 4") and the
    /// block-name fallback that `context` may carry instead.
    public let accessibilityAnnouncement: String
}

/// The blink a paused timer does, decided here so the two surfaces cannot blink out of step.
///
/// **A pure function of the clock**, not a repeating animation and not a stored toggle. Both
/// surfaces already have a time source — the watch's `TimelineView`, the phone's runner — and a
/// rule derived from the clock cannot drift out of phase between them, cannot keep blinking after
/// the session is resumed, and cannot be caught half-faded when the watch comes back from a
/// wrist-drop suspension, which is what a `repeatForever` animation does.
public enum PausedTimerBlink {

    /// One full cycle: visible for the first half, hidden for the second.
    ///
    /// One second, which is about the slowest rate that still reads as blinking rather than as a
    /// flicker — the timer is what you are looking at while paused, and a fast blink of the
    /// largest thing on the screen is exhausting.
    public static let period: TimeInterval = 1.0

    /// How often a surface has to redraw to show the blink cleanly.
    ///
    /// Four samples per cycle. Below that the halves do not land on whole frames and the timer
    /// appears to jitter rather than blink.
    public static let sampleInterval: TimeInterval = period / 4

    /// Whether the timer is in its visible half at `now`.
    public static func isVisible(at now: Date) -> Bool {
        let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return phase < period / 2
    }

    /// The opacity a paused timer draws with. Anything not paused is simply opaque.
    public static func opacity(isPaused: Bool, at now: Date) -> Double {
        guard isPaused else { return 1 }
        return isVisible(at: now) ? 1 : 0
    }
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
        finishedAt: Date? = nil,
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

        // MARK: Name slot, and the next line

        // Each slot now means exactly what it says: the name slot is the interval you are in, and
        // the next line is the interval after it — a rest included, so "Break" leads the next line
        // before every set that has one.
        //
        // The name slot used to **promote** the upcoming exercise during rest, on the reasoning
        // that "Break" tells you what you already know. Two things retired that. The state word
        // badge that used to say `REST` is no longer drawn, so promoting the next exercise left
        // nothing on screen saying you were resting at all; and the promotion made the next line
        // either duplicate the name or vanish to avoid duplicating it, which changed the layout's
        // shape mid-rest. Naming the rest puts a real word back on that screen and costs the next
        // line nothing.
        let name: String = isFinished ? (planName ?? interval.name) : interval.name

        // Only a finished session has no next line: it has no "next" at all. On the final interval
        // the answer to "what's next" is that there isn't one, and knowing the last interval is
        // the last one is the most motivating fact this screen can carry, so it gets the slot
        // rather than a blank.
        //
        // The load carried is the *upcoming* interval's, which is nil on a rest — so a break
        // before an unweighted exercise, or before another break, stays a bare `NEXT · Break`
        // with nothing trailing it. Nothing here special-cases that: it falls out of the interval
        // the line is about, which is the only one whose load it has any business stating.
        let nextLine: SessionScreen.Next? = if isFinished {
            nil
        } else {
            upcoming.map { .exercise($0.name, weight: $0.weightDisplay) } ?? .last
        }

        // MARK: Primary

        let primary: SessionScreen.Primary?
        if isFinished {
            // **Frozen at the moment the session ended, not at the current time.** Computing
            // this from `now` made the number grow on every tick — a six-second demo read 0:24
            // by the time anyone glanced at it, and it would have gone on climbing all evening.
            // Found by looking at the screen rather than by reasoning about it.
            //
            // The fallback matters: an older build's snapshot has no finish time, and a total
            // that is wrong beats no screen at all.
            let ended = finishedAt ?? now
            primary = .elapsed(max(0, ended.timeIntervalSince(startedAt ?? ended)))
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
            weight: interval.weightDisplay,
            context: interval.contextLabel,
            next: nextLine,
            allowsPause: !isFinished && (isPaused || interval.advancesAutomatically),
            accessibilityAnnouncement: announcement(
                stateWord: stateWord,
                name: name,
                primary: primary,
                weight: interval.weightDisplay,
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
    /// about the block. Effort is progress in the same sense and is spoken the same way, in the
    /// same order as `Interval.contextLabel` — the two must not disagree about what a given
    /// interval says.
    private static func progress(of interval: Interval) -> String? {
        if interval.setCount > 1 { return "Set \(interval.setIndex) of \(interval.setCount)" }
        if let intensity = interval.intensity { return intensity.rawValue }
        if interval.blockRoundCount > 1 { return "Round \(interval.blockRound) of \(interval.blockRoundCount)" }
        return nil
    }

    private static func announcement(
        stateWord: SessionScreen.StateWord,
        name: String,
        primary: SessionScreen.Primary?,
        weight: String?,
        progress: String?,
        next: SessionScreen.Next?
    ) -> String {
        var parts = [spoken(stateWord), name]
        if let primary { parts.append(spoken(primary)) }
        // Spoken as it is drawn — directly after the primary and before the progress, which is
        // where it sits on screen. Both surfaces hide this text behind the composed label, so a
        // weight left out of here would be a weight VoiceOver could not reach at all.
        if let weight { parts.append(weight) }
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

    /// Written for the ear rather than copied from the drawn form — the same asymmetry the rep
    /// unit has. `, 20 kg` is how the load is said; the drawn `·` is punctuation for a small
    /// screen. It has to be spoken at all because both runners hide this line behind the composed
    /// label, so a load left out here would be one VoiceOver could not reach.
    private static func spoken(_ next: SessionScreen.Next) -> String {
        switch next {
        case .exercise(let name, let weight):
            if let weight { "Next: \(name), \(weight)" } else { "Next: \(name)" }
        case .last: "Next: Last interval"
        }
    }

    /// Durations in words, because "47m 0s" read aloud is noise.
    private static func spokenDuration(_ seconds: TimeInterval) -> String {
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
