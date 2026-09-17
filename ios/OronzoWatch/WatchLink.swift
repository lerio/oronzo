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

    private var session: WCSession?
    private var haptics: Task<Void, Never>?
    private var lastAnnouncedIndex: Int?
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
        lastAnnouncedIndex = nil
        lastCountdownSecond = nil
    }

    private func announce(now: Date) {
        guard let state, !state.isPaused, !state.isFinished, !intervals.isEmpty else { return }

        let (index, end) = position(at: now)

        if let previous = lastAnnouncedIndex, previous != index {
            WKInterfaceDevice.current().play(.notification)
            lastCountdownSecond = nil
        }
        lastAnnouncedIndex = index

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
}

#if DEBUG
extension WatchLink {
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
            Log.debug("could not decode an incoming message")
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
            startedAt = snapshot.startedAt
            lastAnnouncedIndex = nil
            startHaptics()

        case .sessionEnded:
            Log.debug("applied sessionEnded: clearing")
            stopHaptics()
            intervals = []
            state = nil
            planName = nil
            startedAt = nil
            lastAnnouncedIndex = nil
        }
    }
}
