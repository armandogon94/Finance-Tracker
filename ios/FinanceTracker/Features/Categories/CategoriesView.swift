//
//  CategoriesView.swift
//  Drag-reorder list of categories with budget and icon preview.
//

import SwiftUI

struct CategoriesView: View {
    @Environment(\.appTheme) private var theme
    @State private var categories: [Category] = MockData.categories

    var body: some View {
        ZStack {
            ThemedBackdrop()
            List {
                ForEach(categories) { cat in
                    CategoryRow(category: cat)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { indices, to in
                    categories.move(fromOffsets: indices, toOffset: to)
                }
                .onDelete { indices in
                    categories.remove(atOffsets: indices)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Categories")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().foregroundStyle(theme.accent) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { } label: { Image(systemName: "plus") }.foregroundStyle(theme.accent)
            }
        }
    }
}

private struct CategoryRow: View {
    @Environment(\.appTheme) private var theme
    let category: Category

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(category.color.opacity(0.22))
                Image(systemName: category.iconSystemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                if let b = category.monthlyBudget {
                    Text("Budget $\(Int(b))/mo").font(theme.font.caption).foregroundStyle(theme.textSecondary)
                } else {
                    Text("No budget").font(theme.font.caption).foregroundStyle(theme.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .themedCard()
    }
}

#Preview("Categories — Liquid Glass") {
    NavigationStack { CategoriesView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
