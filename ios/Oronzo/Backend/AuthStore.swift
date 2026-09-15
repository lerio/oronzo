import Foundation
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

    /// The SDK persists the session in the keychain, so "restore" is just asking it whether
    /// it still has one.
    ///
    /// `auth.session` rather than `auth.currentSession`: the latter is the raw cache and may
    /// hand back an expired token, which would show the signed-in UI and then fail every
    /// request. `session` refreshes when needed, and throws only when there is nothing to
    /// refresh.
    func restore() async {
        guard Backend.isConfigured else {
            state = .signedOut
            return
        }
        do {
            _ = try await Backend.client.auth.session
            state = .signedIn
        } catch {
            state = .signedOut
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
