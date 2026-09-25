import Foundation
import OronzoCore
import WatchConnectivity
import WatchKit

/// The watch's half of the link to the phone.
///
/// The phone re-sends the **whole** session — plan and position together — on every change,
/// never a "start" followed by separate updates, because the application context is a single
/// slot and the last write is all that survives. That is what lets the countdown and the
/// haptics keep working while the phone is out of range or asleep: `WatchProjection` walks
/// the interval list forward from the last thing the phone said, and the next message
/// re-anchors it.
@MainActor
@Observable
final class WatchLink: NSObject {

    private(set) var intervals: [Interval] = []
    private(set) var state: SessionState?
    /// Retained for the `DONE` screen, which names the session that just finished. The snapshot
    /// has always carried it; the watch simply used to drop it on the floor.
    private(set) var planName: String?
    /// Likewise retained for `DONE`, which reports how long the session ran.
    private(set) var startedAt: Date?
    /// When the session ended, so `DONE` shows a frozen total rather than one that grows every
    /// time the screen redraws.
    private(set) var finishedAt: Date?

    /// Something the wrist should be told about that is not the workout itself.
    ///
    /// **Held as observable state rather than written to the log, and that is the whole point.**
    /// `Log.debug` is not merely unread in a release build — its `@autoclosure` is never evaluated
    /// (`docs/patterns.md`), so anything whose only trace is a log call does not exist in the
    /// field. A gym is not a console, and the failures this reports are ones a person can act on
    /// in one glance: update one app or the other.
    private(set) var note: String?

    private var session: WCSession?
    private var haptics: Task<Void, Never>?
    /// The bounded retry in flight. See `askForState`.
    private var ask: Task<Void, Never>?
    private var lastMoment: SessionMoment?
    private var lastCountdownSecond: Int?

