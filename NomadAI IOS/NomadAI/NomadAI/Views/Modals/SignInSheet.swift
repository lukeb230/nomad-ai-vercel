//
//  SignInSheet.swift
//  Bottom sheet with Sign in with Apple primary + email/password fallback.
//
//  Auto-dismisses when AuthState.shared.isSignedIn flips to true (the
//  Supabase SDK's authStateChanges listener inside AuthState updates the
//  singleton, SwiftUI re-renders, .onChange fires dismiss).
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase

struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthState.shared

    enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Sign up"
    }

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking: Bool = false
    @State private var errorBanner: String? = nil
    @State private var infoBanner: String? = nil

    /// Raw nonce held across the SIWA round-trip; sha256 of this is sent to Apple,
    /// raw is forwarded to Supabase to verify the ID token.
    @State private var currentNonce: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let info = infoBanner {
                        InfoBanner(text: info)
                    }
                    if let err = errorBanner {
                        SignInErrorBanner(text: err) { errorBanner = nil }
                    }

                    appleButton
                    orDivider
                    emailForm
                }
                .padding(.horizontal, Spacing.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in to NomadAI").monoLabel()
            FrauncesEmphasis(prefix: "Sync trips ", italic: "across", suffix: " devices.", size: 22)
                .foregroundStyle(.fg)
            Text("Your saved spots, trips, and passport stamps stay in sync. Optional — the app works fine without an account.")
                .font(.body(13))
                .foregroundStyle(.muted)
                .lineSpacing(2)
        }
    }

    // MARK: - Apple

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            currentNonce = randomNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(currentNonce)
        } onCompletion: { result in
            handleAppleCompletion(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleIDCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorBanner = "Couldn't read Apple credential. Try again."
                return
            }
            let nonce = currentNonce
            Task {
                isWorking = true
                defer { isWorking = false }
                do {
                    _ = try await SupabaseService.shared.client.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: idToken,
                            nonce: nonce
                        )
                    )
                    // AuthState's listener will set session → onChange will dismiss.
                } catch {
                    errorBanner = "Apple sign-in failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            // User cancellation (.canceled) is silent.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorBanner = "Apple sign-in failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Or divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.line).frame(height: 1)
            Text("OR")
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.muted)
            Rectangle().fill(Color.line).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Email form

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bark))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))

                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bark))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))
            }

            Button(action: submitEmail) {
                HStack {
                    if isWorking {
                        ProgressView().tint(Color.clayInk)
                    } else {
                        Image(systemName: "envelope.fill")
                    }
                    Text(mode.rawValue)
                        .font(.body(14, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(Color.clayInk)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
            }
            .buttonStyle(.plain)
            .disabled(isWorking || !canSubmit)
            .opacity(canSubmit && !isWorking ? 1 : 0.6)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    private func submitEmail() {
        let e = email.trimmingCharacters(in: .whitespaces)
        Task {
            isWorking = true
            errorBanner = nil
            infoBanner = nil
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn:
                    _ = try await SupabaseService.shared.client.auth.signIn(email: e, password: password)
                    // listener → dismiss
                case .signUp:
                    let response = try await SupabaseService.shared.client.auth.signUp(email: e, password: password)
                    if response.session == nil {
                        // Email confirmation required.
                        infoBanner = "Check your email to confirm your account, then sign in."
                        mode = .signIn
                        password = ""
                    }
                    // If signUp returns a session immediately (email confirmation off), listener → dismiss.
                }
            } catch {
                errorBanner = humanError(error)
            }
        }
    }

    private func humanError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("Invalid login") { return "Email or password didn't match." }
        if msg.contains("already registered") || msg.contains("already exists") { return "That email is already registered. Try Sign in." }
        if msg.contains("rate") { return "Too many attempts. Wait a moment and try again." }
        return msg
    }

    // MARK: - Nonce helpers (standard SIWA pattern)

    private func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Banners (sheet-local)

private struct InfoBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.badge").font(.system(size: 12))
            Text(text).font(.body(12))
            Spacer()
        }
        .foregroundStyle(.fgDim)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line, lineWidth: 1))
    }
}

private struct SignInErrorBanner: View {
    let text: String
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12))
            Text(text).font(.body(12)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.muted)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.berry)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.berry.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.berry.opacity(0.4), lineWidth: 1))
    }
}
