//
//  LiquidGlassTheme.swift — Design 1
//  Native iOS 26 Liquid Glass aesthetic: deep layered gradient backgrounds,
//  translucent cards on ultraThinMaterial, big rounded numerals, soft
//  luminous accents, generous corner radii.
//

import SwiftUI

struct LiquidGlassTheme: AppTheme {
    let id: ThemeID = .liquidGlass
    let displayName = "Liquid Glass"
    let summary = "iOS 26 native — translucent depth, glass cards, big numerals"
    let preferredColorScheme: ColorScheme? = .dark

    // Deep blue / violet gradient background (set via heroGradient)
    var background: Color { Color(red: 0.04, green: 0.05, blue: 0.10) }
    var surface: Color { Color.white.opacity(0.08) }
    var surfaceSecondary: Color { Color.white.opacity(0.05) }

    var textPrimary: Color { Color.white }
    var textSecondary: Color { Color.white.opacity(0.70) }
    var textTertiary: Color { Color.white.opacity(0.45) }

    var accent: Color { Color(red: 0.62, green: 0.78, blue: 1.0) }
    var accentSecondary: Color { Color(red: 0.78, green: 0.69, blue: 1.0) }
    var positive: Color { Color(red: 0.45, green: 0.92, blue: 0.69) }
    var negative: Color { Color(red: 1.0, green: 0.48, blue: 0.55) }

    var categoryColors: [Color] {
        [
            Color(red: 0.98, green: 0.56, blue: 0.42), // Food & Dining
            Color(red: 1.00, green: 0.78, blue: 0.35), // Transportation
            Color(red: 0.70, green: 0.55, blue: 1.00), // Shopping
            Color(red: 0.95, green: 0.55, blue: 0.83), // Entertainment
            Color(red: 0.55, green: 0.70, blue: 1.00), // Bills & Utilities
            Color(red: 0.45, green: 0.92, blue: 0.69), // Health
            Color(red: 0.45, green: 0.78, blue: 0.95), // Education
            Color(red: 1.00, green: 0.65, blue: 0.40), // Personal
            Color(red: 0.65, green: 0.68, blue: 0.75), // Other
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 36, weight: .bold, design: .rounded),
            title: .system(size: 24, weight: .semibold, design: .rounded),
            titleCompact: .system(size: 18, weight: .semibold, design: .rounded),
            heroNumeral: .system(size: 48, weight: .semibold, design: .rounded),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 12, weight: .regular, design: .default),
            captionMedium: .system(size: 12, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .rounded)
        )
    }

    var radii: ThemeRadii { ThemeRadii(card: 26, button: 16, pill: 999, sheet: 34) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.12, blue: 0.28),
                    Color(red: 0.32, green: 0.15, blue: 0.45),
                    Color(red: 0.05, green: 0.07, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    func cardBackground() -> AnyShapeStyle {
        AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Liquid Glass reusable view decorators

/// Applies the Liquid Glass full-screen backdrop: deep gradient + soft
/// radial highlights that feel like light refracting through glass.
struct LiquidGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.16),
                    Color(red: 0.11, green: 0.08, blue: 0.26),
                    Color(red: 0.03, green: 0.04, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.22), .clear],
                center: .topLeading, startRadius: 30, endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.78, green: 0.55, blue: 1.0).opacity(0.18), .clear],
                center: .bottomTrailing, startRadius: 40, endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

/// A reusable glass card — ultraThinMaterial with a hairline border and
/// subtle inner highlight. Use as `.background()` or stand-alone container.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 14)
    }
}
