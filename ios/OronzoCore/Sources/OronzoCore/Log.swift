import Foundation

/// Debug-only console output, shared by both apps.
///
/// This exists because WatchConnectivity is the flakiest part of the system and it fails
/// *silently*: a workout that never reached the watch looks exactly like one that was never
/// started, and the deciding facts (is the session activated? is the watch reachable? is the
/// app installed?) are only visible from inside the process.
///
/// `debug` compiles to nothing in a release build — not even the string interpolation, since
/// the message is an autoclosure that is never invoked.
public enum Log {
    public static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Oronzo] \(message())")
        #endif
    }
}
