import Foundation
import HealthKit
import OronzoCore

/// What became of a session's Apple Health write. Read by the summary.
///
/// **It claims only what the store confirmed.** Oronzo asks for write-only access, so it can never
/// read its own sample back — `.written` therefore means "Health accepted the workout", which is
/// the strongest true statement available, and *not* "it is in the Fitness app".
enum HealthWriteOutcome: Equatable, Sendable {
    /// Nothing was attempted: no session has ended, or this launch is a fixture.
    case notAttempted
    /// The store handed the workout back. The strongest thing this app can know.
    case written
    /// **Not refused, and not confirmed.** `finishWorkout()` returned no workout and no error.
    ///
    /// Apple documents that pair as *"finishing the workout succeeded but the workout sample is not
    /// available because the device is locked"* — which is this app's ordinary case, since a
    /// session usually ends with the phone in a pocket.
    ///
    /// **Observed on a device, 28 September 2026.** A session ended with the phone locked reported
    /// this outcome, and the workout *was* in Apple Health. So for this app the documented reading
    /// holds and the save happened.
    ///
    /// **Observed the other way on 30 September 2026**, permission granted and everything else
    /// unchanged: a locked session reported this same outcome and the workout was *not* in Health.
    /// So the documented reading is not the whole story, and the app stopped pretending it could
    /// tell the two apart: the obligation is now written down and offered again when the phone is
    /// unlocked (`OronzoCore.HealthOwedEntry`, `HealthWriteQueue`), which converges on the right
    /// answer whichever one it was.
    ///
    /// The outcome stays separate from `.written` rather than collapsing into it, because the app
    /// still cannot tell the two apart from the inside: the same nil is reported in the field as a
    /// write that genuinely did not happen, and a build that claimed `.written` here would be lying
    /// in exactly the case worth being able to see. What it says on screen is "added, not
    /// confirmed" — which is now known to be the common truth, and would be visibly wrong if the
    /// rarer one ever occurred.
    case unconfirmed
    /// A real session, but under `RecordableWorkout.minimumDuration`.
    case tooShort
    case failed(String)
}

/// Why a write did not happen.
enum HealthWriteError: LocalizedError {
    /// No Health store here at all — an iPad, or a device without Health.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health is not available on this device"
        }
    }
}

/// Writes a finished workout into Apple Health, so it appears in the Fitness app.
///
/// **The decision of *whether* a session is worth recording is not here.** That lives in
/// `OronzoCore.RecordableWorkout`, where `swift test` can prove it on macOS in a second. This is
/// the part that needs a device, a permission prompt and an entitlement, and it does no thinking
/// of its own: it takes a workout that has already been decided on and hands it to the store.
///
/// Deliberately a plain `final class` with no protocol, no delegate and no state beyond the store.
/// A live `HKWorkoutSession` would be the other way to do this, and it is the wrong trade here:
/// it costs a delegate, interruption handling and session recovery, and it would make HealthKit's
/// builder a second authority on when the workout started and stopped. `docs/decisions.md` records
/// the choice.
@MainActor
final class HealthWorkoutRecorder {

    private let store = HKHealthStore()

    /// The one thing Oronzo writes.
    ///
    /// **Write-only, and workouts only.** Oronzo never reads anything back — it has no use for
    /// your health data — and it records no energy and no distance, because it measures neither.
    /// Anything more would be access it cannot justify to you.
    private static let writable: Set<HKSampleType> = [HKObjectType.workoutType()]

    /// Whether the sheet has been raised this launch.
    ///
    /// The first of the two things that make `prepare()` idempotent, and the cheaper one.
    private var hasAsked = false

