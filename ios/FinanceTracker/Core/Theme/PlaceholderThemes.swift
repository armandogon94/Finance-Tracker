//
//  PlaceholderThemes.swift
//  D2–D5: stubbed so the Design Playground picker compiles and renders
//  something recognizable for each. These are intentionally rough —
//  future sessions will flesh out each design language in depth.
//

import SwiftUI

// MARK: - D2: Editorial / Monochrome

struct EditorialTheme: AppTheme {
    let id: ThemeID = .editorial
    let displayName = "Editorial"
    let summary = "Swiss typography, cream + ink, one electric accent"
    let preferredColorScheme: ColorScheme? = .light

    var background: Color { Color(red: 0.98, green: 0.96, blue: 0.92) }
    var surface: Color { .white }
    var surfaceSecondary: Color { Color(red: 0.95, green: 0.93, blue: 0.88) }

    var textPrimary: Color { Color(red: 0.10, green: 0.10, blue: 0.10) }
    var textSecondary: Color { Color(red: 0.42, green: 0.42, blue: 0.42) }
    var textTertiary: Color { Color(red: 0.65, green: 0.65, blue: 0.65) }

    var accent: Color { Color(red: 0.0, green: 0.35, blue: 1.0) }
    var accentSecondary: Color { Color(red: 0.10, green: 0.10, blue: 0.10) }
    var positive: Color { Color(red: 0.13, green: 0.55, blue: 0.28) }
    var negative: Color { Color(red: 0.80, green: 0.15, blue: 0.15) }

    var categoryColors: [Color] {
        [ .black, .black, .black, .black, .black, .black, .black, .black, .black ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 42, weight: .black, design: .serif),
            title: .system(size: 28, weight: .semibold, design: .serif),
            titleCompact: .system(size: 17, weight: .semibold, design: .default),
            heroNumeral: .system(size: 56, weight: .bold, design: .default),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 11, weight: .regular, design: .default),
            captionMedium: .system(size: 11, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .monospaced)
        )
    }
    var radii: ThemeRadii { ThemeRadii(card: 0, button: 0, pill: 0, sheet: 0) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle { AnyShapeStyle(background) }
    func cardBackground() -> AnyShapeStyle { AnyShapeStyle(surface) }
}

// MARK: - D3: Dark Terminal

struct DarkTerminalTheme: AppTheme {
    let id: ThemeID = .darkTerminal
    let displayName = "Dark Terminal"
    let summary = "Bloomberg vibes: dark, mono numerals, cyan data accents"
    let preferredColorScheme: ColorScheme? = .dark

    var background: Color { Color(red: 0.02, green: 0.03, blue: 0.04) }
    var surface: Color { Color(red: 0.06, green: 0.07, blue: 0.09) }
    var surfaceSecondary: Color { Color(red: 0.10, green: 0.11, blue: 0.13) }

    var textPrimary: Color { Color(red: 0.92, green: 0.94, blue: 0.96) }
    var textSecondary: Color { Color(red: 0.58, green: 0.62, blue: 0.66) }
    var textTertiary: Color { Color(red: 0.38, green: 0.42, blue: 0.46) }

    var accent: Color { Color(red: 0.30, green: 0.90, blue: 0.80) }
    var accentSecondary: Color { Color(red: 0.40, green: 0.70, blue: 1.0) }
    var positive: Color { Color(red: 0.30, green: 0.90, blue: 0.55) }
    var negative: Color { Color(red: 1.00, green: 0.35, blue: 0.40) }

    var categoryColors: [Color] {
        [
            Color(red: 1.0, green: 0.35, blue: 0.40),
            Color(red: 1.0, green: 0.72, blue: 0.30),
            Color(red: 0.60, green: 0.55, blue: 1.0),
            Color(red: 0.95, green: 0.42, blue: 0.80),
            Color(red: 0.40, green: 0.70, blue: 1.0),
            Color(red: 0.30, green: 0.90, blue: 0.55),
            Color(red: 0.30, green: 0.90, blue: 0.80),
            Color(red: 1.00, green: 0.55, blue: 0.30),
            Color(red: 0.55, green: 0.58, blue: 0.65),
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 28, weight: .bold, design: .monospaced),
            title: .system(size: 18, weight: .semibold, design: .monospaced),
            titleCompact: .system(size: 14, weight: .semibold, design: .monospaced),
            heroNumeral: .system(size: 44, weight: .bold, design: .monospaced),
            bodyMedium: .system(size: 13, weight: .medium, design: .monospaced),
            body: .system(size: 13, weight: .regular, design: .monospaced),
            caption: .system(size: 10, weight: .regular, design: .monospaced),
            captionMedium: .system(size: 10, weight: .semibold, design: .monospaced),
            monoNumeral: .system(size: 13, weight: .medium, design: .monospaced)
        )
    }
    var radii: ThemeRadii { ThemeRadii(card: 4, button: 4, pill: 4, sheet: 8) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle { AnyShapeStyle(background) }
    func cardBackground() -> AnyShapeStyle { AnyShapeStyle(surface) }
}

