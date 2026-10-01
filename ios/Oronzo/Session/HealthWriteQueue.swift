import Foundation
import OronzoCore

/// The one place a workout is offered to Apple Health — the first attempt and every retry after it.
///
/// **Why a queue at all, when the write used to be four lines in the controller.** A retry and a
/// first attempt are the same operation with a different trigger, and splitting them would put the
/// metadata keys in two places and the settle rule in two more. It also gives the two facts that
/// keep a workout from being written twice somewhere to live: an in-flight set, so the launch hook
/// and the foreground hook cannot both be inside an attempt for the same entry, and the policy in
/// `HealthOwedEntry`, which already knows when an attempt is due.
///
/// **The permission sheet is not raised from here.** `prepare()` is called when a workout *starts*
/// and never again — the sheet needs the foreground, and a retry running at launch has no business
/// interrupting anyone. A retry with the permission revoked simply fails, spends an attempt, and
/// is reported for what it was.
@MainActor
final class HealthWriteQueue {

    /// One per app, for the in-flight set and for a single `HKHealthStore`. The state that matters
    /// is the ledger on disk, not this object — the same argument `SessionRecordFile` makes.
    static let shared = HealthWriteQueue()

    private let health = HealthWorkoutRecorder()

    /// Entries an attempt is in flight for.
    ///
    /// Not a substitute for the ledger: this only covers *this* process, and only the window
    /// between reading the ledger and settling it. What it stops is the launch hook and the first
    /// `.active` of the same launch — which fire within a second of each other — from both
    /// counting an attempt against the same entry.
    private var inFlight: Set<UUID> = []

    /// Told what became of an attempt, so a summary still on screen can correct its own line.
    ///
    /// Set by the session that created the entry, and filtered by id there — a retry that resolves
    /// an older workout, or a controller SwiftUI has since discarded, must not write to a screen
    /// that is showing something else.
    var onOutcome: ((UUID, HealthWriteOutcome) -> Void)?

    private init() {}

    /// Asks for permission to write workouts. See the type's note on when this may run.
    func prepare() async {
        await health.prepare()
    }

    /// Writes down that Health is owed this workout.
    ///
    /// **Synchronous and before any attempt exists**, which is the whole point: an app that dies
    /// between the end of a workout and the Health answer leaves the obligation behind rather than
    /// the loss. Called from `SessionController.complete`, which is the one place a session ends.
    func owe(_ entry: HealthOwedEntry) {
        var ledger = HealthOwedFile.load()
        ledger.insert(entry)
        HealthOwedFile.save(ledger)
        Log.health("health: owed the workout ending \(entry.finishedAt) — written down before it is offered")
    }

    /// Offers one owed workout to Health, if the ledger still holds it and policy allows.
    ///
    /// Returns `nil` when nothing was attempted — the entry is gone, is spent, was attempted
    /// moments ago, or another attempt is already in flight. That is not an error: it is the
    /// launch hook and the foreground hook agreeing about one workout.
    @discardableResult
    func resolve(_ id: UUID, at now: Date = .now) async -> HealthWriteOutcome? {
        guard !inFlight.contains(id) else { return nil }

        var ledger = HealthOwedFile.load()
        guard var entry = ledger.entry(id), entry.isRetryable(at: now) else { return nil }

        inFlight.insert(id)
        defer { inFlight.remove(id) }

        // **The version is taken before the attempt is counted, and both are saved before the call.**
        // That ordering is what survives a crash mid-write: the attempt is already spent and its
        // version already used, so the next process cannot hand the same version to a second save.
        // Spending an attempt that never reached Health costs one of three; reusing a version is
        // the one thing that could leave two workouts behind.
        let version = entry.nextVersion
        entry.recordAttempt(at: now)
        ledger.replace(entry)
        HealthOwedFile.save(ledger)

        Log.health("health: offering the workout ending \(entry.finishedAt) to Health (attempt \(entry.attempts) of \(HealthOwedEntry.maximumAttempts), version \(version))")

        let outcome: HealthWriteOutcome
        do {
            outcome = try await health.record(entry.workout, syncIdentifier: entry.id, version: version)
        } catch {
            // Only a thrown error is evidence that nothing was written — see `HealthWriteOutcome`.
            outcome = .failed(error.localizedDescription)
            Log.health("health: could not offer the workout — \(error.localizedDescription)")
        }

        settle(id, outcome: outcome, at: .now)
        onOutcome?(id, outcome)
        return outcome
    }

    /// Every entry that is due an attempt. Called at launch and when the app comes forward.
    ///
    /// The foreground is not a compromise hook for this — it is the precise one. The failure this
    /// exists for is a phone that was locked, and the cure is the phone being picked up, which is
    /// the moment `scenePhase` becomes `.active`.
    func resolveAll(at now: Date = .now) async {
        for entry in HealthOwedFile.load().retryable(at: now) {
            _ = await resolve(entry.id, at: now)
        }
    }

    /// Puts what Health said back into the ledger.
    ///
    /// Read, mutated and written with **no suspension in between**, so a settle cannot be
    /// interleaved with anything else touching the file.
    private func settle(_ id: UUID, outcome: HealthWriteOutcome, at now: Date) {
        var ledger = HealthOwedFile.load()
        let owed = ledger.entry(id)

        switch outcome {
        case .written:
            ledger.remove(id)
            Log.health("health: the owed ledger is settled — Health took it")

        case .unconfirmed, .failed:
            // Kept. The attempt was counted before the call; what is left to say is whether it was
            // the last one. **"Gave up" is not "it is not there"** — the app cannot tell those
            // apart, which is the entire reason this file exists.
            if let owed, owed.isSpent(at: now) {
                Log.health("health: gave up on the workout ending \(owed.finishedAt) after \(owed.attempts) attempts — the app cannot tell whether it reached Health")
            } else if let owed {
                Log.health("health: the workout ending \(owed.finishedAt) is still owed; it will be offered again when the phone is next awake")
            }

        case .tooShort, .notAttempted:
            // Unreachable: an entry only exists for a workout that cleared the three-minute bar,
            // and this only runs for an entry that was just attempted. Removed anyway, because an
            // entry that can never be written must not sit in the ledger for a month.
            ledger.remove(id)
        }

        ledger.prune(at: now)
        HealthOwedFile.save(ledger)
    }
}
