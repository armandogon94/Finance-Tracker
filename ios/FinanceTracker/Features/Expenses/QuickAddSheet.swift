//
//  QuickAddSheet.swift
//  Sub-10-second expense entry: amount keypad + category chip picker.
//

import SwiftUI

struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var amount: String = "0"
    @State private var selectedCategory: Category? = MockData.categories.first

    var body: some View {
        ZStack {
            if theme.id == .liquidGlass {
                Color.clear
            } else {
                theme.background.ignoresSafeArea()
            }
            VStack(spacing: 18) {
                grabber
                Text("Quick Add").font(theme.font.title).foregroundStyle(theme.textPrimary).padding(.top, 4)

                amountDisplay
                categoryPicker
                keypad
                saveButton
            }
            .padding(20)
        }
    }

    private var grabber: some View {
        Capsule().fill(theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 6)
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
            Text(amount).font(theme.font.heroNumeral).foregroundStyle(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MockData.categories) { cat in
                    let active = selectedCategory?.id == cat.id
                    Button { selectedCategory = cat } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.iconSystemName)
                            Text(cat.name)
                        }
                        .font(theme.font.captionMedium)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(active ? cat.color.opacity(0.3) : theme.surface))
                        .foregroundStyle(active ? cat.color : theme.textSecondary)
                    }
                }
            }
        }
    }

    private var keypad: some View {
        let rows = [["1","2","3"], ["4","5","6"], ["7","8","9"], [".","0","⌫"]]
        return VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                        .fill(theme.surface)
                                )
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Save expense")
                .font(theme.font.titleCompact)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                        .fill(theme.accent)
                )
        }
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            amount = String(amount.dropLast())
            if amount.isEmpty { amount = "0" }
        } else if key == "." {
            if !amount.contains(".") { amount += "." }
        } else {
            if amount == "0" { amount = key } else { amount += key }
        }
    }
}

#Preview("QuickAdd — Liquid Glass") {
    QuickAddSheet()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
