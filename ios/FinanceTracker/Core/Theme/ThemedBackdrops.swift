//
//  ThemedBackdrops.swift
//  Per-theme full-screen backgrounds. Every screen places a
//  `ThemedBackdrop()` at the root of its ZStack; the right variant
//  is picked from the active theme.
//

import SwiftUI

// MARK: - Dispatcher (replaces earlier simple version)

struct ThemedBackdrop: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            switch theme.id {
            case .liquidGlass:  LiquidGlassBackdrop()
            case .healthCards:  HealthCardsBackdrop()
            }
        }
    }
}

// MARK: - D5 Health Cards

struct HealthCardsBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.965, green: 0.965, blue: 0.975)
            // Soft coloured glow top — evokes Apple Health category gradients
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.45, blue: 0.45).opacity(0.07),
                    .clear
                ],
                startPoint: .top, endPoint: .center
            )
            LinearGradient(
                colors: [
                    .clear,
                    Color(red: 0.38, green: 0.52, blue: 0.98).opacity(0.06)
                ],
                startPoint: .center, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
