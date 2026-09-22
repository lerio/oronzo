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

    private var session: WCSession?
    private var haptics: Task<Void, Never>?
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

    /// Asks the phone what it is running.
    ///
    /// The watch used to have no way to say "I have nothing" — it could only wait to be told —
    /// so any push that never arrived left **"No workout"** on the wrist for the rest of the
    /// session, looking exactly like a phone that never started one. The phone now answers with
    /// the live session or with "nothing running", so the watch converges on the truth at every
    /// wake instead of the two silently disagreeing.
    ///
    /// Not a stream: one message per activation — a wrist raise — which is a different thing
    /// from the per-second traffic `docs/decisions.md` rules out. When the phone is out of
    /// range the ask is only worth queueing if there is nothing on screen to lose; otherwise
    /// the phone's own push, or the stored context on the next wake, already covers it.
    func askForState() {
        guard let session else { return }
        guard session.isReachable || intervals.isEmpty else { return }
        Log.debug(
            "asking the phone for state "
            + "(reachable=\(session.isReachable), showing \(intervals.count) intervals)"
        )
        send(.requestState)
    }

    func send(_ control: WatchControl) {
        guard let session else { return }
        let payload: [String: Any] = ["control": control.rawValue]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            // Queued for when the phone is next awake, rather than dropped.
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Haptics
    //
    // The watch does this itself rather than waiting to be told, because a buzz is exactly
    // what you need when you are not looking at either screen.

    func startHaptics() {
        haptics?.cancel()
        haptics = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.announce(now: .now)
            }
        }
    }

    func stopHaptics() {
        haptics?.cancel()
        haptics = nil
        lastMoment = nil
        lastCountdownSecond = nil
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

        intervals = PlanFlattener.flatten(plan)
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
            self.askForState()
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
            return
        }

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
