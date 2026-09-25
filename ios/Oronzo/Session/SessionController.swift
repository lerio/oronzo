import Foundation
import OronzoCore

/// Drives a workout: owns the engine, ticks it, and turns engine events into sound, haptics
/// and published state for the view.
///
/// The engine does the thinking (`OronzoCore.ExecutionEngine`, tested on macOS without a
/// device); this is the part that needs a running app.
@MainActor
@Observable
final class SessionController {

    let planID: UUID
    let planName: String

    private(set) var remaining: TimeInterval?

    /// Set once the session ends — whether it ran its course or was stopped early.
    private(set) var completed: CompletedSession?

    private let audio: WorkoutAudio
    private let link = PhoneConnectivity.shared
    private var engine: ExecutionEngine
    private var ticker: Task<Void, Never>?
    private var lastCountdownSecond: Int?
    private var lastPushedState: SessionState?

    init(plan: Plan, exercises: [UUID: ExerciseInfo], audio: WorkoutAudio = WorkoutAudio()) {
        self.planID = plan.id
        self.planName = plan.name
        self.audio = audio
        self.engine = ExecutionEngine(
            intervals: PlanFlattener.flatten(plan, exercises: exercises)
        )
        // Deliberately nothing here but construction.
        //
        // `SessionRunner` builds this as a `@State(initialValue:)`, and SwiftUI re-evaluates that
        // expression on **every** re-render of the view presenting it — the runner included, so
        // this happens repeatedly during a workout, not once at the start. Measured on a simulator
        // session: each re-render builds a fresh controller, and the previous one is not released
        // until the next build replaces it, so there is always a discarded controller alive.
        //
        // Anything done here is therefore done to one of those. Binding the watch link from here
        // is what let one answer the watch's controls from its own empty engine — a wrist that
        // jumped back to the first exercise and then stopped responding, with the phone entirely
        // unaffected. See `pushState`'s guard and `PhoneConnectivity.claim`.
    }

    // MARK: - What the view reads

    var current: Interval? { engine.current }
    var isRunning: Bool { engine.phase == .running }
    var isPaused: Bool { engine.phase == .paused }
    var isFinished: Bool { engine.phase == .finished }
    var isEmpty: Bool { engine.intervals.isEmpty }

    var next: Interval? {
        let index = engine.currentIndex + 1
        return engine.intervals.indices.contains(index) ? engine.intervals[index] : nil
    }

    var position: Int { engine.currentIndex + 1 }
    var totalCount: Int { engine.intervals.count }

    /// The shared presentation model.
    ///
    /// The phone and the watch both draw from `SessionPresentation`, so they cannot disagree
    /// about what the state word is, what the next line says, or when `LAST` appears.
    /// Those rules are tested once, in `OronzoCore`, rather than implemented twice and left to
    /// drift — which is the whole reason the model lives there.
    ///
    /// Note the index: `position` above is 1-based because it is read by a person ("2 of 12"),
    /// while the model wants the engine's 0-based index.
    func screen(at now: Date) -> SessionScreen? {
        SessionPresentation.screen(
            intervals: engine.intervals,
            index: engine.currentIndex,
            // Paused holds the clock rather than clearing it. `Engine.pause` sets `intervalEnd`
            // to nil and keeps the remainder in `remainingWhenPaused`, so passing `intervalEnd`
            // alone drew the **em dash** — the "nothing to count" sign — for the whole pause.
            // `WatchLink.position` has always turned the remainder back into a date for the
            // watch; this is the same conversion, and the phone had simply never had it.
            end: engine.intervalEnd
                ?? engine.remainingWhenPaused.map { now.addingTimeInterval($0) },
            isPaused: isPaused,
            isFinished: isFinished,
            planName: planName,
            startedAt: engine.startedAt,
            now: now
        )
    }

    // MARK: - Lifecycle

    func start() {
        guard engine.phase == .idle, !isEmpty else { return }
        // From here until `teardown`, this controller *is* what the watch is being told about —
        // and it is refused if a live session already holds the link. A refused controller is
        // inert on purpose: it is either a SwiftUI re-render's discarded copy or a genuine second
        // runner, and in neither case may it move the wrist. Logged, because it means something
        // upstream is building a runner it does not install.
        guard link.claim(self) else {
            Log.debug("refused to start a second session while one is live")
            return
        }
        // Named, because *which* controller is running the workout is what every failure in this
        // file comes down to — there is more than one of these alive at a time, by SwiftUI's doing
        // rather than by design, and from the outside they are indistinguishable.
        Log.debug("session: started by \(ObjectIdentifier(self))")
        audio.start()
        // Deliberately ignoring the returned event: a beep the instant you press Start
        // would be noise, not information.
        _ = engine.start(at: .now)
        refreshClocks()
        startTicking()

        // The watch gets the whole plan, so it can keep counting and buzzing even if this
        // phone goes quiet. Sent as part of every update — see SessionSnapshot for why.
        pushState(force: true)
    }

