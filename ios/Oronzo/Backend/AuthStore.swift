import Foundation
import OronzoCore
import Supabase

@MainActor
@Observable
final class AuthStore {

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private(set) var state: State = .loading
    private(set) var error: String?
    private(set) var isBusy = false

    /// The SDK persists the session in the keychain, so "restore" is asking it whether it still
    /// has one.
    ///
    /// **Whether a session is *stored* is the question — not whether a refresh succeeded.** This
    /// used to call `auth.session`, which refreshes when the token is stale and *throws* when that
    /// refresh fails, and every throw was read as "signed out". A dropped connection, a phone that
    /// just woke up, or one minute of no signal therefore looked exactly like a revoked account,
    /// and the sign-in screen appeared while the credentials sat untouched in the keychain. That
    /// is the "the session keeps getting lost" report: it was never lost, it just could not be
    /// renewed that second.
    ///
    /// So the keychain decides the state, and renewing is a best-effort follow-up whose failure is
    /// logged rather than acted on. If a request then turns out to be unauthorized, `PlanStore`
    /// says so in words the person can act on, and Sign out → sign in again is the way out — which
    /// is also the only thing that *should* clear a session.
    func restore() async {
        guard Backend.isConfigured else {
            state = .signedOut
            return
        }
        guard Backend.client.auth.currentSession != nil else {
            state = .signedOut
            return
        }

        state = .signedIn

        do {
            // Refreshes only if the token is stale; a no-op otherwise.
            _ = try await Backend.client.auth.session
        } catch {
            Log.debug("auth: could not renew the session at launch: \(error)")
        }
    }

    func signIn(email: String, password: String) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            _ = try await Backend.client.auth.signIn(email: email, password: password)
            state = .signedIn
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        try? await Backend.client.auth.signOut()
        state = .signedOut
    }
}
