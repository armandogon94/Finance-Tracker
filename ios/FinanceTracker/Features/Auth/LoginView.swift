//
//  LoginView.swift
//  Entry screen. Calls AuthService.signIn / register, which reads
//  JWT tokens, persists them to Keychain, and flips the
//  AuthService.status → .signedIn so RootView swaps to the tab bar.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AuthService.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var isWorking = false

    enum Mode: String, Hashable { case signIn, register }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 28) {
                Spacer()

                header

                VStack(spacing: 14) {
                    glassField(icon: "envelope.fill", placeholder: "Email", text: $email)
                    glassField(icon: "lock.fill", placeholder: "Password (min 6)", text: $password, secure: true)
                }
                .padding(.horizontal, 24)

                if let err = auth.lastError?.errorDescription {
                    Text(err)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.negative)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    Button(action: submit) {
                        HStack {
                            if isWorking {
                                ProgressView().tint(.black).padding(.trailing, 4)
                            }
                            Text(mode == .signIn ? "Sign In" : "Create Account")
                                .font(theme.font.titleCompact)
                        }
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                .fill(canSubmit ? theme.accent : theme.accent.opacity(0.4))
                        )
                    }
                    .disabled(!canSubmit)

                    Button {
                        mode = mode == .signIn ? .register : .signIn
                    } label: {
                        Text(mode == .signIn ? "Don't have an account? Register"
                                             : "Already have an account? Sign in")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.accent.opacity(0.25))
                    .frame(width: 88, height: 88)
                Image(systemName: "dollarsign")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
            }
            .shadow(color: theme.accent.opacity(0.5), radius: 30)

            Text("Finance Tracker")
                .font(theme.font.largeTitle)
                .foregroundStyle(theme.textPrimary)

            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var canSubmit: Bool {
        !isWorking
            && email.contains("@")
            && password.count >= 6
    }

    private func submit() {
        isWorking = true
        Task {
            let ok: Bool
            switch mode {
            case .signIn:
                ok = await auth.signIn(email: email, password: password)
            case .register:
                ok = await auth.register(email: email, password: password, displayName: nil)
            }
            isWorking = false
            if !ok {
                // lastError is already set by AuthService; view will redraw.
            }
        }
    }

    private func glassField(icon: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 20)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text).keyboardType(.emailAddress) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(theme.font.body)
            .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview("Login — Liquid Glass") {
    LoginView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
