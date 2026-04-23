//
//  LoginView.swift
//  Entry screen. Bypassed with a single tap in the skeleton — no real
//  auth, just flips the isAuthenticated flag in RootView.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.appTheme) private var theme
    var onSignIn: () -> Void

    @State private var email = "claude@example.com"
    @State private var password = "••••••••"

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 28) {
                Spacer()

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

                    Text("Welcome back, \(MockData.user.name.components(separatedBy: " ").first ?? "")")
                        .font(theme.font.body)
                        .foregroundStyle(theme.textSecondary)
                }

                VStack(spacing: 14) {
                    glassField(icon: "envelope.fill", placeholder: "Email", text: $email)
                    glassField(icon: "lock.fill", placeholder: "Password", text: $password, secure: true)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button(action: onSignIn) {
                        Text("Sign In")
                            .font(theme.font.titleCompact)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                    .fill(theme.accent)
                            )
                    }
                    Button {
                        onSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                            Text("Unlock with Face ID")
                        }
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                .fill(theme.surface)
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 4) {
                    Text("No account?")
                        .foregroundStyle(theme.textSecondary)
                    Button("Register") { onSignIn() }
                        .foregroundStyle(theme.accent)
                }
                .font(theme.font.body)
                .padding(.bottom, 32)
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
                else { TextField(placeholder, text: text) }
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
    LoginView(onSignIn: {})
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
