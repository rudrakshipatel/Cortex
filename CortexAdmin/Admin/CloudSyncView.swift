import SwiftUI

/// Admin sign-in for Supabase. Required before publishing content or
/// broadcasting emergencies to all users.
struct CloudSyncView: View {
    @EnvironmentObject var sb: SupabaseService
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if sb.isConfigured {
                    Label("Backend connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(CX.teal)
                } else {
                    Label("Not configured", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(CX.orange)
                }
            } footer: {
                if !sb.isConfigured {
                    Text("Add your Supabase URL and anon key in SupabaseConfig.swift, then rebuild.")
                }
            }

            if sb.isAdminSignedIn {
                Section("Signed in") {
                    Text(sb.adminEmail ?? "Admin")
                    Button(role: .destructive) { sb.signOut() } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } else {
                Section("Admin sign-in") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button { signIn() } label: {
                        HStack { if working { ProgressView() }; Text("Sign in").fontWeight(.semibold) }
                    }
                    .disabled(!sb.isConfigured || email.isEmpty || password.isEmpty || working)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(CX.orange) }
                }
            }
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signIn() {
        working = true; error = nil
        Task {
            do { try await sb.signIn(email: email, password: password); password = "" }
            catch { self.error = error.localizedDescription }
            working = false
        }
    }
}