    func activate() {
        guard WCSession.isSupported() else {
            Log.debug("watch: WCSession is not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        Log.debug("watch: activate() called")
    }

    /// Where the session should be now — the phone's position, projected forward through
    /// any timed intervals that have elapsed since it last spoke.
    func position(at now: Date) -> (index: Int, end: Date?) {
        guard let state else { return (0, nil) }

        // Paused: the phone is holding the clock, so nothing should move.
        if state.isPaused {
            return (state.currentIndex, state.remainingWhenPaused.map { now.addingTimeInterval($0) })
        }

        return WatchProjection.project(
            intervals: intervals,
            from: state.currentIndex,
            end: state.intervalEnd,
            now: now
        )
    }

    func interval(at index: Int) -> Interval? {
        intervals.indices.contains(index) ? intervals[index] : nil
    }

    /// Re-reads whatever the phone last sent.
    ///
    /// This is the fix for the obvious failure: with the wrist down the watch app is
    /// suspended, and a suspended app is not woken by WatchConnectivity. Raising the wrist
    /// *resumes* it rather than re-activating the session, so `activationDidComplete` does
    /// not fire again and nothing would ever tell it the phone had started a workout. The
    /// stored application context is still there — this just goes and looks.
    func refreshFromContext() {
        guard let session, session.activationState == .activated else {
            // Named separately rather than one silent `return`: "never activated" and "no
            // context stored yet" look identical from the wrist and have different causes.
            Log.debug("refresh: skipped (\(session == nil ? "no session" : "not activated"))")
            return
        }
        guard let data = session.receivedApplicationContext["message"] as? Data else {
            Log.debug("refresh: no stored context yet")
            return
        }
        apply(data)
    }

    /// Asks the phone what it is running, and keeps asking — **for a bounded while**.
    ///
    /// The watch used to have no way to say "I have nothing" — it could only wait to be told — so
    /// any push that never arrived left **"No workout"** on the wrist for the rest of the session,
    /// looking exactly like a phone that never started one. Recovery was added once, as a single
    /// best-effort shot per wrist raise, and a single shot is not a recovery: `sendMessage` is
    /// called with no error handler, so a message the phone was not ready for is dropped in
    /// silence, and there was nothing after it.
    ///
    /// Three things changed, and each closes a different hole:
    ///
    /// - **The stored context is read first.** It is local, it is durable, and reading it costs
    ///   nothing — so the cheapest possible recovery is tried before spending a message on one.
    /// - **The retry is bounded by `AskSchedule`**: four attempts at most, over about a minute.
    ///   `docs/decisions.md` rules out per-second traffic between these apps for reasons that cost
    ///   a battery to learn, so the bound is the feature rather than a limitation.
    /// - **The guard that suppressed the ask is gone.** It read
    ///   `session.isReachable || intervals.isEmpty` — which discards the durable channel for a
    ///   watch showing *stale non-empty intervals*, which is precisely the watch that needs to
    ///   ask. It was inverted for the case that matters.
    ///
    /// Cancelled the moment anything is applied, so a healthy link still costs exactly one ask.
    func askForState(reason: String) {
        refreshFromContext()

        guard let session else { return }
        ask?.cancel()

        Log.debug(
            "asking the phone for state (\(reason)); reachable=\(session.isReachable), "
            + "showing \(intervals.count) intervals"
        )

        let began = Date()
        ask = Task { [weak self] in
            for attempt in 1...AskSchedule.attemptCount {
                guard let self, !Task.isCancelled else { return }
                guard let due = AskSchedule.attempt(attempt, from: began) else { return }

                let delay = due.timeIntervalSinceNow
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }

                self.send(.requestState, asking: true)
            }
        }
    }

    /// The wrist went down, or the ask has been answered. Either way, stop.
    func stopAsking() {
        ask?.cancel()
        ask = nil
    }

    /// Sends a control to the phone.
    ///
    /// - Parameter asking: an ask is worth putting on the **durable** channel even when the phone
    ///   is in range, which is not true of a button press. A press that is dropped is recoverable
    ///   by pressing again; an ask that is dropped leaves the wrist wrong, and the failure being
    ///   covered is exactly the one where the phone looked ready and was not — its link not yet
    ///   activated, so `sendMessage` failed with nobody listening for the error.
    func send(_ control: WatchControl, asking: Bool = false) {
        guard let session else { return }

        var payload: [String: Any] = ["control": control.rawValue]
        // Tells the phone which build this is, so a mismatch can be named rather than guessed at.
        // An older phone ignores the key; an older *watch* never sends one, and that silence is
        // itself the signal — see `WireProtocol`.
        payload["protocolVersion"] = WireProtocol.current

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        if asking || !session.isReachable {
            // Queued for when the phone is next awake, rather than dropped.
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Haptics
    //
    // The watch does this itself rather than waiting to be told, because a buzz is exactly
    // what you need when you are not looking at either screen.

    /// Starts the cue loop, or re-anchors it if it is already running.
    ///
    /// **This used to wake four times a second for the whole session, and that is what cost the
    /// battery.** It sampled the projected position and asked whether anything had changed — but
    /// nothing here needs watching for, because every deadline is an absolute date the phone
    /// already sent. `SessionSchedule` says which instant is next, so the loop sleeps until it
    /// instead of asking 4,300 times an hour whether it has arrived. Measured on a 15-minute
    /// session: 80 wakes, against 3,600 for the poll (`SessionScheduleTests`).
    ///
    /// Restarting re-anchors, and never clears `lastMoment` — that memory is what distinguishes a
    /// transition from a first sighting, and losing it would silence the cue on the path that
    /// matters most.
    func startHaptics() {
        haptics?.cancel()
        haptics = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Announce first, then sleep: a snapshot arriving mid-interval has to buzz on
                // arrival rather than at the next boundary, and `announce` is idempotent — it
                // compares against `lastMoment` and `lastCountdownSecond` before playing.
                self.announce(now: .now)

                // **`.rest` parks the loop; it never means "wait and look again".** A rep interval,
                // a pause, a finished session and no session at all all land here, and parking is
                // right for every one of them because each is moved on by something outside this
                // loop that restarts it — `apply` on the next snapshot, or a wrist raise through
                // `syncRuntimeAndCues`. See `SessionSchedule.Wake`.
                guard case .at(let next) = self.nextWake() else { return }

                // Strictly after the moment it was asked about, so this is normally positive.
                // When it is not, the world moved in the gap: loop again, which re-reads the clock
                // and recomputes — it cannot spin, because the next answer is always ahead of the
                // newer `now`.
                let delay = next.timeIntervalSinceNow
                guard delay > 0 else { continue }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stopHaptics() {
        haptics?.cancel()
        haptics = nil
        lastMoment = nil
        lastCountdownSecond = nil
    }

    /// The next instant at which anything can happen, from wherever the session is now.
    ///
    /// There is no second term here, unlike the phone's: this surface draws its countdown from a
    /// `TimelineView`, so nothing needs waking to repaint a clock. That is the arrangement the
    /// *phone* adopted later, for the same reason — see `SessionRunner`'s timeline.
    func nextWake() -> SessionSchedule.Wake {
        let now = Date()
        let (_, end) = position(at: now)
        return SessionSchedule.wake(
            after: now,
            end: end,
            isPaused: state?.isPaused ?? false,
            isFinished: state?.isFinished ?? false,
            hasSession: !intervals.isEmpty
        )
    }

    private func announce(now: Date) {
        guard let state, !intervals.isEmpty else { return }

        let (index, end) = position(at: now)
        let kind = intervals.indices.contains(index) ? intervals[index].kind : .exercise
        let moment = SessionMoment(index: index, kind: kind, isFinished: state.isFinished)

        // The decision is `HapticLanguage`'s, not this file's — see there for why each
        // transition earned what it did. This only plays what it is handed.
        if let cue = HapticLanguage.cue(from: lastMoment, to: moment) {
            // Logged because a haptic is invisible to every tool we have: without this, "the
            // vocabulary never fired" and "it fired but you did not feel it" are the same
            // observation on a device. Same reasoning as the watch-link logging.
            Log.debug("cue: \(cue.rawValue) — \(kind) at index \(index)")
            play(cue)
            lastCountdownSecond = nil
        }
        lastMoment = moment

        // A paused session holds its clock, so there is no countdown to click through.
        guard !state.isPaused else { return }

        // Three clicks on the way into a transition, as on the phone.
        guard let end else { return }
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0, remaining <= 3 else {
            lastCountdownSecond = nil
            return
        }
        let second = Int(remaining.rounded(.up))
        guard second != lastCountdownSecond else { return }
        lastCountdownSecond = second
        WKInterfaceDevice.current().play(.click)
    }

    /// Turns a cue into a feel.
    ///
    /// The whole vocabulary rests on *count* rather than on different textures: `stop` and `start`
    /// are the same tap, played once or twice. That is deliberate — a tap you have felt a thousand
    /// times is recognisable immediately, and a second distinct texture would have to be learned.
    ///
    /// The texture is `.directionUp` rather than `.notification`, and that was calibrated on a
    /// wrist rather than chosen: `.notification` is Apple's *assertive* tap, and on a real workout
    /// it read as an alarm. A cue that tells you you may rest should feel like a nudge. The gap
    /// between the two taps went to 220ms for the same reason — at 180ms they blurred into one
    /// longer buzz, which loses the entire distinction the vocabulary is built on.
    private func play(_ cue: HapticCue) {
        switch cue {
        case .stop:
            WKInterfaceDevice.current().play(.directionUp)

        case .start:
            WKInterfaceDevice.current().play(.directionUp)
            Task { @MainActor in
                // Long enough to read as two taps, short enough to feel like one idea. Tuned
                // against a wrist: at 180ms they blurred together.
                try? await Task.sleep(for: .milliseconds(220))
                WKInterfaceDevice.current().play(.directionUp)
            }

        case .finished:
            // `.success` is the rising pattern — the payoff, and the one moment worth noticing.
            WKInterfaceDevice.current().play(.success)
        }
    }
}

#if DEBUG
extension WatchLink {
    /// Presses Next on a timer, so the watch→phone half of the link can be exercised without a
    /// second pair of hands.
    ///
    /// Launch with `-autoNext <seconds>`. It exists because the interesting failures in this
    /// direction — a control reaching a controller that is not the live session, or reaching
    /// nothing at all — cannot be produced by hand on a simulator, where the button cannot be
    /// tapped, and are tedious to reproduce on a wrist. Sends exactly what the button sends.
    func startAutoNext(everySeconds: Double) {
        guard everySeconds > 0 else { return }
        Log.debug("autoNext: pressing Next every \(everySeconds)s")
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(everySeconds))
                guard let self else { return }
                Log.debug("autoNext: sending .next")
                self.send(.next)
            }
        }
    }

    /// Seeds a session already in progress, so the screen can be looked at without a paired
    /// phone. Launch with `-demoSession`; debug builds only.
    func loadDemoSession() {
        let plan = Plan(
            name: "Demo",
            blocks: [
                PlanBlock(name: "Warm-up", steps: [
                    PlanStep(label: "Easy — 2 min", mode: .time, duration: 120),
                ]),
                PlanBlock(name: "Main work", steps: [
                    PlanStep(label: "Flat Dumbbell Bench Press", sets: 4, mode: .reps,
                             reps: 8, targetWeightKg: 20, restAfter: 90),
                ]),
            ]
        )

        // No exercise info at all: every step in this fixture carries a label, and nothing here is
        // two-sided. Passed explicitly rather than defaulted — see `PlanFlattener.flatten`.
        intervals = PlanFlattener.flatten(plan, exercises: [:])
        state = SessionState(
            currentIndex: 0,
            isPaused: false,
            isFinished: false,
            // Deliberately part-way through, so the countdown is doing something.
            intervalEnd: Date().addingTimeInterval(42),
            remainingWhenPaused: nil
        )
        // Started here too, or the demo would be silent: `apply` is what normally starts the
        // haptic loop, and a seeded session never goes through it. That made "the vocabulary
        // never fires" and "the demo has no haptics" the same observation — exactly the kind of
        // silent difference this project keeps having to dig out.
        startHaptics()
    }
}
#endif

extension WatchLink: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        // The watch's half of the phone's activation line. Without it, a watch whose session
        // never activated is indistinguishable from one that simply has nothing to show.
        //
        // No `isPaired` here: it is unavailable on watchOS (the build rejects it), which is
        // fine — from the watch the useful facts are whether the session came up at all and
        // whether a context is already sitting there.
        let hasStoredContext = session.receivedApplicationContext["message"] != nil
        Log.debug(
            "watch activation: state=\(activationState.rawValue) "
            + "storedContext=\(hasStoredContext) "
            + "error=\(error.map { String(describing: $0) } ?? "none")"
        )

