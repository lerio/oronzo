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

    /// The SDK persists the session (and refreshes the token) in the keychain, so
    /// "restore" is just asking it whether it still has a valid one.
    func restore() async {
        guard Backend.isConfigured else {
            state = .signedOut
            return
        }
        do {
            _ = try await Backend.client.auth.currentSession
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