    /// Asks for permission to write workouts — once, and only if there is still something to ask.
    ///
    /// **Called when a workout starts, not at launch.** The sheet is about the workout you are
    /// starting, which is the one moment it means anything; a permission prompt before you have
    /// done anything is exactly the nag that makes people deny it.
    ///
    /// Asking here rather than at save time is also the practical choice: the sheet needs the
    /// foreground, and at save time the phone may be in a pocket. Nothing needs to pause for it —
    /// every deadline in a session is an absolute date, so the countdown is simply correct when
    /// the sheet is dismissed.
    func prepare() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.health("health: no Health store on this device")
            return
        }
        // `start()` is re-run every time the runner reappears, so this has to be safe to call at
        // any time — including in the middle of a workout.
        guard !hasAsked else { return }
        hasAsked = true

        // **Logged before any decision, and that is the point of the line.** Everything below can
        // return without writing anything — a denied permission, a sheet already answered — and the
        // state that decides which is otherwise invisible: a session that was never recorded looks
        // exactly like one whose write failed, from every screen and every other log line. This is
        // the one fact that separates "Health refused" from "Health was never asked".
        Log.health("health: write authorization is \(Self.describe(authorizationStatus))")

        do {
            // Ask only when the system would actually raise a sheet. `.unnecessary` means the
            // question has already been answered — granted *or* denied — and this is what stops a
            // refusal being re-asked on every runner re-appearance.
            let status = try await store.statusForAuthorizationRequest(
                toShare: Self.writable,
                read: []
            )
            guard status == .shouldRequest else {
                Log.health("health: no sheet to raise; authorization is \(Self.describe(authorizationStatus))")
                return
            }

            try await store.requestAuthorization(toShare: Self.writable, read: [])
            Log.health("health: the sheet was answered; authorization is now \(Self.describe(authorizationStatus))")
        } catch {
            // Not fatal and not worth a dialog: the workout simply will not be recorded. Note
            // that this says nothing about whether permission was *granted* — a refused request
            // succeeds here and is discovered at save time.
            Log.health("health: the authorization request failed — \(error.localizedDescription)")
        }
    }

    /// What the store says about writing workouts, in words.
    ///
    /// Readable without raising anything, which is what makes it usable in a log line: it is the
    /// answer to "is this app allowed to record at all", and the one thing a record that never
    /// happened cannot be distinguished from without it.
    private var authorizationStatus: HKAuthorizationStatus {
        store.authorizationStatus(for: HKObjectType.workoutType())
    }

    private static func describe(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not determined (the sheet has not been answered)"
        case .sharingDenied: "DENIED for writing"
        case .sharingAuthorized: "authorized for writing"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }

    /// Saves one finished workout under a **sync identifier**, so the same workout may be offered
    /// again without becoming two workouts.
    ///
    /// Throws when the store refused it, and otherwise reports what the store confirmed — which,
    /// for a locked phone, is nothing.
    ///
    /// **Two rules, and they are about different things.** Within one run of the app a session is
    /// offered **once**: a "Try again" button is the one control that could plausibly double-write
    /// if a failure ever landed *after* the store had committed, and `HealthWriteQueue` enforces
    /// that. Across runs, a workout that Health never confirmed **is** offered again, and that is
    /// safe for a reason that has nothing to do with the app: Apple's header for
    /// `HKMetadataKeySyncIdentifier` says a save *"will replace an existing HKObject with the same
    /// HKMetadataKeySyncIdentifier value if the new HKObject has a greater
    /// HKMetadataKeySyncVersion"*. `version` only ever climbs, so each attempt either creates the
    /// workout or replaces the previous identical copy — never a second one. The equal-version
    /// case is not documented, which is exactly why it is never relied on.
    @discardableResult
    func record(_ workout: RecordableWorkout, syncIdentifier: UUID, version: Int) async throws -> HealthWriteOutcome {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthWriteError.unavailable }

        // Stated at save time as well as at ask time, because the two can differ: a refusal made
        // between a session starting and ending would otherwise only show up as an opaque error
        // from the store.
        Log.health("health: saving \(Int(workout.finishedAt.timeIntervalSince(workout.startedAt)))s of work; authorization is \(Self.describe(authorizationStatus))")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // `HKWorkoutBuilder`, not `HKWorkout`'s convenience initialiser — every one of those has
        // been deprecated since iOS 17 in favour of this. No *samples* are added to the builder:
        // Oronzo records how long you trained, not what your body did while you did it, and a
        // workout with no heart-rate and no energy samples is the honest shape of that.
        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: workout.startedAt)

        // The two keys that make a second attempt safe rather than a second workout. Bridged to
        // `NSString`/`NSNumber` because that is what HealthKit's header documents each key as
        // expecting — this dictionary is its own `NSDictionary<NSString *, id>`, not a Swift one.
        try await builder.addMetadata([
            HKMetadataKeySyncIdentifier: syncIdentifier.uuidString as NSString,
            HKMetadataKeySyncVersion: NSNumber(value: version),
        ])

        try await builder.endCollection(at: workout.finishedAt)

        // Only a thrown error is evidence that nothing was written. See `HealthWriteOutcome`
        // for why a `nil` here is reported as unconfirmed rather than as either answer.
        let finished = try await builder.finishWorkout()

        if finished == nil {
            Log.health("health: finished the workout; the store returned no object (locked device, or a write that did not happen — see HealthWriteOutcome.unconfirmed)")
            return .unconfirmed
        }

        Log.health("health: recorded the workout ending \(workout.finishedAt) (version \(version))")
        return .written
    }
}
