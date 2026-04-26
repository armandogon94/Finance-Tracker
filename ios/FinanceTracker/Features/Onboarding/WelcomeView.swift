//
//  WelcomeView.swift
//  Slice 10 — first-run welcome. Single full-bleed sheet shown once
//  per install (gated by OnboardingState.hasSeenWelcome). Pitched at
//  Mom: short value-prop, three concrete benefits, one big button.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(OnboardingState.self) private var onboarding

    @State private var heroPulse = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.heroGradient())
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer(minLength: 32)

                Image(systemName: "sparkles")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: heroPulse)
                    .accessibilityHidden(true)
                    .onAppear { heroPulse = true }

                VStack(spacing: 10) {
                    Text("Track money. Skip the guesswork.")
                        .font(.system(size: 30, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Finance Tracker keeps your spending in one place and tells you what it means.")
                        .font(theme.font.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 18) {
                    bullet("doc.text.viewfinder", text: "Scan receipts in seconds")
                    bullet("chart.line.uptrend.xyaxis", text: "See where your money goes")
                    bullet("sparkles", text: "Ask Claude anything about your spending")
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)

                Spacer()

                Button {
                    onboarding.markSeen()
                    dismiss()
                } label: {
                    Text("Get started")
                        .font(theme.font.titleCompact)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .accessibilityLabel("Get started — dismiss this welcome screen")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
    }

    private func bullet(_ icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(theme.font.bodyMedium)
                .foregroundStyle(.white)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview("Welcome — Liquid Glass") {
    WelcomeView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(OnboardingState())
        .preferredColorScheme(.dark)
}
