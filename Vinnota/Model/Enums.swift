import SwiftUI

/// The bottle lifecycle from the design's `TAG` table.
enum WineStatus: String, Codable, CaseIterable, Identifiable {
    case new, want, maybe, not, bought, tasted
    var id: String { rawValue }

    /// Chip/tag copy, verbatim from the design.
    var label: String {
        switch self {
        case .new:    "Scanned"
        case .want:   "Want to try"
        case .maybe:  "Undecided"
        case .not:    "Passed"
        case .bought: "In the rack"
        case .tasted: "Tasted"
        }
    }

    /// The accent used for the rail, shelf dot and timeline dot.
    var rail: Color {
        switch self {
        case .new:    Palette.rose(0.22)
        case .want:   Palette.rose(1.0)
        case .maybe:  Palette.rose(0.22)
        case .not:    Palette.rose(0.10)
        case .bought: Palette.green
        case .tasted: Palette.rose(0.55)
        }
    }
}

/// Filter tabs across the cellar and search screens.
enum WineFilter: String, CaseIterable, Identifiable {
    case all, new, want, bought, tasted, not
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    "All"
        case .new:    "Scanned"
        case .want:   "Wanted"
        case .bought: "In the rack"
        case .tasted: "Tasted"
        case .not:    "Passed"
        }
    }

    func matches(_ wine: Wine) -> Bool {
        guard self != .all else { return true }
        return wine.status.rawValue == rawValue
    }
}

/// The three-way tasting verdict.
enum Verdict: String, Codable, CaseIterable, Identifiable {
    case loved, meh, disliked
    var id: String { rawValue }

    var label: String {
        switch self {
        case .loved:    "Loved it"
        case .meh:      "Fine"
        case .disliked: "Not for me"
        }
    }

    /// Secondary copy on the tasting screen's verdict rows.
    var caption: String {
        switch self {
        case .loved:    "Buy it again"
        case .meh:      "No hurry to repeat"
        case .disliked: "Note it and move on"
        }
    }

    var dot: Color {
        switch self {
        case .loved:    Palette.green
        case .meh:      Palette.yellow
        case .disliked: Palette.red
        }
    }

    var foreground: Color {
        switch self {
        case .loved:    Color(red: 126/255, green: 214/255, blue: 153/255)
        case .meh:      Color(red: 240/255, green: 216/255, blue: 124/255)
        case .disliked: Color(red: 255/255, green: 166/255, blue: 168/255)
        }
    }

    var background: Color {
        switch self {
        case .loved:    Palette.green.opacity(0.22)
        case .meh:      Palette.yellow.opacity(0.16)
        case .disliked: Palette.red.opacity(0.20)
        }
    }
}

/// The five currencies the design offers.
enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case EUR, USD, GBP, CHF, SEK
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .EUR: "€"
        case .USD: "$"
        case .GBP: "£"
        case .CHF: "Fr"
        case .SEK: "kr"
        }
    }

    var name: String {
        switch self {
        case .EUR: "Euro"
        case .USD: "US dollar"
        case .GBP: "Pound sterling"
        case .CHF: "Swiss franc"
        case .SEK: "Swedish krona"
        }
    }

    /// `money()` in the design: SEK trails, everything else leads.
    /// CHF carries a thin space, matching the design's `SYM` table.
    func format(_ amount: String?) -> String {
        guard let amount, !amount.isEmpty else { return "—" }
        switch self {
        case .SEK: return "\(amount) kr"
        case .CHF: return "Fr\u{2009}\(amount)"
        default:   return "\(symbol)\(amount)"
        }
    }
}
