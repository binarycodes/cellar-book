import Observation
import SwiftUI

/// The design drives everything from one `screen` string plus a `sheet` string.
/// That is modelled directly here rather than with `NavigationStack`, because
/// every screen draws its own full-bleed chrome and none uses a system bar.
@Observable
@MainActor
final class AppState {
    enum Screen: Equatable { case cellar, search, scan, review, detail, tasting }
    enum Sheet: Equatable { case voice, currency, bought, delete, account }
    /// Which field the currency sheet is editing.
    enum CurrencyTarget: Equatable { case form, buy }
    /// Which note collection dictation is appending to.
    enum VoiceTarget: Equatable { case form, detail, tasting }

    var screen: Screen = .cellar
    var sheet: Sheet?

    /// The bottle the detail and tasting screens are showing.
    var selected: Wine?

    var filter: WineFilter = .all
    var searchFilter: WineFilter = .all
    var query: String = ""

    var currencyTarget: CurrencyTarget = .form
    var voiceTarget: VoiceTarget = .form

    /// Draft state for the Review screen, before the bottle exists.
    var form = WineForm()
    /// Set when the Review screen is editing a saved bottle rather than adding one.
    var editing: Wine?
    /// Draft state for the "Bought it" sheet.
    var buy = BuyForm()
    /// Draft state for the Tasting screen.
    var tasting = TastingForm()

    var toast: String?
    private var toastTask: Task<Void, Never>?

    func go(_ screen: Screen) {
        withAnimation(.easeOut(duration: 0.2)) {
            self.screen = screen
            self.sheet = nil
        }
    }

    func present(_ sheet: Sheet) {
        withAnimation(.easeOut(duration: 0.2)) { self.sheet = sheet }
    }

    func closeSheet() {
        withAnimation(.easeOut(duration: 0.2)) { self.sheet = nil }
    }

    /// Toasts clear themselves after 2.6s, as the design's `toast()` does.
    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }

    /// The scan button only shows on the two list screens.
    var showsNav: Bool { screen == .cellar || screen == .search }

    /// Clears navigation and every draft. Called on sign-out so a later
    /// session does not resume into the previous user's half-finished form.
    func reset() {
        screen = .cellar
        sheet = nil
        selected = nil
        filter = .all
        searchFilter = .all
        query = ""
        form = WineForm()
        buy = BuyForm()
        tasting = TastingForm()
        toastTask?.cancel()
        toast = nil
    }
}

/// The Review screen's draft. Mirrors the design's `form` object.
struct WineForm {
    var producer = ""
    var name = ""
    var vintage = ""
    var region = ""
    var grape = ""
    var shop = ""
    var price = ""
    var currency: CurrencyCode = .EUR
    var text = ""
    /// True when OCR found something, which shows the confirmation line.
    var recognized = false
    var labelPhoto: Data?
    /// Notes captured before the bottle is saved. `typed` records whether the
    /// note was written or spoken, so neither is labelled as the other.
    var notes: [(when: String, text: String, typed: Bool)] = []

    init() {}

    /// Only the producer gates a save: without it the card, the search index and
    /// the detail page have nothing to call the bottle. Everything else can be
    /// filled in later from the edit screen, which matters because this form is
    /// filled standing in a shop aisle — a blocked save there does not produce
    /// better data, it produces no data.
    var missingRequired: [String] {
        var missing: [String] = []
        if producer.isBlank { missing.append("the producer") }
        return missing
    }

    var isComplete: Bool { missingRequired.isEmpty }


    /// Builds the bottle this form describes. Lives on the form rather than
    /// inside the view's `save()` so the commit path — trimming, the blank-price
    /// sentinel, the hand-entry flag — is reachable from tests. It was not, and
    /// a mutation that dropped `.trimmed` went undetected.
    func makeWine() -> Wine {
        let wine = Wine(
            producer: producer.trimmed,
            name: name.trimmed,
            vintage: vintage.trimmed,
            region: region.trimmed,
            grape: grape.trimmed,
            shop: shop.trimmed,
            price: price.isBlank ? nil : price.trimmed,
            currency: currency,
            labelPhoto: labelPhoto
        )
        // Neither read off a label nor carrying one: the user typed it in.
        wine.addedByHand = !recognized && labelPhoto == nil
        return wine
    }

    /// Writes this form over a bottle already in the book. Mirrors `makeWine`
    /// field for field; the two must not drift.
    func apply(to wine: Wine) {
        wine.producer = producer.trimmed
        wine.name = name.trimmed
        wine.vintage = vintage.trimmed
        wine.region = region.trimmed
        wine.grape = grape.trimmed
        wine.shop = shop.trimmed
        wine.price = price.isBlank ? nil : price.trimmed
        wine.currency = currency
        wine.labelPhoto = labelPhoto
    }

    /// The notes this form has collected, ready to attach to a saved bottle.
    /// The typed note lands first, then anything dictated.
    func makeNotes() -> [TastingNote] {
        var out: [TastingNote] = []
        if !text.isBlank {
            out.append(TastingNote(kind: .text, phase: .pre, text: text.trimmed))
        }
        for dictated in notes {
            out.append(TastingNote(kind: dictated.typed ? .text : .voice, phase: .pre,
                                   text: dictated.text, when: dictated.when))
        }
        return out
    }

    /// Loads an existing bottle back into the form for editing. Notes are left
    /// alone — they are their own records with their own affordances.
    init(editing wine: Wine) {
        producer = wine.producer
        name = wine.name == "—" ? "" : wine.name
        vintage = wine.vintage
        region = wine.region
        grape = wine.grape
        shop = wine.shop
        price = wine.price ?? ""
        currency = wine.currency
        labelPhoto = wine.labelPhoto
    }

    init(reading: LabelReading, photo: Data?, currency: CurrencyCode) {
        producer = reading.producer
        name = reading.name
        vintage = reading.vintage
        region = reading.region
        grape = reading.grape
        recognized = reading.recognized
        labelPhoto = photo
        self.currency = currency
    }
}

/// The "Bought it" sheet's draft.
struct BuyForm {
    var date = Formatters.today()
    var qty = "1"
    var price = ""
    var currency: CurrencyCode = .EUR
    var shop = ""
}

/// The Tasting screen's draft.
struct TastingForm {
    var text = ""
    var verdict: Verdict?
    var pourPhoto: Data?
    var notes: [(when: String, text: String, typed: Bool)] = []

    mutating func reset() { self = TastingForm() }
}


extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "a", "a and b", "a, b and c" — for naming missing fields in prose.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
