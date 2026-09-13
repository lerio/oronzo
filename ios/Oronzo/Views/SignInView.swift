import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                Text("Oronzo")
                    .font(.largeTitle.bold())
                Text("Sign in to load your plans")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 10))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
            }

            if let error = auth.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await auth.signIn(email: email, password: password) }
            } label: {
                if auth.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty || auth.isBusy)

            Spacer()
            Spacer()
        }
        .padding(24)
    }
}
