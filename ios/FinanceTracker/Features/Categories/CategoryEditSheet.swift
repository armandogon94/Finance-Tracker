//
//  CategoryEditSheet.swift
//  Create or edit a category. Icon picker is a curated emoji set
//  (same list as the web's DEFAULT_ICONS); color picker is a curated
//  swatch set matching the web's DEFAULT_COLORS. The name field is
//  required; everything else is optional.
//

import SwiftUI

struct CategoryEditSheet: View {
    enum Mode: Equatable {
        case create
        case edit(Category)

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }
        var title: String {
            self == .create ? "New category" : "Edit category"
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(CategoriesService.self) private var cats

    let mode: Mode

    @State private var name: String = ""
    @State private var icon: String = "🍔"
    @State private var color: String = Self.defaultColors[0]
    @State private var budgetText: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedStamp = 0
    @State private var errorStamp = 0

    static let defaultIcons: [String] = [
        "🍔", "🛒", "🚗", "🏠", "💊", "🎮", "✈️", "📚", "👕", "💡",
        "🎬", "🏋️", "☕", "🎁", "📱",
    ]
    static let defaultColors: [String] = [
        "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6",
        "#EC4899", "#14B8A6", "#F97316", "#6366F1", "#84CC16",
    ]

    private var parsedBudget: Double? {
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
    private var canSave: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    grabber
                    header

                    nameCard
                    iconCard
                    colorCard
                    budgetCard

                    if let saveError {
                        Text(saveError)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    saveButton
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear(perform: prefill)
        .sensoryFeedback(.success, trigger: savedStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
    }

    // MARK: - Layout

    private var grabber: some View {
        Capsule().fill(theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
    }

    private var header: some View {
        HStack {
            Text(mode.title)
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(role: .cancel) { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: 10) {
                // Live preview of the selected icon + color so the user can
                // see the composition as they build it.
                ZStack {
                    Circle().fill(swatchColor.opacity(0.22))
                    CategoryIcon(name: icon, color: swatchColor, pointSize: 16)
                }
                .frame(width: 38, height: 38)
                TextField("e.g. Coffee, Gym, Subscriptions", text: $name)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                    .textInputAutocapitalization(.words)
            }
        }
        .padding(18)
        .themedCard()
    }

    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ICON")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.defaultIcons, id: \.self) { emoji in
                        let active = emoji == icon
                        Button { icon = emoji } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(active ? swatchColor.opacity(0.30) : theme.surface)
                                )
                                .overlay(
                                    Circle().strokeBorder(active ? swatchColor : .clear, lineWidth: 2)
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLOR")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.defaultColors, id: \.self) { hex in
                        let active = hex == color
                        Button { color = hex } label: {
                            Circle()
                                .fill(Self.color(from: hex) ?? .gray)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().strokeBorder(active ? Color.white : .clear, lineWidth: 3)
                                )
                                .overlay(
                                    Circle().strokeBorder(active ? theme.textPrimary.opacity(0.6) : .clear, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MONTHLY BUDGET (OPTIONAL)")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                TextField("0", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            Text("Leave empty if you don't want to track a limit.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .themedCard()
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().tint(.black).padding(.trailing, 2)
                }
                Text(isSaving ? "Saving…" : (mode.isEdit ? "Save changes" : "Create category"))
                    .font(theme.font.titleCompact)
                    .foregroundStyle(Color.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(canSave ? theme.accent : theme.accent.opacity(0.4))
            )
        }
        .disabled(!canSave)
    }

    // MARK: - Actions

    private var swatchColor: Color {
        Self.color(from: color) ?? theme.accent
    }

    private func prefill() {
        if case let .edit(cat) = mode {
            name = cat.name
            if !cat.iconSystemName.isEmpty {
                icon = cat.iconSystemName
            }
            if let hex = Self.hex(from: cat.color) {
                color = hex
            }
            if let budget = cat.monthlyBudget {
                budgetText = String(format: "%.0f", budget)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        saveError = nil
        Task {
            let ok: Bool
            switch mode {
            case .create:
                ok = (await cats.create(
                    name: trimmedName,
                    icon: icon,
                    color: color,
                    monthlyBudget: parsedBudget
                )) != nil
            case .edit(let original):
                let patch = diff(from: original, newName: trimmedName)
                ok = await cats.update(id: original.id, patch: patch)
            }
            isSaving = false
            if ok {
                savedStamp += 1
                try? await Task.sleep(for: .milliseconds(120))
                dismiss()
            } else {
                errorStamp += 1
                saveError = "Couldn't save. Check your connection and try again."
            }
        }
    }

    /// Only include fields the user actually changed. Keeps PATCH payloads
    /// tight and readable in network logs.
    private func diff(from original: Category, newName: String) -> UpdateCategoryDTO {
        let origHex = Self.hex(from: original.color) ?? ""
        let nameChanged = newName != original.name
        let iconChanged = icon != original.iconSystemName && !icon.isEmpty
        let colorChanged = color != origHex
        let budgetChanged = parsedBudget != original.monthlyBudget
        return UpdateCategoryDTO(
            name: nameChanged ? newName : nil,
            icon: iconChanged ? icon : nil,
            color: colorChanged ? color : nil,
            monthlyBudget: budgetChanged ? parsedBudget : nil,
            isHidden: nil
        )
    }

    // MARK: - Color helpers

    private static func color(from hex: String) -> Color? {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Best-effort reverse-lookup for a SwiftUI Color → hex. Since SwiftUI
    /// doesn't expose color components directly, we round-trip through
    /// UIColor to pull RGB out.
    private static func hex(from color: Color) -> String? {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

#Preview("Create — Liquid Glass") {
    CategoryEditSheet(mode: .create)
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(CategoriesService(api: APIClient()))
        .preferredColorScheme(.dark)
}

#Preview("Edit — Liquid Glass") {
    CategoryEditSheet(mode: .edit(MockData.categories[0]))
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(CategoriesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
