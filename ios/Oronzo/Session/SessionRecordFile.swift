import Foundation
import OronzoCore

/// The running session, as a file.
///
/// The phone writes it on every state change and reads it on launch, which is what lets it answer
/// the watch's "is a workout running?" with something it knows rather than something it happens to
/// be holding. Before this, that question was answered from a `weak` reference, so a relaunched
/// app answered "nothing is running" mid-workout — reproducing a cleared wrist in under a minute
/// on paired simulators, and matching the field report this exists to fix.
///
/// **Stateless on purpose.** Deliberately not an object holding a cached copy: the writer
/// (`SessionController`) and the reader (`PhoneConnectivity`) are different objects on the same
/// actor, and a cached value held by one of them is a second source of truth that can disagree
/// with the file. The same argument that keeps `SessionSnapshot` whole keeps this dumb.
///
/// Synchronous for the same reason. An `async` write would re-introduce write *ordering* — a save
/// that lands after the clear that followed it — which is the lesson the single-slot application
/// context already taught, at a smaller scale. The file is a few kilobytes and it is written when
/// the session changes, not on every tick.
///
/// See `PlanCache` in `PlanStore.swift` for the same shape, and `docs/known-issues.md` §4 for why
/// a decode failure here is logged rather than swallowed.
@MainActor
enum SessionRecordFile {

    /// A `let`, so it is computed once and is safe to share. It is also `@MainActor` with
    /// everything else here: the writer and the reader are both on the main actor, so pinning the
    /// file to it means a save and the read that follows it cannot interleave.
    private static let url: URL? = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("session-record.json")
    }()

    /// The session last written down, or `nil` when there is none — or none that can be read.
    ///
    /// **Those two are different facts and this cannot distinguish them to the caller**, which is
    /// why the failure is logged where it happens. In a debug build an unreadable record says so;
    /// in release `Log.debug` compiles out and it is silent, which is the standing hazard
    /// `docs/patterns.md` describes and the reason a mismatched build gets a visible banner
    /// rather than a log line.
    static func load() -> SessionRecord? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SessionRecord.self, from: data)
        } catch {
            Log.debug("session record: could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    static func save(_ record: SessionRecord) {
        guard let url, let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Forgets the session. Called when one genuinely ends — not when a view goes away mid-workout,
    /// which is not the same thing and used to be treated as if it were.
    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
