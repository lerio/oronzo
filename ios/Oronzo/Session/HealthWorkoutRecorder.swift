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
    /// Health accepted the workout.
    case written
    /// A real session, but under `RecordableWorkout.minimumDuration`.
    case tooShort
    case failed(String)
}

/// Why a write did not happen.
enum HealthWriteError: LocalizedError {
    /// No Health store here at all — an iPad, or a device without Health.
    case unavailable
    /// `finishWorkout()` returned no workout and no error. Treated as a failure rather than a
    /// silent success, because nothing was written either way.
    case notSaved

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health is not available on this device"
        case .notSaved: "Health returned no workout"
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
            Log.debug("health: no Health store on this device")
            return
        }
        // `start()` is re-run every time the runner reappears, so this has to be safe to call at
        // any time — including in the middle of a workout.
        guard !hasAsked else { return }
        hasAsked = true

        do {
            // Ask only when the system would actually raise a sheet. `.unnecessary` means the
            // question has already been answered — granted *or* denied — and this is what stops a
            // refusal being re-asked on every runner re-appearance.
            let status = try await store.statusForAuthorizationRequest(
                toShare: Self.writable,
                read: []
            )
            guard status == .shouldRequest else { return }

            try await store.requestAuthorization(toShare: Self.writable, read: [])
        } catch {
            // Not fatal and not worth a dialog: the workout simply will not be recorded. Note
            // that this says nothing about whether permission was *granted* — a refused request
            // succeeds here and is discovered at save time.
            Log.debug("health: the authorization request failed — \(error.localizedDescription)")
        }
    }

    /// Saves one finished workout, and throws if it was not saved.
    ///
    /// **There is no retry, however this fails.** A `finishWorkout` that threw wrote nothing — but
    /// a second attempt driven by a button is the one path that could plausibly double-write if a
    /// failure ever landed *after* the store had committed. One attempt per session is enforced by
    /// the caller, and the summary reports the outcome rather than offering to try again.
    func record(_ workout: RecordableWorkout) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthWriteError.unavailable }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // `HKWorkoutBuilder`, not `HKWorkout`'s convenience initialiser — every one of those has
        // been deprecated since iOS 17 in favour of this. Nothing is added to the builder: Oronzo
        // records how long you trained, not what your body did while you did it, and a workout
        // with no heart-rate and no energy samples is the honest shape of that.
        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: workout.startedAt)
        try await builder.endCollection(at: workout.finishedAt)
        // A nil workout with no error means nothing was written, so it is a failure rather than a
        // silent success. The single thing `.written` is allowed to mean is that the store handed
        // back a workout.
        guard try await builder.finishWorkout() != nil else { throw HealthWriteError.notSaved }

        Log.debug("health: recorded the workout ending \(workout.finishedAt)")
    }
}
