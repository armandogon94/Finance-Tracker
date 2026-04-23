//
//  DesignPlaygroundView.swift
//  Theme picker — D1 Liquid Glass and D5 Health Cards. Either can be
//  the user's daily driver; changing persists to UserDefaults and
//  re-skins the entire app instantly.
//

import SwiftUI

struct DesignPlaygroundView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ThemeStore.self) private var store

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard
                    ForEach(ThemeID.allCases, id: \.self) { id in
                        themeCard(for: id)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Theme")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick your look")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("Both themes are daily-driver ready — Liquid Glass leans dark and atmospheric, Health Cards leans light and crisp. Tap to switch; the whole app re-skins instantly and remembers your choice.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .themedCard()
    }

    private func themeCard(for id: ThemeID) -> some View {
        let candidate = ThemeStore.theme(for: id)
        let isActive = store.current.id == id

        return Button {
            withAnimation(.smooth) {
                store.apply(id)
            }
        } label: {
            HStack(alignment: .center, spacing: 16) {
                themeSwatch(candidate: candidate)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(candidate.displayName)
                            .font(theme.font.titleCompact)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        if isActive {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.positive)
                        }
                    }
                    Text(candidate.summary)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(16)
            .themedCard()
            .overlay(
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(isActive ? theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeSwatch(candidate: any AppTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(candidate.heroGradient())
            if candidate.id == .liquidGlass {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.12, blue: 0.28),
                        Color(red: 0.32, green: 0.15, blue: 0.45),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(candidate.accent).frame(width: 44, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(candidate.accentSecondary).frame(width: 34, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(candidate.textSecondary.opacity(0.5)).frame(width: 28, height: 6)
            }
        }
        .frame(width: 84, height: 84)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview("Theme — Liquid Glass") {
    NavigationStack { DesignPlaygroundView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ThemeStore())
        .preferredColorScheme(.dark)
}
