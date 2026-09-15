import Foundation
import OronzoCore
import WatchConnectivity
import WatchKit

/// The watch's half of the link to the phone.
///
/// The phone sends the whole plan once, at the start, and then only position updates. That
/// is what lets the countdown and the haptics keep working while the phone is out of range
/// or asleep: `WatchProjection` walks the interval list forward from the last thing the
/// phone said, and the next message re-anchors it.
@MainActor
@Observable
final class WatchLink: NSObject {

    private(set) var planName: String?
    private(set) var intervals: [Interval] = []
    private(set) var state: SessionState?
    private(set) var isReachable = false

    private var session: WCSession?
    private var haptics: Task<Void, Never>?
    private var lastAnnouncedIndex: Int?
    private var lastCountdownSecond: Int?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
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
        guard let session, session.activationState == .activated else { return }
        guard let data = session.receivedApplicationContext["message"] as? Data else {
            print("[Oronzo watch] refresh: nothing stored yet")
            return
        }
        print("[Oronzo watch] refresh: applying stored context")
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

        planName = plan.name
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
        // `[String: Any]` is not Sendable, so the message is pulled out as Data — which is —
        // before hopping to the main actor. Same reason every other callback here does it.
        let reachable = session.isReachable
        let data = session.receivedApplicationContext["message"] as? Data

        Task { @MainActor in
            self.isReachable = reachable
            // Whatever the phone last said, even if it said it while this app was closed.
            if let data { self.apply(data) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
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
            print("[Oronzo watch] could not decode an incoming message")
            return
        }

        switch message {
        case .session(let snapshot):
            // Concise on purpose: printing the message itself dumps every interval.
            print("[Oronzo watch] session: \(snapshot.intervals.count) intervals, at \(snapshot.state.currentIndex)")
            // Always complete, so it does not matter whether this is the first message the
            // watch has seen or the hundredth.
            planName = snapshot.planName
            intervals = snapshot.intervals
            state = snapshot.state
            lastAnnouncedIndex = nil
            startHaptics()

        case .sessionEnded:
            print("[Oronzo watch] session ended")
            stopHaptics()
            intervals = []
            state = nil
            planName = nil
            lastAnnouncedIndex = nil
        }
    }
}