        // `[String: Any]` is not Sendable, so the message is pulled out as Data — which is —
        // before hopping to the main actor. Same reason every other callback here does it.
        let data = session.receivedApplicationContext["message"] as? Data

        Task { @MainActor in
            Log.debug("watch activation: stored context present = \(data != nil)")
            // Whatever the phone last said, even if it said it while this app was closed.
            if let data { self.apply(data) }
            // And if there was nothing stored — or it would not decode — ask outright. A cold
            // launch does not necessarily produce a `scenePhase` *change*, so the ask the view
            // makes cannot be relied on to happen here; activation always completes.
            self.askForState(reason: "the link just came up")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["message"] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["message"] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }

    private func apply(_ data: Data) {
        guard let message = try? WireCodec.decode(WatchMessage.self, from: data) else {
            // The one failure that leaves no trace at all. A message that cannot be decoded is
            // almost always a wire shape this build does not know — the two apps are installed
            // separately and can be different builds — and the screen it leaves behind is the
            // idle one, which reads as "the phone never started a workout". Named here because
            // that ambiguity has cost hours before: see the stale-watch-app row in
            // `docs/runbook.md`.
            Log.debug("could not decode an incoming message — are both apps the same build?")
            // **And now said out loud.** This is the failure the runbook describes as the most
            // expensive in the project: a healthy phone, a wrist reading "No workout", and no
            // error message anywhere. A message this build cannot read means the phone is a
            // different build, which is a thing the person holding it can fix in a minute.
            note = "Can't read your iPhone — reinstall the Watch app"
            return
        }

        // Readable, so compare what it says it speaks. A phone that predates versioning sends no
        // version at all, and that is not an error to clear the screen over — the workout is still
        // perfectly drawable — so this sets a note and nothing else.
        if case .session(let snapshot) = message {
            switch WireProtocol.mismatch(snapshot.protocolVersion) {
            case .some(.peerIsOlder):
                note = "Update the iPhone app"
                Log.debug("the phone speaks an older wire protocol (\(snapshot.protocolVersion.map(String.init) ?? "none"))")
            case .some(.peerIsNewer):
                note = "Update the Watch app to match your iPhone"
                Log.debug("the phone speaks a newer wire protocol (\(snapshot.protocolVersion.map(String.init) ?? "none"))")
            case .none:
                note = nil
            }
        }

        // **Answered — stop asking.** This is the primary stopping condition of the retry, and the
        // one that fires in the healthy case: the first ask gets an answer, so a session that is
        // being pushed to costs exactly one extra message. See `askForState`.
        stopAsking()

        switch message {
        case .session(let snapshot):
            // Logged on success, not just failure: "the phone sent and the watch applied it"
            // is the single most useful fact when the wrist shows the wrong thing.
            Log.debug("applied session: \(snapshot.intervals.count) intervals, index=\(snapshot.state.currentIndex), finished=\(snapshot.state.isFinished)")
            // Always complete, so it does not matter whether this is the first message the
            // watch has seen or the hundredth.
            intervals = snapshot.intervals
            state = snapshot.state
            planName = snapshot.planName
            finishedAt = snapshot.state.finishedAt
            // Only a *new session* clears the memory of where we were.
            //
            // This used to clear on every snapshot, and that quietly disabled the transition cue
            // on the path that matters most: when the phone drives an interval change it pushes a
            // snapshot first, the memory was wiped, and the next observation looked like a first
            // sighting rather than a transition. So "rest is over, start working" only ever
            // buzzed when the phone was *silent* — the opposite of the common case.
            //
            // `startedAt` identifies the session, so a genuine restart still starts clean.
            if startedAt != snapshot.startedAt { lastMoment = nil }
            startedAt = snapshot.startedAt
            startHaptics()

        case .sessionEnded:
            Log.debug("applied sessionEnded: clearing")
            stopHaptics()
            intervals = []
            state = nil
            planName = nil
            startedAt = nil
            finishedAt = nil
            lastMoment = nil
        }
    }
}
