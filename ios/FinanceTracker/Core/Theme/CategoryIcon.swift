//
//  CategoryIcon.swift
//  Renders a Category's icon correctly regardless of whether the
//  backend stored a lucide-react icon name (seeded defaults like
//  "utensils", "car") or a Unicode emoji (user-picked like "☕", "🍔").
//
//  Used everywhere a category shows up: Home row, Expenses row,
//  Detail hero chip, QuickAdd chips, Edit sheet, Categories list.
//

import SwiftUI

/// Draws the icon in a fixed square — callers decide the outer frame,
/// colour, and any chip/pill wrapping. `color` tints SF Symbols; emoji
/// ignore tint (the colour is baked into the glyph).
struct CategoryIcon: View {
    let name: String?
    var color: Color = .primary
    var pointSize: CGFloat = 14
    var weight: Font.Weight = .semibold

    var body: some View {
        if let n = name, !n.isEmpty {
            if let sfSymbol = Self.lucideToSFSymbol[n.lowercased()] {
                Image(systemName: sfSymbol)
                    .font(.system(size: pointSize, weight: weight))
                    .foregroundStyle(color)
            } else {
                // Emoji or unknown string: render as text. Emoji ignore the
                // tint, and for unknown strings we still get *something*
                // on screen instead of a broken-symbol placeholder.
                Text(n)
                    .font(.system(size: pointSize + 2))
            }
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: pointSize, weight: weight))
                .foregroundStyle(color)
        }
    }

    /// Seeded categories on the backend store icons as lucide-react
    /// names (from the web app's registration defaults). Map them to
    /// SF Symbols for native rendering.
    private static let lucideToSFSymbol: [String: String] = [
        "utensils":      "fork.knife",
        "car":           "car.fill",
        "shopping-bag":  "bag.fill",
        "shoppingbag":   "bag.fill",
        "film":          "film.fill",
        "zap":           "bolt.fill",
        "heart":         "heart.fill",
        "book":          "book.fill",
        "user":          "person.fill",
        "receipt":       "square.grid.2x2.fill",
        "home":          "house.fill",
        "coffee":        "cup.and.saucer.fill",
        "plane":         "airplane",
        "shirt":         "tshirt.fill",
        "lightbulb":     "lightbulb.fill",
        "gift":          "gift.fill",
        "smartphone":    "iphone",
        "pill":          "pills.fill",
        "shopping-cart": "cart.fill",
    ]
}

#Preview {
    VStack(spacing: 20) {
        CategoryIcon(name: "utensils", color: .red, pointSize: 18)
        CategoryIcon(name: "☕", pointSize: 18)
        CategoryIcon(name: "🍔", pointSize: 18)
        CategoryIcon(name: nil, color: .gray, pointSize: 18)
        CategoryIcon(name: "not-a-real-icon", pointSize: 18)
    }
    .padding()
}
