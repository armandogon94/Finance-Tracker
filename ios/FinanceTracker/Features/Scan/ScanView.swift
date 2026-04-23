//
//  ScanView.swift
//  Receipt OCR flow. The skeleton shows the three states: pre-capture,
//  analyzing, and review. Real VisionKit integration will replace the
//  static preview in the next phase.
//

import SwiftUI

struct ScanView: View {
    @Environment(\.appTheme) private var theme
    enum Phase { case capture, analyzing, review }
    @State private var phase: Phase = .capture

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                switch phase {
                case .capture:   captureScreen
                case .analyzing: analyzingScreen
                case .review:    reviewScreen
                }
            }
            .navigationTitle("Scan receipt")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Capture

    private var captureScreen: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(theme.surfaceSecondary)
                    .overlay(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                                .padding(32)
                            VStack {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 54))
                                    .foregroundStyle(theme.textSecondary)
                                Text("Position the receipt inside the frame")
                                    .font(theme.font.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.top, 8)
                            }
                        }
                    )
                    .aspectRatio(3/4, contentMode: .fit)
                    .padding(16)
                VStack {
                    Spacer()
                    HStack(spacing: 14) {
                        secondary("photo.on.rectangle", label: "Library")
                        Button { fake() } label: {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 76, height: 76)
                                Circle().strokeBorder(theme.accent, lineWidth: 4).frame(width: 84, height: 84)
                            }
                        }
                        secondary("flashlight.off.fill", label: "Flash")
                    }
                    .padding(.bottom, 24)
                }
            }
            Spacer()
        }
    }

    private func secondary(_ icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.surface))
                .foregroundStyle(theme.textPrimary)
            Text(label).font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Analyzing

    private var analyzingScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().strokeBorder(theme.accent.opacity(0.25), lineWidth: 8).frame(width: 120, height: 120)
                Circle().trim(from: 0, to: 0.7).stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .task {
                        try? await Task.sleep(for: .seconds(1.6))
                        phase = .review
                    }
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
            }
            Text("Analyzing with Claude Vision…")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("Reading merchant, total, date, and items")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Review

    private var reviewScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(MockData.lastOcr.merchant)
                        .font(theme.font.title)
                        .foregroundStyle(theme.textPrimary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                        Text(String(format: "%.2f", MockData.lastOcr.total))
                            .font(theme.font.heroNumeral)
                            .foregroundStyle(theme.textPrimary)
                    }
                    Text(MockData.lastOcr.date)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .themedCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Category").font(theme.font.captionMedium).tracking(1.2)
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MockData.categories) { cat in
                                let active = cat.name == MockData.lastOcr.category
                                HStack(spacing: 6) {
                                    Image(systemName: cat.iconSystemName)
                                    Text(cat.name)
                                }
                                .font(theme.font.captionMedium)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(active ? cat.color.opacity(0.25) : theme.surface))
                                .foregroundStyle(active ? cat.color : theme.textSecondary)
                            }
                        }
                    }
                }
                .padding(16)
                .themedCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Items").font(theme.font.captionMedium).tracking(1.2)
                        .foregroundStyle(theme.textTertiary)
                    VStack(spacing: 8) {
                        ForEach(MockData.lastOcr.items, id: \.self) { it in
                            HStack {
                                Image(systemName: "circle.fill").font(.system(size: 5))
                                    .foregroundStyle(theme.textTertiary)
                                Text(it).font(theme.font.body).foregroundStyle(theme.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .themedCard()

                HStack(spacing: 12) {
                    Button { phase = .capture } label: {
                        Text("Cancel")
                            .font(theme.font.bodyMedium)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: theme.radii.button).fill(theme.surface))
                            .foregroundStyle(theme.textPrimary)
                    }
                    Button { phase = .capture } label: {
                        Text("Save")
                            .font(theme.font.titleCompact)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: theme.radii.button).fill(theme.accent))
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func fake() {
        phase = .analyzing
    }
}

#Preview("Scan — Liquid Glass") {
    ScanView()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