    /// Called when the view goes away. Safe to call at any point.
    func teardown() {
        stopTicking()
        audio.stop()

        // Leaving the runner ends the session as far as the watch is concerned, even though
        // nothing was "finished" — but **only if this runner is still the one the watch is
        // hearing about**. `resign` refuses if a newer session has already advertised itself,
        // which is the case that must not clear: a re-created runner would otherwise hand the
        // watch a running session and then erase it, leaving the wrist on "No workout" while
        // the workout carried on. Harmless if the session already ended.
        if link.resign(self) {
            link.send(.sessionEnded)
        }
    }

    func pause() {
        guard isRunning else { return }
        _ = engine.pause(at: .now)
        refreshClocks()
        // The clock is held, so nothing is due until someone resumes. Leaving the ticker running
        // would be a loop that wakes, finds nothing to do, and sleeps again for as long as the
        // session stays paused.
        stopTicking()
        pushState()
    }

    func resume() {
        guard isPaused else { return }
        _ = engine.resume(at: .now)
        refreshClocks()
        pushState()
        rearmTicking()
    }

    /// Completes the current interval now — "done" on a rep set, "skip" on a timed one.
    func advance(skipped: Bool = false) {
        guard !isFinished else { return }
        handle(engine.advance(at: .now, skipped: skipped))
        refreshClocks()
        pushState()
        rearmTicking()
    }

    func goBack() {
        guard !isFinished else { return }
        _ = engine.goBack(at: .now)
        refreshClocks()
        pushState()
        rearmTicking()
    }

    /// Ends the session early. Everything not reached is recorded as such.
    func finishEarly() {
        guard !isFinished else { return }
        completed = engine.abandon(at: .now)
        stopTicking()
        audio.stop()
        // The final snapshot **replaces** `.sessionEnded` rather than preceding it. The
        // application context is a single slot — whatever is written last is all that survives
        // — so sending both would leave only the `.sessionEnded` and the watch would never show
        // DONE at all. `abandon` has already moved the engine to `.finished`, so this carries
        // `isFinished: true`, which is what the watch draws its DONE screen from.
        //
        // The screen is still cleared, just not here: `teardown` sends `.sessionEnded` when the
        // runner goes away, which is what keeps DONE brief rather than a stale screen.
        pushState(force: true)
    }

    // MARK: - Ticking

    /// Wakes the session at the instants it can actually change, and not otherwise.
    ///
    /// **This ran ten times a second for the whole workout, and it was the phone's worst piece of
    /// busy-work.** Each tick wrote `remaining` — an observed property, so the entire runner body
    /// re-evaluated — for a clock that only changes once a second, and each tick rebuilt a
    /// `SessionScreen` (strings, arrays, the joined VoiceOver announcement) for the Lock Screen to
    /// compare against what it already had. Almost every one of those wakes found nothing: a
    /// minute-long interval has four instants at which anything can happen.
    ///
    /// `SessionSchedule` supplies them, so this sleeps to the next one instead of asking. The
    /// countdown steps land exactly on their second rather than within 100 ms of it, which is a
    /// small improvement to the beeps as well as a large one to the battery.
    ///
    /// It rests while the session is paused — the clock is held, so nothing is due — and `resume`,
    /// `advance` and `goBack` start it again, because each of those can move the session onto an
    /// interval with a new end to wait for.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let next = self.nextWake() else { return }

