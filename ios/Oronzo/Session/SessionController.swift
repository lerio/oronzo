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

    /// What became of this session's Apple Health write, for the summary to report.
    ///
    /// Observed rather than returned, because the write outlives the moment the session ends: the
    /// summary is already on screen by the time Health answers, so this is what lets the line fill
    /// in when it does.
    private(set) var healthWrite: HealthWriteOutcome = .notAttempted

    /// Whether this session writes itself down. False only for the `-demoSession` fixture, which
    /// must never leave a record behind: a demo record would be picked up by the next real launch
    /// and resume a workout nobody started, which is a new and worse flavour of the confusion this
    /// whole file is trying to remove.
    private let persistsRecord: Bool

    /// Whether this session may leave a trace in **Apple Health**.
    ///
    /// Deliberately a second flag rather than a reuse of `persistsRecord`, because the two answers
    /// differ for exactly one fixture. `-demoRecord` sets `persistsRecord` — it exists to exercise
    /// *resume* — and it runs `DemoPlan.make()`, a full-length plan that clears the three-minute
    /// bar comfortably. Under one flag, a debug launch would deposit a workout nobody did into
    /// real Apple Health, where it outlives the phone and has to be deleted by hand.
    ///
    /// Read it as: *nobody did this workout, so nothing about it belongs in Health.*
    private let recordsHealth: Bool

    private let audio: WorkoutAudio
    private let health: HealthWorkoutRecorder

    /// Whether this session's outcome has already been offered to Health.
    ///
    /// Both places `completed` is set are single-shot by construction — each sits behind a
    /// `!isFinished` guard, and the engine emits `.finished` once. This is what makes that an
    /// invariant rather than a fact about today's call sites, in the spirit of the file's other
    /// cheap guards.
    private var hasWrittenToHealth = false

    private let link = PhoneConnectivity.shared
    private var engine: ExecutionEngine
    private var ticker: Task<Void, Never>?
    private var lastCountdownSecond: Int?
    private var lastPushedState: SessionState?

    init(
        plan: Plan,
        exercises: [UUID: ExerciseInfo],
        audio: WorkoutAudio = WorkoutAudio(),
        health: HealthWorkoutRecorder = HealthWorkoutRecorder(),
        persistsRecord: Bool = true,
        recordsHealth: Bool = true
    ) {
        self.planID = plan.id
        self.planName = plan.name
        self.audio = audio
        self.health = health
        self.engine = ExecutionEngine(
            intervals: PlanFlattener.flatten(plan, exercises: exercises)
        )
        self.persistsRecord = persistsRecord
        self.recordsHealth = recordsHealth
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

    /// Picks up a workout the phone was already in the middle of.
    ///
    /// Fails when the record cannot describe a real session — see `ExecutionEngine.init?(restoring:)`,
    /// which refuses rather than half-applying. A refused restore means the plan list, which is a
    /// worse screen than a resumed runner and a far better one than a runner driving nonsense.
    ///
    /// **Nothing here starts anything.** The restored controller is handed to the runner, and its
    /// `start()` finds the engine already running and takes the `reassert` path — which is the same
    /// path a reappearing runner takes, and deliberately so: a resumed session and a re-asserted one
    /// need exactly the same things done to them.
    ///
    /// Note what is **not** done here. Nothing claims the link, starts audio, or touches the watch:
    /// this is a constructor, and `SessionController.init` has been side-effect-free since the
    /// `@State(initialValue:)` trap — SwiftUI builds these on every re-render, so anything done here
    /// is done to a copy that is about to be discarded.
    init?(
        restoring record: SessionRecord,
        audio: WorkoutAudio = WorkoutAudio(),
        health: HealthWorkoutRecorder = HealthWorkoutRecorder()
    ) {
        guard let engine = ExecutionEngine(restoring: record) else { return nil }
        self.planID = record.planID
        self.planName = record.planName
        self.audio = audio
        self.health = health
        self.engine = engine
        self.persistsRecord = true
        // A record on disk is a real workout by definition — the demo fixtures are the only thing
        // that writes one and `-demoRecord` is the only demo that does, but a *restored* session
        // is one that was already running when the app went away, so it is always real.
        self.recordsHealth = true
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
        guard !isEmpty else { return }

        // **A runner reappearing onto a session already in flight is not a new workout.**
        //
        // This used to open with `guard engine.phase == .idle`, *before* the claim and before the
        // push — and that ordering was a whole failure on its own. `teardown()` (which SwiftUI
        // calls from `onDisappear`, on occasions that are not "the user left the workout") sends
        // `.sessionEnded`; `onAppear` then calls this again on the *same* controller, whose phase
        // is already `.running`. The guard returned, so nothing re-claimed the link, nothing
        // restarted the ticker or the audio, and nothing ever told the watch again: the phone drew
        // a perfect workout while the wrist read **"No workout"** with dead controls, for the rest
        // of the session. It needs no crash, no relaunch and no stale build.
        if engine.phase != .idle {
            reassert()
            return
        }

        // From here until the session ends, this controller *is* what the watch is being told
        // about — and it is refused if a live session already holds the link. A refused controller
        // is inert on purpose: it is either a SwiftUI re-render's discarded copy or a genuine
        // second runner, and in neither case may it move the wrist. Logged, because it means
        // something upstream is building a runner it does not install.
        guard link.claim(self) else {
            Log.debug("refused to start a second session while one is live")
            return
        }
        // Named, because *which* controller is running the workout is what every failure in this
        // file comes down to — there is more than one of these alive at a time, by SwiftUI's doing
        // rather than by design, and from the outside they are indistinguishable.
        Log.debug("session: started by \(ObjectIdentifier(self))")
        audio.start()
        // After the claim, so a controller the link refused — a SwiftUI re-render's discarded
        // copy — never raises a permission sheet over a workout it is not running.
        requestHealthAuthorization()
        // Deliberately ignoring the returned event: a beep the instant you press Start
        // would be noise, not information.
        _ = engine.start(at: .now)
        refreshClocks()
        startTicking()

        // The watch gets the whole plan, so it can keep counting and buzzing even if this
        // phone goes quiet. Sent as part of every update — see SessionSnapshot for why.
        pushState(force: true)
    }

    /// Takes the link back for a session that never stopped, and tells the watch where it is.
    ///
    /// Everything here is idempotent — the audio has its own guard, `rearmTicking` refuses when
    /// the session is paused, and the push is forced so the dedupe cannot swallow it. That is the
    /// point: this runs on a path SwiftUI can take at any time, so it has to be safe to run at
    /// any time, including when nothing was actually wrong.
    private func reassert() {
        // A finished session has nothing to re-assert. The summary is on screen and the watch has
        // its terminal snapshot; restarting the keep-alive here would hold the phone awake behind
        // a workout that is over.
        guard !isFinished else { return }

        guard link.claim(self) else {
            Log.debug("reassert refused: another session holds the link")
            return
        }
        Log.debug("session: re-asserted by \(ObjectIdentifier(self))")
        // The keep-alive is the phone's only claim on staying awake, and without it the phone is
        // suspended and cannot hear the watch at all.
        audio.start()
        // A resumed session skipped `start()`'s opening path, so this is the other place a
        // workout can begin without having been asked. Cheap: the ask is idempotent.
        requestHealthAuthorization()
        rearmTicking()
        pushState(force: true)
    }

    /// Called when the view goes away. Safe to call at any point.
    ///
    /// **A runner going away is not a workout ending**, and the difference is the whole of it:
    /// this used to stop the audio, stop the clock and wipe the watch unconditionally, so any
    /// spurious `onDisappear` took a live session apart. Now it acts only on a session that has
    /// genuinely finished, and a live one is left exactly as it was — still ticking, still on the
    /// wrist — for `start()` to re-assert if the runner comes back.
    func teardown() {
        guard isFinished else {
            Log.debug("teardown: the session is still live; the watch and the record are left alone")
            return
        }

        stopTicking()
        audio.stop()
        // The workout is over and its history is written, so there is nothing left to be durable
        // about. Clearing this is what stops a finished session from answering the watch forever.
        SessionRecordFile.clear()

        // `resign` refuses if a newer session has already advertised itself, which is the case
        // that must not clear: a re-created runner would otherwise hand the watch a session and
        // then erase it. Harmless if the session already ended.
        if link.resign(self) {
            // Dated, so a watch that is somehow still showing this session can tell this clear
            // from one that predates it — and, more to the point, so a clear that predates a
            // *newer* session cannot erase it. See `SessionClear`.
            link.send(.idle(at: .now))
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
        complete(with: engine.abandon(at: .now))
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

                // **`.rest` parks the loop; it never means "wait and look again".** See
                // `SessionSchedule.Wake` for why that distinction is written down rather than left
                // to the shape of a `guard`. Reaching `.rest` is not an error and needs no log —
                // it is the ordinary state of a rep set, a pause, or a session that has finished.
                guard case .at(let next) = self.nextWake() else { return }

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

    /// The next instant worth waking for, or `.rest` when nothing is due.
    ///
    /// **Four wakes per timed interval, and no more.** This used to also wake once a second for
    /// the whole of every timed interval, purely to repaint the on-screen clock from a stored
    /// remainder — because that was how the view drew it. The view draws its clock from a
    /// `TimelineView` now, so the clock costs no wakes at all, and the only instants left are the
    /// ones the session can actually change at. See `SessionRunner.runner` for the other half, and
    /// note what that half buys: a `TimelineView` stops when it is not on screen, so a phone
    /// locked in a pocket does *nothing* between those four instants instead of ticking ten
    /// thousand times an hour for a screen nobody is reading.
    private func nextWake() -> SessionSchedule.Wake {
        SessionSchedule.wake(
            after: .now,
            end: engine.intervalEnd,
            isPaused: isPaused,
            isFinished: isFinished,
            hasSession: !isEmpty
        )
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
        guard force || state != lastPushedState else { return }

        // **Written down before the link is consulted, and deliberately outside its guard.**
        //
        // The point of the record is that the phone knows what it is running. A controller the
        // link has refused is still running a real workout — it is the copy SwiftUI built and
        // discarded, or a second runner — and if the record were written only by the session that
        // holds the link, then the file would be silent in exactly the case it exists to cover.
        // Written here, the file follows the engine, and the link follows the file.
        if persistsRecord {
            SessionRecordFile.save(
                SessionRecord(engine: engine, planID: planID, planName: planName, savedAt: .now)
            )
        }

        guard link.isAdvertising(self) else {
            // Worth a line, because this is invisible from the outside: the wrist carries on
            // looking right whether it is being told or not.
            Log.debug("session: \(ObjectIdentifier(self)) is not the live session; the watch was not told")
            return
        }

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
                complete(with: engine.snapshot(status: .completed))
                stopTicking()
                audio.stop()
                // See `finishEarly`: this final snapshot is the terminal state, and sending
                // `.sessionEnded` after it would erase the only thing the watch has to draw.
                pushState(force: true)
            }
        }
    }

    // MARK: - Apple Health

    /// **The one place a session ends**, so a write that hangs off completion cannot be missed by
    /// a path added later.
    ///
    /// Both callers — `finishEarly` and the engine's `.finished` — go through here, and that is
    /// load-bearing rather than tidy. `SessionRunner.persist` has a **"Try again" button**
    /// (`SessionRunner.swift:473`) that re-runs itself whenever the Supabase write fails, so a
    /// Health write living beside it would post a second workout on every retry. Completing a
    /// session is engine-driven and happens exactly once; this is where that is made true.
    ///
    /// A session that finishes while the phone is in a pocket arrives here like any other, which
    /// is the point — only the authorization *sheet* needs the foreground, not the write.
    private func complete(with session: CompletedSession) {
        completed = session
        writeToHealth(session)
    }

    /// Hands a finished session to Apple Health, if it was a workout.
    ///
    /// Guarded on `recordsHealth` so no fixture ever reaches the store, and on
    /// `hasWrittenToHealth` so this is single-shot whatever calls it.
    private func writeToHealth(_ session: CompletedSession) {
        guard recordsHealth, !hasWrittenToHealth else { return }
        hasWrittenToHealth = true

        guard let workout = RecordableWorkout(completed: session) else {
            // A mis-tap, or a plan tapped through faster than three minutes. Reported rather than
            // hidden: the summary explains the absence, instead of leaving it to be guessed at.
            healthWrite = .tooShort
            Log.debug(
                "health: not recorded — \(Int(session.totalDuration.rounded()))s is under the \(Int(RecordableWorkout.minimumDuration))s minimum"
            )
            return
        }

        // Unstructured on purpose. The write has to outlive the screen that shows the summary —
        // the runner can be dismissed while it is still in flight — so this cannot be awaited by
        // whoever set `completed`. `healthWrite` is observed, so the line fills in when Health
        // answers, whenever that is.
        Task {
            do {
                try await health.record(workout)
                healthWrite = .written
            } catch {
                // The one state that means something went wrong on the phone rather than in the
                // rule, so it carries the reason rather than a bare failure.
                healthWrite = .failed(error.localizedDescription)
                Log.debug("health: could not write the workout — \(error.localizedDescription)")
            }
        }
    }

    /// Asks for permission to write workouts, the first time a real one starts.
    ///
    /// Idempotent at both ends — `hasAsked` in the recorder, and the store's own
    /// `statusForAuthorizationRequest` — which is what lets `reassert` call it unconditionally.
    private func requestHealthAuthorization() {
        guard recordsHealth else { return }
        Task { await health.prepare() }
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
