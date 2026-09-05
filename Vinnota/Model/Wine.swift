import Foundation
import SwiftData
import SwiftUI

/// A note attached to a bottle, either typed or dictated, and taken either
/// before the bottle was opened (`pre`) or in the glass (`post`).
@Model
final class TastingNote {
    enum Kind: String, Codable { case text, voice }
    enum Phase: String, Codable { case pre, post }

    var kindRaw: String
    var phaseRaw: String
    var when: String
    var text: String
    var createdAt: Date

    var wine: Wine?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }
    var phase: Phase {
        get { Phase(rawValue: phaseRaw) ?? .pre }
        set { phaseRaw = newValue.rawValue }
    }

    /// "Dictated · 12 Aug · 18:40" / "Typed · …", as the detail screen renders it.
    var label: String { (kind == .voice ? "Dictated" : "Typed") + " · " + when }

    init(kind: Kind, phase: Phase, text: String, when: String = Formatters.stamp()) {
        self.kindRaw = kind.rawValue
        self.phaseRaw = phase.rawValue
        self.text = text
        self.when = when
        self.createdAt = Date()
    }
}

@Model
final class Wine {
    var producer: String
    var name: String
    var vintage: String
    var region: String
    var grape: String
    var shop: String

    /// Typed in rather than read off a label. The chip and the provenance line
    /// both used to claim "Scanned" for every bottle, which is a plain untruth
    /// for a hand-entered one.
    var addedByHand: Bool = false

    var statusRaw: String
    var verdictRaw: String?

    /// Shelf price — what the bottle was marked at when scanned.
    var price: String?
    var currencyRaw: String
    /// What was actually paid, which the design notes is "rarely the shelf price".
    var boughtPrice: String?
    var boughtCurrencyRaw: String
    var boughtDate: String?
    var qty: Int

    var scannedAt: String
    var openedAt: String?

    /// The label shot from the scanner, and the photo of the pour.
    @Attribute(.externalStorage) var labelPhoto: Data?
    @Attribute(.externalStorage) var pourPhoto: Data?

    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TastingNote.wine)
    var notes: [TastingNote] = []

    var status: WineStatus {
        get { WineStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }
    var verdict: Verdict? {
        get { verdictRaw.flatMap(Verdict.init(rawValue:)) }
        set { verdictRaw = newValue?.rawValue }
    }
    var currency: CurrencyCode {
        get { CurrencyCode(rawValue: currencyRaw) ?? .EUR }
        set { currencyRaw = newValue.rawValue }
    }
    var boughtCurrency: CurrencyCode {
        get { CurrencyCode(rawValue: boughtCurrencyRaw) ?? .EUR }
        set { boughtCurrencyRaw = newValue.rawValue }
    }

    init(producer: String, name: String, vintage: String, region: String,
         grape: String, shop: String, price: String? = nil,
         currency: CurrencyCode = .EUR, labelPhoto: Data? = nil) {
        self.producer = producer
        self.name = name
        self.vintage = vintage
        self.region = region
        self.grape = grape
        self.shop = shop
        self.price = price
        self.currencyRaw = currency.rawValue
        self.boughtCurrencyRaw = currency.rawValue
        self.statusRaw = WineStatus.new.rawValue
        self.qty = 1
        self.scannedAt = Formatters.today()
        self.createdAt = Date()
        self.labelPhoto = labelPhoto
    }

    // MARK: - Derived, mirroring the design's `rowOf` and `d` builders

    /// "NV" when there is no vintage, exactly as the design falls back.
    var hasVintage: Bool { !vintage.isBlank }
    var displayVintage: String { vintage }

    /// "Cuvée · Region" under the producer.
    var subtitle: String {
        [displayName, region].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The cuvée, or nothing — older rows stored an em dash for "none".
    var displayName: String { (name == "—" || name.isBlank) ? "" : name }

    /// Status chip copy. `.new` reads "Scanned", which only holds if it was.
    var statusLabel: String {
        if status == .new && addedByHand { return "Added by hand" }
        return status.label
    }

    /// "Grape · Region", the detail screen's eyebrow.
    var eyebrow: String { [grape, region].filter { !$0.isEmpty }.joined(separator: " · ") }

    /// Verdict colour wins over status colour wherever an accent is drawn.
    var accent: Color { verdict?.dot ?? status.rail }

    /// The design shows the paid price when there is one, else the shelf price.
    var displayPrice: String {
        boughtPrice != nil
            ? boughtCurrency.format(boughtPrice)
            : currency.format(price)
    }
    var hasPrice: Bool { (boughtPrice ?? price)?.isEmpty == false }

    var preNotes:  [TastingNote] { notes.filter { $0.phase == .pre  }.sorted { $0.createdAt < $1.createdAt } }
    var postNotes: [TastingNote] { notes.filter { $0.phase == .post }.sorted { $0.createdAt < $1.createdAt } }

    var isTasted: Bool { status == .tasted }
    var isBought: Bool { status == .bought }
    /// "Tasted bottles stay on the record. Only untasted ones can be deleted."
    var canDelete: Bool { !isTasted }
    /// The keenness segmented control is hidden once a bottle is bought or drunk.
    var showKeen: Bool { !isTasted && !isBought }

    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return [producer, name, region, grape, shop]
            .joined(separator: " ").lowercased().contains(q)
    }
}
