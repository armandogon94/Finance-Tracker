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
            case .editorial:    EditorialBackdrop()
            case .darkTerminal: DarkTerminalBackdrop()
            case .warmPaper:    WarmPaperBackdrop()
            case .healthCards:  HealthCardsBackdrop()
            }
        }
    }
}

// MARK: - D2 Editorial

struct EditorialBackdrop: View {
    var body: some View {
        Color(red: 0.98, green: 0.96, blue: 0.92)
            .overlay(
                // Thin baseline rules that hint at a magazine grid
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .frame(height: 0.5)
                        .padding(.horizontal, 24)
                    Spacer().frame(height: 72)
                }
            )
            .ignoresSafeArea()
    }
}

// MARK: - D3 Dark Terminal

struct DarkTerminalBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.04)
            // Subtle vignette to give the "screen glow" feel
            RadialGradient(
                colors: [
                    Color(red: 0.30, green: 0.90, blue: 0.80).opacity(0.06),
                    .clear
                ],
                center: .top, startRadius: 20, endRadius: 500
            )
            // Faint horizontal scanlines
            GeometryReader { proxy in
                let stripeHeight: CGFloat = 2
                VStack(spacing: stripeHeight) {
                    ForEach(0..<Int(proxy.size.height / (stripeHeight * 2)) + 1, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.012))
                            .frame(height: stripeHeight)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - D4 Warm Paper

struct WarmPaperBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.93, blue: 0.86),
                    Color(red: 0.94, green: 0.89, blue: 0.80)
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Warm radial highlight top-left
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.92, blue: 0.75).opacity(0.45), .clear],
                center: .topLeading, startRadius: 20, endRadius: 420
            )
            // Deeper shadow pool bottom-right
            RadialGradient(
                colors: [Color(red: 0.50, green: 0.35, blue: 0.20).opacity(0.12), .clear],
                center: .bottomTrailing, startRadius: 40, endRadius: 520
            )
        }
        .ignoresSafeArea()
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
