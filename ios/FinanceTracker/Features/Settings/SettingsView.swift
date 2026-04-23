//
//  SettingsView.swift
//  Profile, OCR preference, theme, Face ID, Telegram linking, data export.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @State private var faceIdEnabled = true
    @State private var ocrMode: OcrMode = .auto
    @State private var currency = "USD"

    enum OcrMode: String, CaseIterable, Hashable {
        case auto, cloud, offline, manual
        var label: String {
            switch self {
            case .auto: "Auto"
            case .cloud: "Cloud Only"
            case .offline: "Offline Only"
            case .manual: "Manual"
            }
        }
        var summary: String {
            switch self {
            case .auto: "Claude → Ollama → Tesseract"
            case .cloud: "Claude Vision (Haiku 4.5)"
            case .offline: "On-device Tesseract"
            case .manual: "Type amounts manually"
            }
        }
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    profileCard
                    ocrCard
                    securityCard
                    designPlaygroundLink
                    telegramCard
                    exportCard
                    aboutCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(theme.accent.opacity(0.25))
                    Text(String(MockData.user.name.prefix(1)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MockData.user.name).font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
                    Text(MockData.user.email).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }
            Divider().opacity(0.15)
            row(icon: "dollarsign.circle", title: "Currency", value: currency)
            row(icon: "clock", title: "Timezone", value: "America/New York")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var ocrCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Receipt OCR", systemImage: "doc.text.viewfinder")
                .font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            ForEach(OcrMode.allCases, id: \.self) { mode in
                let active = ocrMode == mode
                Button { ocrMode = mode } label: {
                    HStack {
                        Image(systemName: active ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(active ? theme.accent : theme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                            Text(mode.summary).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radii.card - 8, style: .continuous)
                            .fill(active ? theme.accent.opacity(0.12) : theme.surfaceSecondary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security", systemImage: "lock.shield.fill")
                .font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Toggle(isOn: $faceIdEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock with Face ID").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text("Require biometrics on launch").font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .tint(theme.accent)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var designPlaygroundLink: some View {
        NavigationLink { DesignPlaygroundView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.accent.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Design Playground").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text("Try five visual languages").font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .fill(theme.cardBackground())
            )
        }
        .buttonStyle(.plain)
    }

    private var telegramCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Telegram bot", systemImage: "paperplane.fill")
                .font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Text("Log expenses and scan receipts from @ArmandoFinanceBot on Telegram.")
                .font(theme.font.caption).foregroundStyle(theme.textSecondary)
            Button {} label: {
                Text("Link Telegram account")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: theme.radii.button).fill(theme.accent.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export data", systemImage: "tray.and.arrow.down.fill")
                .font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Button {} label: {
                row(icon: "arrow.down.doc", title: "Download CSV (2026)", value: "")
            }.buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var aboutCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Finance Tracker").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                Text("v0.1.0 · skeleton build").font(theme.font.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text(title).font(theme.font.body).foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value).font(theme.font.caption).foregroundStyle(theme.textSecondary)
            Image(systemName: "chevron.right").foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, 8)
    }
}

#Preview("Settings — Liquid Glass") {
    NavigationStack { SettingsView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
