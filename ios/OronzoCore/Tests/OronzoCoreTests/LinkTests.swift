import XCTest
@testable import OronzoCore

/// The phone↔watch wire format, which had no test until now.
///
/// It is the one contract in this project with **no build-time check at all**: the two apps are
/// compiled from the same sources but installed separately, so a phone and a watch can be
/// different builds, and a mismatch shows up only as a watch that decodes nothing and sits on
/// "No workout". `docs/runbook.md` records that costing hours once. These tests pin the parts
/// that must not drift, and prove the decode tolerance that a persisted application context
/// depends on.
final class LinkTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func timed(_ index: Int, _ seconds: TimeInterval) -> Interval {
        Interval(
            index: index, kind: .exercise, name: "Work", mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil
        )
    }

    private func snapshot(_ state: SessionState) -> WatchMessage {
        .session(
            SessionSnapshot(
                planName: "Upper Body A",
                intervals: [timed(0, 60), timed(1, 30)],
                startedAt: t0,
                state: state
            )
        )
    }

    private func runningState() -> SessionState {
        SessionState(
            currentIndex: 1, isPaused: false, isFinished: false,
            intervalEnd: t0.addingTimeInterval(90), remainingWhenPaused: nil, finishedAt: nil
        )
    }

    // MARK: - The vocabulary

    /// The raw values *are* the wire format — the watch sends one as a string, and the phone
    /// looks it up. Renaming a case would rename the wire and silently break a paired watch
    /// running an older build, so the spelling is asserted rather than assumed.
    func testControlRawValuesAreTheWireFormat() {
        XCTAssertEqual(WatchControl.next.rawValue, "next")
        XCTAssertEqual(WatchControl.previous.rawValue, "previous")
        XCTAssertEqual(WatchControl.togglePause.rawValue, "togglePause")
        XCTAssertEqual(WatchControl.finish.rawValue, "finish")
        XCTAssertEqual(WatchControl.requestState.rawValue, "requestState")
    }

    /// The ask travels as a bare string in a dictionary, exactly as the watch's `send` builds
    /// it and the phone's delegate reads it back.
    func testRequestStateSurvivesTheTransportDictionary() {
        let payload: [String: Any] = ["control": WatchControl.requestState.rawValue]

        let raw = payload["control"] as? String

        XCTAssertEqual(raw.flatMap(WatchControl.init(rawValue:)), .requestState)
    }

    /// A control the phone does not know is ignored rather than misread — the path that lets a
    /// newer watch talk to an older phone.
    func testAnUnknownControlIsNotMisread() {
        XCTAssertNil(WatchControl(rawValue: "somethingNewer"))
    }

    // MARK: - The snapshot

    /// What the watch is sent is always whole: the plan *and* the position. Asserted because
    /// the application context holds one message and no more — see `SessionSnapshot`.
    func testASnapshotRoundTripsWhole() throws {
        let message = snapshot(runningState())

        let encoded = try WireCodec.encode(message)
        let decoded = try WireCodec.decode(WatchMessage.self, from: encoded)

        guard case .session(let back) = decoded else {
            return XCTFail("a session snapshot came back as something else")
        }
        XCTAssertEqual(back.planName, "Upper Body A")
        XCTAssertEqual(back.intervals.count, 2, "the plan travels with the position, never apart from it")
        XCTAssertEqual(back.startedAt, t0)
        XCTAssertEqual(back.state, runningState())
    }

    func testSessionEndedRoundTrips() throws {
        let encoded = try WireCodec.encode(WatchMessage.sessionEnded)

        let decoded = try WireCodec.decode(WatchMessage.self, from: encoded)

        guard case .sessionEnded = decoded else {
            return XCTFail("sessionEnded came back as something else")
        }
    }

    // MARK: - Tolerance

    /// A context written by a build that predates `finishedAt` must still be readable.
    ///
    /// The application context persists across launches, so a newer watch can wake to a
    /// snapshot an older phone wrote. A synthesised decoder would reject it for the absent key
    /// and the watch would show nothing at all — which is why `SessionState` decodes by hand.
    func testAStateWithoutFinishedAtStillDecodes() throws {
        let older = Data(#"{"currentIndex":0,"isPaused":false,"isFinished":false}"#.utf8)

        let state = try WireCodec.decode(SessionState.self, from: older)

        XCTAssertEqual(state.currentIndex, 0)
        XCTAssertNil(state.finishedAt, "absent rather than a decode failure")
    }

    /// The same tolerance, one level up: a whole message from an older build.
    ///
    /// The key is stripped from a freshly-encoded message rather than hand-written, so this
    /// does not encode a guess about how the message nests — it removes exactly the field an
    /// older build would not have sent.
    func testASnapshotWithoutFinishedAtStillDecodes() throws {
        let encoded = try WireCodec.encode(snapshot(runningState()))
        let stripped = try JSONSerialization.data(
            withJSONObject: removing("finishedAt", from: try JSONSerialization.jsonObject(with: encoded))
        )

        let decoded = try WireCodec.decode(WatchMessage.self, from: stripped)

        guard case .session(let back) = decoded else {
            return XCTFail("a snapshot from an older build came back as something else")
        }
        XCTAssertNil(back.state.finishedAt)
        XCTAssertEqual(back.intervals.count, 2, "the plan survives a field it never knew about")
    }

    /// Drops a key wherever it appears in a JSON tree.
    private func removing(_ key: String, from value: Any) -> Any {
        if var object = value as? [String: Any] {
            object.removeValue(forKey: key)
            return object.mapValues { removing(key, from: $0) }
        }
        if let array = value as? [Any] {
            return array.map { removing(key, from: $0) }
        }
        return value
    }
}
