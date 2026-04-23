//
//  ThemedCard.swift
//  One API (.themedCard() / ThemedBackdrop) that every screen calls.
//  The modifier dispatches per-theme so D1 gets glass materials,
//  D2 gets flat hairline rectangles, D3 gets dark bloomberg rows, etc.
//

import SwiftUI

// MARK: - Per-theme card modifier

extension View {
    /// Apply the active theme's card surface (fill + border + shadow).
    /// - Parameter radius: optional override; defaults to `theme.radii.card`.
    func themedCard(radius: CGFloat? = nil) -> some View {
        modifier(ThemedCardModifier(radius: radius))
    }

    /// Variant with reduced visual weight — used for nested/inner cards.
    func themedInnerCard(radius: CGFloat? = nil) -> some View {
        modifier(ThemedCardModifier(radius: radius, inner: true))
    }
}

struct ThemedCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    var radius: CGFloat?
    var inner: Bool = false

    func body(content: Content) -> some View {
        let r = radius ?? theme.radii.card
        switch theme.id {

        // MARK: Liquid Glass — materials, luminous border, layered shadow
        case .liquidGlass:
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(inner ? AnyShapeStyle(Color.white.opacity(0.05))
                                        : AnyShapeStyle(.ultraThinMaterial))
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(inner ? 0.18 : 0.32),
                                             Color.white.opacity(0.04)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(inner ? 0.10 : 0.30), radius: inner ? 8 : 18, y: inner ? 4 : 10)

        // MARK: Editorial — flat surface, hairline ink border, no shadow
        case .editorial:
            content
                .background(
                    Rectangle()
                        .fill(inner ? theme.surfaceSecondary : theme.surface)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.black.opacity(inner ? 0.05 : 0.09), lineWidth: 0.7)
                )

        // MARK: Dark Terminal — accent top rule + tiny radius + inner glow
        case .darkTerminal:
            content
                .background(
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(inner ? theme.surfaceSecondary : theme.surface)
                        Rectangle()
                            .fill(theme.accent.opacity(inner ? 0.4 : 0.8))
                            .frame(height: inner ? 1 : 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )

        // MARK: Warm Paper — cream surface with soft warm-tinted shadow
        case .warmPaper:
            content
                .background(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(inner ? theme.surfaceSecondary : theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Color(red: 0.35, green: 0.25, blue: 0.15).opacity(inner ? 0.04 : 0.08), lineWidth: 0.7)
                )
                .shadow(
                    color: Color(red: 0.30, green: 0.18, blue: 0.08).opacity(inner ? 0.05 : 0.12),
                    radius: inner ? 3 : 8, y: inner ? 1 : 4
                )

        // MARK: Health Cards — clean rounded surface with soft elevation
        case .healthCards:
            content
                .background(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(inner ? theme.surfaceSecondary : theme.surface)
                )
                .shadow(
                    color: .black.opacity(inner ? 0.04 : 0.08),
                    radius: inner ? 6 : 14, y: inner ? 2 : 6
                )
        }
    }
}
