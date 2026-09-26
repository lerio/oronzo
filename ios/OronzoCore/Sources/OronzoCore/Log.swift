import Foundation
import os

/// Debug-only output, shared by both apps.
///
/// This exists because WatchConnectivity is the flakiest part of the system and it fails
/// *silently*: a workout that never reached the watch looks exactly like one that was never
/// started, and the deciding facts (is the session activated? is the watch reachable? is the
/// app installed?) are only visible from inside the process.
///
/// **It goes to the unified log as well as to the console, and that is what makes a phone or a
/// watch diagnosable without Xcode attached.** A bare `print` reaches the Xcode console and
/// nothing else: not the simulator's log, not a device's, not a sysdiagnose — so the evidence this
/// file exists to capture was unreachable exactly when it was needed. On 26 September 2026 that
/// cost an afternoon of adding statements to find a bug whose own log lines already said what was
/// wrong; they were simply invisible. Both destinations now, which costs nothing (the value is
/// still built only in a debug build) and means:
///
/// ```bash
/// log stream --device --predicate 'subsystem == "com.lerio.oronzo"'
/// ```
///
/// `debug` compiles to nothing in a release build — not even the string interpolation, since the
/// message is an autoclosure that is never invoked.
public enum Log {

    /// The subsystem every line is filed under, so a device's log can be filtered to this app's.
    public static let subsystem = "com.lerio.oronzo"

    private static let logger = Logger(subsystem: subsystem, category: "link")

    public static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        print("[Oronzo] \(text)")
        logger.debug("\(text, privacy: .public)")
        #endif
    }
}
