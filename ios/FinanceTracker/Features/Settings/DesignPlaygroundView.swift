//
//  DesignPlaygroundView.swift
//  The reason this whole scaffolding phase exists — tap a design, the
//  entire app re-skins via the AppTheme environment.
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
        .navigationTitle("Design Playground")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Five visual languages").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Text("Tap one and the entire app re-skins live. Start with Liquid Glass — that's D1 and it's the only one fully styled today. D2–D5 are stubbed so you can see the colour grading and typography; the deep styling lands in later sessions.")
                .font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private func themeCard(for id: ThemeID) -> some View {
        let candidate = ThemeStore.theme(for: id)
        let isActive = store.current.id == id

        return Button {
            withAnimation(.smooth) {
                store.apply(id)
            }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                themeSwatch(candidate: candidate)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(candidate.displayName)
                            .font(theme.font.titleCompact)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        if isActive {
                            Text("ACTIVE").font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(theme.positive.opacity(0.22)))
                                .foregroundStyle(theme.positive)
                        } else {
                            Text(id == .liquidGlass ? "READY" : "PLACEHOLDER")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill((id == .liquidGlass ? theme.accent : theme.textTertiary).opacity(0.22)))
                                .foregroundStyle(id == .liquidGlass ? theme.accent : theme.textSecondary)
                        }
                    }
                    Text(candidate.summary).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .fill(theme.cardBackground())
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(isActive ? theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeSwatch(candidate: any AppTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(candidate.heroGradient())
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4).fill(candidate.accent).frame(width: 40, height: 6)
                RoundedRectangle(cornerRadius: 4).fill(candidate.accentSecondary).frame(width: 32, height: 6)
                RoundedRectangle(cornerRadius: 4).fill(candidate.textSecondary).frame(width: 26, height: 6)
            }
        }
        .frame(width: 70, height: 70)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview("DesignPlayground — Liquid Glass") {
    NavigationStack { DesignPlaygroundView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ThemeStore())
        .preferredColorScheme(.dark)
}
