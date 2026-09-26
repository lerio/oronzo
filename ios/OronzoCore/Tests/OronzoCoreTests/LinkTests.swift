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

    /// The undated clear still decodes, because a phone built before `idle(at:)` exists keeps
    /// sending it. The watch refuses to obey it against a live screen rather than refusing to read
    /// it — see `SessionClear`.
    func testSessionEndedRoundTrips() throws {
        let encoded = try WireCodec.encode(WatchMessage.sessionEnded)

        let decoded = try WireCodec.decode(WatchMessage.self, from: encoded)

        guard case .sessionEnded = decoded else {
            return XCTFail("sessionEnded came back as something else")
        }
    }

    /// **The date is the message.** A clear that came back without its instant would be
    /// indistinguishable from the undated one, on a build that believes it is safe to obey — so
    /// this asserts the value, not just the case.
    func testIdleRoundTripsWithItsDate() throws {
        let clearedAt = t0.addingTimeInterval(90)

        let encoded = try WireCodec.encode(WatchMessage.idle(at: clearedAt))
        let decoded = try WireCodec.decode(WatchMessage.self, from: encoded)

        guard case .idle(let back) = decoded else {
            return XCTFail("idle came back as something else")
        }
        XCTAssertEqual(back.timeIntervalSince1970, clearedAt.timeIntervalSince1970, accuracy: 0.001)
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

    /// `intensity` is the first field added to `Interval` since the wire existed, and this is the
    /// property that makes it safe: an *optional* field is decoded with `decodeIfPresent`, so a
    /// snapshot written before it existed still decodes, and a nil one is omitted from the JSON
    /// entirely — an older watch receives exactly the bytes it used to.
    func testAnIntervalWithNoIntensityDecodesAndEncodesAsItAlwaysDid() throws {
        let plain = WatchMessage.session(
            SessionSnapshot(planName: "P", intervals: [timed(0, 60)], startedAt: t0, state: runningState())
        )
        let encoded = try WireCodec.encode(plain)
        XCTAssertFalse(
            String(decoding: encoded, as: UTF8.self).contains("intensity"),
            "a nil intensity must not appear on the wire at all"
        )

        // And the tolerance in the other direction: a snapshot that *does* carry one, with the
        // key stripped, is what a phone running this build would send to an older watch.
        let withEffort = WatchMessage.session(
            SessionSnapshot(
                planName: "P",
                intervals: [Interval(
                    index: 0, kind: .exercise, name: "Burpee", mode: .time, duration: 20,
                    reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1,
                    blockRound: 1, blockRoundCount: 6, blockName: "HIIT", exerciseID: nil,
                    intensity: .hard
                )],
                startedAt: t0,
                state: runningState()
            )
        )
        let stripped = try JSONSerialization.data(
            withJSONObject: removing("intensity", from: try JSONSerialization.jsonObject(
                with: try WireCodec.encode(withEffort)
            ))
        )

        guard case .session(let back) = try WireCodec.decode(WatchMessage.self, from: stripped) else {
            return XCTFail("a snapshot without intensity came back as something else")
        }
        XCTAssertNil(back.intervals.first?.intensity)
        XCTAssertEqual(back.intervals.first?.name, "Burpee", "the rest of the interval survives")
    }

    // MARK: - Versioning

    /// **The assumption the entire compatibility story rests on, and the one nothing pinned.**
    ///
    /// Every tolerance test above *removes* a key an older build would not have sent. None of
    /// them proves the converse — that an older build, whose struct has no such property, ignores
    /// a key a newer one *added*. That is the direction that matters for `protocolVersion`: a
    /// watch built before the field existed has to skip it rather than fail.
    ///
    /// If this test ever fails, versioning on the wire is unsafe in the new-phone/old-watch
    /// direction and the field has to move somewhere else entirely.
    func testAnUnknownKeyInASnapshotIsIgnored() throws {
        let encoded = try WireCodec.encode(snapshot(runningState()))
        let withExtra = try JSONSerialization.data(
            withJSONObject: dict(adding: ["somethingFromAFutureBuild": 42],
                                 to: try JSONSerialization.jsonObject(with: encoded))
        )

        guard case .session(let back) = try WireCodec.decode(WatchMessage.self, from: withExtra) else {
            return XCTFail("a snapshot carrying an unknown key came back as something else")
        }
        XCTAssertEqual(back.intervals.count, 2, "a key from the future does not break the message")
    }

    /// A phone that predates versioning sends no version, and that must **not** be read as an
    /// unreadable message. The watch shows a screen and a note; it does not clear.
    func testASnapshotWithoutAProtocolVersionStillDecodes() throws {
        let encoded = try WireCodec.encode(snapshot(runningState()))
        let stripped = try JSONSerialization.data(
            withJSONObject: removing("protocolVersion", from: try JSONSerialization.jsonObject(with: encoded))
        )

        guard case .session(let back) = try WireCodec.decode(WatchMessage.self, from: stripped) else {
            return XCTFail("a snapshot from an older phone came back as something else")
        }
        XCTAssertNil(back.protocolVersion)
        XCTAssertEqual(back.intervals.count, 2, "and the workout it describes survives")
    }

    /// Absent when nil, so a message from this build is byte-for-byte what an older watch already
    /// receives — the same property `Interval.intensity` has.
    func testTheProtocolVersionIsAbsentWhenNilAndReadableWhenPresent() throws {
        let versioned = try WireCodec.encode(snapshot(runningState()))
        XCTAssertTrue(
            String(decoding: versioned, as: UTF8.self).contains("protocolVersion"),
            "this build stamps what it speaks"
        )

        let plain = WatchMessage.session(
            SessionSnapshot(planName: "P", intervals: [timed(0, 60)], startedAt: t0,
                            state: runningState(), protocolVersion: nil)
        )
        XCTAssertFalse(
            String(decoding: try WireCodec.encode(plain), as: UTF8.self).contains("protocolVersion"),
            "and says nothing at all when it has nothing to say"
        )
    }

    /// The mismatch rule. `nil` means the peer predates versioning entirely — which is not an
    /// error but is exactly what a stale build looks like, and is the most likely mismatch in the
    /// field because a re-sign can replace one app and not the other.
    func testAMismatchNamesItsDirection() {
        XCTAssertNil(WireProtocol.mismatch(WireProtocol.current))

        XCTAssertEqual(WireProtocol.mismatch(nil), .peerIsOlder, "an unversioned build is an old build")
        XCTAssertEqual(WireProtocol.mismatch(WireProtocol.minimum - 1), .peerIsOlder)
        XCTAssertEqual(WireProtocol.mismatch(WireProtocol.current + 1), .peerIsNewer)
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

    /// Adds keys at the top level only — the position a future build's new field would occupy.
    private func dict(adding additions: [String: Any], to value: Any) -> Any {
        guard var object = value as? [String: Any] else { return value }
        for (key, newValue) in additions { object[key] = newValue }
        return object
    }
}
