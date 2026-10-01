import Foundation
import OronzoCore

/// The workouts Health is still owed, as a file.
///
/// **Deliberately not part of `session-record.json`**, although both are a few kilobytes in the
/// same directory. That record describes the workout *in flight*: it is cleared the moment the
/// runner is dismissed and it expires after six hours, because its job is to answer the watch and
/// to be resumed. This one describes what is *over* and unconfirmed, and its whole value is that
/// it outlives both of those moments — a session that ends with the phone locked is written here
/// on the way to bed and resolved the next morning. The two files have opposite lifetimes on
/// purpose; folding them together would tie the obligation to the session's teardown.
///
/// Stateless and synchronous for the reasons `SessionRecordFile` gives: the writer and the reader
/// are on the same actor, a cached copy would be a second source of truth, and an `async` write
/// would reintroduce write *ordering* into a file whose entries are the thing that must not be
/// lost. The file is a few hundred bytes per owed workout.
@MainActor
enum HealthOwedFile {

    private static let url: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("health-owed.json")
    }()

    /// What is owed as of now.
    ///
    /// **An empty ledger and no file are the same answer here** — unlike `SessionRecordFile`, where
    /// "no record" and "an unreadable record" are different facts worth telling apart. Nothing is
    /// owed until something writes an entry, so an absent file is not a missing ledger; and an
    /// unreadable one is logged rather than guessed at. What that costs is one session's write
    /// being attempted once instead of three times: durability degrades, the workout does not.
    static func load() -> HealthOwedLedger {
        guard let url, let data = try? Data(contentsOf: url) else { return HealthOwedLedger() }
        do {
            return try JSONDecoder().decode(HealthOwedLedger.self, from: data)
        } catch {
            Log.health("health: could not read \(url.lastPathComponent) — \(error); treating nothing as owed")
            return HealthOwedLedger()
        }
    }

    /// Writes the ledger, and **removes the file when nothing is owed** — so absence keeps meaning
    /// what it says, on a desk as much as in the code.
    static func save(_ ledger: HealthOwedLedger) {
        guard let url else { return }
        guard !ledger.entries.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(ledger) else {
            Log.health("health: could not encode the owed ledger; \(ledger.entries.count) workout(s) will not be retried")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.health("health: could not write \(url.lastPathComponent) — \(error); the write is not durable")
        }
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