// MARK: - D4: Warm Paper

struct WarmPaperTheme: AppTheme {
    let id: ThemeID = .warmPaper
    let displayName = "Warm Paper"
    let summary = "Leather-ledger feel: cream, serif, muted earth tones"
    let preferredColorScheme: ColorScheme? = .light

    var background: Color { Color(red: 0.96, green: 0.92, blue: 0.85) }
    var surface: Color { Color(red: 0.99, green: 0.96, blue: 0.90) }
    var surfaceSecondary: Color { Color(red: 0.93, green: 0.89, blue: 0.81) }

    var textPrimary: Color { Color(red: 0.22, green: 0.16, blue: 0.11) }
    var textSecondary: Color { Color(red: 0.45, green: 0.35, blue: 0.25) }
    var textTertiary: Color { Color(red: 0.62, green: 0.52, blue: 0.42) }

    var accent: Color { Color(red: 0.58, green: 0.28, blue: 0.18) }
    var accentSecondary: Color { Color(red: 0.35, green: 0.45, blue: 0.30) }
    var positive: Color { Color(red: 0.30, green: 0.50, blue: 0.28) }
    var negative: Color { Color(red: 0.70, green: 0.25, blue: 0.20) }

    var categoryColors: [Color] {
        [
            Color(red: 0.72, green: 0.38, blue: 0.25),
            Color(red: 0.85, green: 0.60, blue: 0.25),
            Color(red: 0.55, green: 0.35, blue: 0.45),
            Color(red: 0.78, green: 0.40, blue: 0.55),
            Color(red: 0.40, green: 0.50, blue: 0.65),
            Color(red: 0.42, green: 0.55, blue: 0.38),
            Color(red: 0.35, green: 0.50, blue: 0.62),
            Color(red: 0.75, green: 0.48, blue: 0.30),
            Color(red: 0.55, green: 0.48, blue: 0.40),
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 38, weight: .bold, design: .serif),
            title: .system(size: 24, weight: .semibold, design: .serif),
            titleCompact: .system(size: 17, weight: .semibold, design: .serif),
            heroNumeral: .system(size: 46, weight: .semibold, design: .serif),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 12, weight: .regular, design: .default),
            captionMedium: .system(size: 12, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .serif)
        )
    }
    var radii: ThemeRadii { ThemeRadii(card: 10, button: 8, pill: 999, sheet: 18) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.92, blue: 0.85),
                    Color(red: 0.93, green: 0.88, blue: 0.78)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
    func cardBackground() -> AnyShapeStyle { AnyShapeStyle(surface) }
}

// MARK: - D5: Apple Health-style Cards

struct HealthCardsTheme: AppTheme {
    let id: ThemeID = .healthCards
    let displayName = "Health Cards"
    let summary = "Bright gradient cards, big visualizations, vertical stack"
    let preferredColorScheme: ColorScheme? = .light

    var background: Color { Color(red: 0.96, green: 0.96, blue: 0.98) }
    var surface: Color { .white }
    var surfaceSecondary: Color { Color(red: 0.92, green: 0.92, blue: 0.96) }

    var textPrimary: Color { Color(red: 0.08, green: 0.09, blue: 0.12) }
    var textSecondary: Color { Color(red: 0.42, green: 0.44, blue: 0.50) }
    var textTertiary: Color { Color(red: 0.65, green: 0.68, blue: 0.72) }

    var accent: Color { Color(red: 0.96, green: 0.35, blue: 0.45) }
    var accentSecondary: Color { Color(red: 0.38, green: 0.48, blue: 0.98) }
    var positive: Color { Color(red: 0.18, green: 0.70, blue: 0.45) }
    var negative: Color { Color(red: 0.96, green: 0.35, blue: 0.45) }

    var categoryColors: [Color] {
        [
            Color(red: 0.98, green: 0.45, blue: 0.45),
            Color(red: 1.00, green: 0.68, blue: 0.22),
            Color(red: 0.58, green: 0.42, blue: 0.98),
            Color(red: 0.95, green: 0.42, blue: 0.78),
            Color(red: 0.38, green: 0.52, blue: 0.98),
            Color(red: 0.22, green: 0.78, blue: 0.52),
            Color(red: 0.22, green: 0.72, blue: 0.88),
            Color(red: 0.98, green: 0.55, blue: 0.28),
            Color(red: 0.62, green: 0.62, blue: 0.68),
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 34, weight: .bold, design: .default),
            title: .system(size: 22, weight: .bold, design: .default),
            titleCompact: .system(size: 17, weight: .semibold, design: .default),
            heroNumeral: .system(size: 44, weight: .bold, design: .rounded),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 12, weight: .regular, design: .default),
            captionMedium: .system(size: 12, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .rounded)
        )
    }
    var radii: ThemeRadii { ThemeRadii(card: 18, button: 14, pill: 999, sheet: 28) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle { AnyShapeStyle(background) }
    func cardBackground() -> AnyShapeStyle { AnyShapeStyle(surface) }
}
