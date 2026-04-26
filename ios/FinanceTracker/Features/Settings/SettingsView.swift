//
//  SettingsView.swift
//  Slice 5: real Settings surface — Account (read from AuthService.currentUser),
//  Appearance (D1 ↔ D5 picker via ThemeStore), About (version/build), Sign Out.
//
//  Themes outside this slice (OCR mode, biometric lock, Telegram linking,
//  data export) are deliberately removed — they were placeholder mocks.
//  They will return as their own slices once each feature lands for real.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(ThemeStore.self) private var themeStore

    @State private var showSignOutAlert = false
    @State private var themeStamp = 0
    @State private var signOutWarnStamp = 0
    @State private var signOutDoneStamp = 0

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    accountCard
                    appearanceCard
                    aboutCard
                    signOutButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Sign out of Finance Tracker?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                auth.signOut()
                signOutDoneStamp += 1
            }
        } message: {
            Text("Your saved data stays on the server. You'll need to sign back in to view it.")
        }
        .sensoryFeedback(.selection, trigger: themeStamp)
        .sensoryFeedback(.warning, trigger: signOutWarnStamp)
        .sensoryFeedback(.success, trigger: signOutDoneStamp)
    }

    // MARK: - Account

    private var accountCard: some View {
        let user = auth.currentUser
        let displayName = user?.displayName?.trimmingCharacters(in: .whitespaces).nonEmpty
            ?? user?.email ?? "Signed-in user"
        let initials = Self.initials(from: displayName)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(theme.accent.opacity(0.25))
                    Text(initials)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(theme.font.titleCompact)
                        .foregroundStyle(theme.textPrimary)
                    if let email = user?.email {
                        Text(email)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if let createdAt = user?.createdAt {
                        Text("Member since \(Self.monthYear(createdAt))")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer()
            }
        }
        .padding(18)
        .themedCard()
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APPEARANCE")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: 12) {
                themeCard(.liquidGlass)
                themeCard(.healthCards)
            }
        }
        .padding(18)
        .themedCard()
    }

    @ViewBuilder
    private func themeCard(_ id: ThemeID) -> some View {
        let active = themeStore.current.id == id
        let preview = ThemeStore.theme(for: id)
        Button {
            themeStore.apply(id)
            themeStamp += 1
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Mini preview: tinted background + a fake hero number + chip.
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(preview.heroGradient())
                        .frame(height: 78)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("$78")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(10)
                }
                HStack(spacing: 6) {
                    Circle().fill(preview.accent).frame(width: 8, height: 8)
                    Text(id.label)
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(active ? theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack {
                Image(systemName: "wallet.bifold.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finance Tracker")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    Text(versionLabel)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }
            Divider().opacity(0.15)
            Text("Made by Armando")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Link(destination: URL(string: "https://armandointeligencia.com")!) {
                HStack {
                    Text("armandointeligencia.com")
                        .font(theme.font.bodyMedium)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
                .foregroundStyle(theme.accent)
            }
            Divider().opacity(0.15)
            // Slice 10: App Store requires accessible Privacy Policy +
            // Terms URLs. The marketing pages don't exist yet — Apple
            // just needs the URLs to resolve to *something* before review.
            Link(destination: URL(string: "https://armandointeligencia.com/privacy")!) {
                aboutLinkRow(label: "Privacy Policy", systemImage: "hand.raised.fill")
            }
            Link(destination: URL(string: "https://armandointeligencia.com/terms")!) {
                aboutLinkRow(label: "Terms of Service", systemImage: "doc.text.fill")
            }
        }
        .padding(18)
        .themedCard()
    }

    private func aboutLinkRow(label: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 20)
            Text(label).font(theme.font.body).foregroundStyle(theme.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.right.square").foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button(role: .destructive) {
            signOutWarnStamp += 1
            showSignOutAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
                    .font(theme.font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(theme.negative.opacity(0.18))
            )
            .foregroundStyle(theme.negative)
        }
    }

    // MARK: - Helpers

    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(v) (\(b))"
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2,
           let first = parts.first?.first,
           let last = parts.dropFirst().first?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private static func monthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

private extension String {
    /// Returns nil for empty / whitespace-only strings, otherwise self.
    var nonEmpty: String? { isEmpty ? nil : self }
}

#Preview("Settings — Liquid Glass") {
    NavigationStack { SettingsView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ThemeStore())
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