                // Positive by construction, but the world can move between the two reads; looping
                // re-reads the clock, and the next answer is always ahead of it, so it cannot spin.
                let delay = next.timeIntervalSinceNow
                guard delay > 0 else { continue }
                try? await Task.sleep(for: .seconds(delay))

                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    /// The next instant worth waking for, or `nil` when nothing is due and the loop can rest.
    private func nextWake() -> Date? {
        guard isRunning else { return nil }
        let now = Date()
        let event = SessionSchedule.nextEvent(
            after: now,
            end: engine.intervalEnd,
            isPaused: isPaused,
            isFinished: isFinished
        )

        // A rep interval has no clock to repaint and no deadline of its own — only the user or the
        // watch can move it on — so a real event is the only thing worth waking for.
        guard engine.intervalEnd != nil else { return event }

        // A timed interval needs a wake per second to repaint its clock, because this surface draws
        // its countdown from a stored remainder rather than letting the system render it.
        let second = SessionSchedule.nextSecond(after: now)
        return event.map { min($0, second) } ?? second
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Re-arms the ticker after something moved the session on.
    ///
    /// Refuses when the session is no longer running, which is the case that matters: `advance`
    /// is how a session finishes its last interval, and `handle` has already stopped the ticker
    /// by then.
    private func rearmTicking() {
        guard isRunning else { return }
        startTicking()
    }

    private func tick() {
        guard isRunning else { return }
        handle(engine.tick(now: .now))
        refreshClocks()
        fireCountdownCue()
        // Only sends when something actually changed, so this is not 10 messages a second.
        pushState()
    }

    /// Tells the watch where the session is. Skipped when nothing has moved, so a session that is
    /// simply counting down does not send a message a second.
    private func pushState(force: Bool = false) {
        // **Only the session holding the link may speak to the watch**, whatever asked it to.
        //
        // This is the guard that closes a real reported failure. A controller that never claimed
        // the link — the copy SwiftUI builds and discards on every re-render of the presenter —
        // can still be driven by a watch control if it won the handler, and its engine is empty:
        // `advance` passes its `!isFinished` check on an idle engine, does nothing, and then
        // pushed a **first-interval** snapshot anyway. The wrist jumped back to exercise one while
        // the phone was untouched, and the next press pushed the identical state, which the dedupe
        // below swallowed — so the button then appeared dead. Both halves, one cause: a session
        // that was not the session writing to the wrist.
        let state = currentState
        let moved = force || state != lastPushedState

        guard link.isAdvertising(self) else {
            // Worth a line only when something had moved, and worth one at all because this is
            // invisible from the outside: the wrist carries on looking right whether it is being
            // told or not.
            if moved {
                Log.debug("session: \(ObjectIdentifier(self)) is not the live session; the watch was not told")
            }
            return
        }

        guard moved else { return }
        lastPushedState = state
        link.send(currentMessage)
    }

    /// Where the session is, in the shape the watch needs it.
    private var currentState: SessionState {
        SessionState(
            currentIndex: engine.currentIndex,
            isPaused: isPaused,
            isFinished: isFinished,
            intervalEnd: engine.intervalEnd,
            remainingWhenPaused: engine.remainingWhenPaused,
            // Without this the watch computes the DONE total from its own clock and the number
            // climbs forever. Sent so the watch can freeze it at the real finish.
            finishedAt: engine.finishedAt
        )
    }

    /// A control from the watch.
    ///
    /// `.requestState` is normally answered by the link itself — it has to be answerable when
    /// no session is running at all, which is exactly when the watch asks. This case is here so
    /// the switch stays exhaustive without a `default:` that would silently swallow whatever
    /// control is added next; reaching it costs one redundant snapshot, and nothing else.
    func handle(_ control: WatchControl) {
        switch control {
        case .next: advance()
        case .previous: goBack()
        case .togglePause: isPaused ? resume() : pause()
        case .finish: finishEarly()
        case .requestState: pushState(force: true)
        }
    }

    private func refreshClocks() {
        remaining = engine.remaining(at: .now)
    }

    /// Beeps on each of the last three seconds of a timed interval. A rep interval has no
    /// end, so there is nothing to count down.
    private func fireCountdownCue() {
        guard let remaining, remaining > 0, remaining <= 3 else {
            lastCountdownSecond = nil
            return
        }
        let second = Int(remaining.rounded(.up))
        guard second != lastCountdownSecond else { return }
        lastCountdownSecond = second
        audio.playCountdownTick()
    }

    private func handle(_ events: [EngineEvent]) {
        for event in events {
            switch event {
            case .started, .advanced:
                audio.playTransition()
                lastCountdownSecond = nil

            case .paused, .resumed:
                break

            case .finished:
                audio.playFinish()
                completed = engine.snapshot(status: .completed)
                stopTicking()
                audio.stop()
                // See `finishEarly`: this final snapshot is the terminal state, and sending
                // `.sessionEnded` after it would erase the only thing the watch has to draw.
                pushState(force: true)
            }
        }
    }
}

// MARK: - What the watch hears from this session

/// `currentMessage` is built rather than cached, so an answer is always the state *now*: the
/// same reason nothing in this file reads the clock twice. It is what the link sends when the
/// watch asks, so a request can never be answered from a stale snapshot.
extension SessionController: AdvertisedSession {

    var currentMessage: WatchMessage {
        .session(
            SessionSnapshot(
                planName: planName,
                intervals: engine.intervals,
                startedAt: engine.startedAt ?? .now,
                state: currentState
            )
        )
    }
}
