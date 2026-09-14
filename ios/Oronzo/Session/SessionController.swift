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
    private(set) var elapsed: TimeInterval = 0

    /// Set once the session ends — whether it ran its course or was stopped early.
    private(set) var completed: CompletedSession?

    private let audio: WorkoutAudio
    private var engine: ExecutionEngine
    private var ticker: Task<Void, Never>?
    private var lastCountdownSecond: Int?

    init(plan: Plan, exerciseNames: [UUID: String], audio: WorkoutAudio = WorkoutAudio()) {
        self.planID = plan.id
        self.planName = plan.name
        self.audio = audio
        self.engine = ExecutionEngine(
            intervals: PlanFlattener.flatten(plan, exerciseNames: exerciseNames)
        )
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

    // MARK: - Lifecycle

    func start() {
        guard engine.phase == .idle, !isEmpty else { return }
        audio.start()
        // Deliberately ignoring the returned event: a beep the instant you press Start
        // would be noise, not information.
        _ = engine.start(at: .now)
        refreshClocks()
        startTicking()
    }

    /// Called when the view goes away. Safe to call at any point.
    func teardown() {
        stopTicking()
        audio.stop()
    }

    func pause() {
        guard isRunning else { return }
        _ = engine.pause(at: .now)
        refreshClocks()
    }

    func resume() {
        guard isPaused else { return }
        _ = engine.resume(at: .now)
        refreshClocks()
    }

    /// Completes the current interval now — "done" on a rep set, "skip" on a timed one.
    func advance(skipped: Bool = false) {
        guard !isFinished else { return }
        handle(engine.advance(at: .now, skipped: skipped))
        refreshClocks()
    }

    func goBack() {
        guard !isFinished else { return }
        _ = engine.goBack(at: .now)
        refreshClocks()
    }

    /// Ends the session early. Everything not reached is recorded as such.
    func finishEarly() {
        guard !isFinished else { return }
        completed = engine.abandon(at: .now)
        stopTicking()
        audio.stop()
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
    }

    private func refreshClocks() {
        remaining = engine.remaining(at: .now)
        elapsed = engine.elapsed(at: .now)
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
            }
        }
    }
}
