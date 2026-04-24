//
//  CategoriesView.swift
//  Drag-reorder list of categories with swipe-to-archive and a "+"
//  toolbar button. Tapping a row presents CategoryEditSheet in edit
//  mode; tapping "+" presents it in create mode.
//

import SwiftUI

struct CategoriesView: View {
    @Environment(\.appTheme) private var theme
    @Environment(CategoriesService.self) private var cats

    @State private var editingMode: CategoryEditSheet.Mode?
    @State private var showCreate = false
    @State private var archiveError: String?
    @State private var reorderError: String?
    @State private var archivedStamp = 0
    @State private var reorderedStamp = 0
    @State private var errorStamp = 0

    /// Skeleton fallback only when the user launched with -skipAuth and
    /// the service hasn't tried to load yet. Signed-in users always see
    /// live data (or an empty state after load).
    private var useMock: Bool {
        UserDefaults.standard.bool(forKey: "FinanceTracker.skipAuth") && cats.state == .idle
    }
    private var displayCategories: [Category] {
        useMock ? MockData.categories : cats.categories
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            List {
                ForEach(displayCategories) { cat in
                    Button { editingMode = .edit(cat) } label: {
                        CategoryRow(category: cat)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            archive(cat)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
                .onMove(perform: move)

                if let archiveError {
                    Text(archiveError)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.negative)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let reorderError {
                    Text(reorderError)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.negative)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Categories")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().foregroundStyle(theme.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(theme.accent)
            }
        }
        .sheet(isPresented: $showCreate) {
            CategoryEditSheet(mode: .create)
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .sheet(item: $editingMode) { mode in
            CategoryEditSheet(mode: mode)
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .sensoryFeedback(.warning, trigger: archivedStamp)
        .sensoryFeedback(.impact(weight: .light), trigger: reorderedStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
    }

    private var sheetBackground: AnyShapeStyle {
        theme.id == .liquidGlass
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(theme.background)
    }

    // MARK: - Actions

    private func archive(_ cat: Category) {
        archiveError = nil
        Task {
            let ok = await cats.archive(id: cat.id)
            if ok {
                archivedStamp += 1
            } else {
                errorStamp += 1
                archiveError = "Couldn't archive \(cat.name). Try again."
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        // Compute the resulting ordered id list locally so we can snapshot
        // before sending. The service also snapshots for rollback on failure.
        var working = displayCategories
        working.move(fromOffsets: source, toOffset: destination)
        let orderedIds = working.map(\.id)
        reorderError = nil
        Task {
            let ok = await cats.reorder(orderedIds: orderedIds)
            if ok {
                reorderedStamp += 1
            } else {
                errorStamp += 1
                reorderError = "Couldn't reorder. Try again."
            }
        }
    }
}

// MARK: - Row

private struct CategoryRow: View {
    @Environment(\.appTheme) private var theme
    let category: Category

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(category.color.opacity(0.22))
                CategoryIcon(
                    name: category.iconSystemName,
                    color: category.color,
                    pointSize: 16
                )
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

// Lets `.sheet(item:)` drive both create and edit from a single binding.
extension CategoryEditSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let cat): return "edit:\(cat.id.uuidString)"
        }
    }
}

#Preview("Categories — Liquid Glass") {
    NavigationStack { CategoriesView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(CategoriesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
