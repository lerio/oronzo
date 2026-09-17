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
    /// The Lock Screen surface, when the system allows one.
    private let activity = LiveSessionActivity()
    private var engine: ExecutionEngine
    private var ticker: Task<Void, Never>?
    private var lastCountdownSecond: Int?
    private var lastPushedState: SessionState?

    init(plan: Plan, exerciseNames: [UUID: String], audio: WorkoutAudio = WorkoutAudio()) {
        self.planID = plan.id
        self.planName = plan.name
        self.audio = audio
        self.engine = ExecutionEngine(
            intervals: PlanFlattener.flatten(plan, exerciseNames: exerciseNames)
        )

        link.onControl = { [weak self] control in
            self?.handle(control)
        }
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
    /// about what the state word is, when rest promotes what's next, or when `LAST` appears.
    /// Those rules are tested once, in `OronzoCore`, rather than implemented twice and left to
    /// drift — which is the whole reason the model lives there.
    ///
    /// Note the index: `position` above is 1-based because it is read by a person ("2 of 12"),
    /// while the model wants the engine's 0-based index.
    func screen(at now: Date) -> SessionScreen? {
        SessionPresentation.screen(
            intervals: engine.intervals,
            index: engine.currentIndex,
            end: engine.intervalEnd,
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
        link.setSessionActive(true)
        audio.start()
        // Deliberately ignoring the returned event: a beep the instant you press Start
        // would be noise, not information.
        _ = engine.start(at: .now)
        refreshClocks()
        startTicking()

        // The Lock Screen surface. Started *before* the first push, so there is an Activity for
        // that push to update rather than one created empty a moment later.
        if let content = activityContent() {
            activity.start(content)
        }

        // The watch gets the whole plan, so it can keep counting and buzzing even if this
        // phone goes quiet. Sent as part of every update — see SessionSnapshot for why.
        pushState(force: true)
    }

    /// What the Lock Screen needs: the shared model, plus the two facts that make the countdown
    /// *live* — an absolute end date, or a frozen remainder while paused.
    ///
    /// Deliberately current-plus-next only. The interval list belongs to the watch, whose
    /// transport is a single slot with no size ceiling; this one has a 4 KB limit and would throw.
    private func activityContent() -> SessionActivityContent? {
        screen(at: .now).map {
            SessionActivityContent(
                screen: $0,
                intervalEnd: engine.intervalEnd,
                remainingWhenPaused: engine.remainingWhenPaused
            )
        }
    }

    /// Called when the view goes away. Safe to call at any point.
    func teardown() {
        stopTicking()
        audio.stop()

        // Leaving the runner by swiping it away ends the session as far as the watch is
        // concerned, even though nothing was "finished". Harmless if it already ended.
        link.setSessionActive(false)
        // Unbind, or the next controller to install its own handler silently leaves this
        // dead one still receiving the watch's controls.
        link.onControl = nil
        activity.end()
        link.send(.sessionEnded)
    }

    func pause() {
        guard isRunning else { return }
        _ = engine.pause(at: .now)
        refreshClocks()
        pushState()
    }

    func resume() {
        guard isPaused else { return }
        _ = engine.resume(at: .now)
        refreshClocks()
        pushState()
    }

    /// Completes the current interval now — "done" on a rep set, "skip" on a timed one.
    func advance(skipped: Bool = false) {
        guard !isFinished else { return }
        handle(engine.advance(at: .now, skipped: skipped))
        refreshClocks()
        pushState()
    }

    func goBack() {
        guard !isFinished else { return }
        _ = engine.goBack(at: .now)
        refreshClocks()
        pushState()
    }

    /// Ends the session early. Everything not reached is recorded as such.
    func finishEarly() {
        guard !isFinished else { return }
        completed = engine.abandon(at: .now)
        stopTicking()
        audio.stop()
        // The Lock Screen surface ends here rather than showing `DONE`, which is the watch's —
        // a Lock Screen is for what is happening now, and a finished workout is not happening.
        activity.end()
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

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            // 10Hz: smooth enough for the countdown, fine for firing transitions promptly.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard isRunning else { return }
        handle(engine.tick(now: .now))
        refreshClocks()
        fireCountdownCue()
        // Only sends when something actually changed, so this is not 10 messages a second.
        pushState()
    }

    /// Tells the watch where the session is. Skipped when nothing has moved, since the tick
    /// runs ten times a second and the watch needs none of those.
    private func pushState(force: Bool = false) {
        let state = SessionState(
            currentIndex: engine.currentIndex,
            isPaused: isPaused,
            isFinished: isFinished,
            intervalEnd: engine.intervalEnd,
            remainingWhenPaused: engine.remainingWhenPaused,
            // Without this the watch computes the DONE total from its own clock and the number
            // climbs forever. Sent so the watch can freeze it at the real finish.
            finishedAt: engine.finishedAt
        )
        guard force || state != lastPushedState else { return }
        lastPushedState = state
        link.send(
            .session(
                SessionSnapshot(
                    planName: planName,
                    intervals: engine.intervals,
                    startedAt: engine.startedAt ?? .now,
                    state: state
                )
            )
        )

        // The Lock Screen tracks the same state through the same model, so the two cannot say
        // different things. It only speaks when something moved, which is the dedupe above.
        if let content = activityContent() {
            activity.update(content)
        }
    }

    private func handle(_ control: WatchControl) {
        switch control {
        case .next: advance()
        case .previous: goBack()
        case .togglePause: isPaused ? resume() : pause()
        case .finish: finishEarly()
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
                activity.end()
                // See `finishEarly`: this final snapshot is the terminal state, and sending
                // `.sessionEnded` after it would erase the only thing the watch has to draw.
                pushState(force: true)
            }
        }
    }
}
