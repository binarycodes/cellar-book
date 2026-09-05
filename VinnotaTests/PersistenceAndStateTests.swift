import Foundation
import SwiftData
import Testing

@testable import Vinnota

// MARK: - Fixtures

/// A store that behaves like the real one — same schema, same relationship and
/// cascade rules — but lives only for the test.
private func newContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema([Wine.self, TastingNote.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}

/// A second `ModelContext` over the same store. Fetching through this one is a
/// genuine re-read: a single context hands back the instance it already has in
/// memory, which would let a field that never reached the store pass a
/// "round-trip" assertion.
private func reader(_ container: ModelContainer) -> ModelContext {
    ModelContext(container)
}

private func allWines(_ context: ModelContext) throws -> [Wine] {
    try context.fetch(FetchDescriptor<Wine>())
}

/// Notes are fetched as their own rows, never through `wine.notes` — an orphan
/// left behind by a failed cascade is invisible from the wine side by
/// definition.
private func allNotes(_ context: ModelContext) throws -> [TastingNote] {
    try context.fetch(FetchDescriptor<TastingNote>())
}

/// One megabyte with structure in it. A blob of repeated zeroes would survive a
/// truncation or a byte-order mangling unnoticed.
private func megabyte() -> Data {
    let block = Data((0..<1024).map { UInt8($0 & 0xFF) })
    var out = Data(capacity: 1024 * 1024)
    for _ in 0..<1024 { out.append(block) }
    return out
}

/// Every stored field set to something distinguishable, so a field dropped on
/// the way to the store shows up as a mismatch rather than as a coincidence.
private func fullyPopulated(labelPhoto: Data? = nil, pourPhoto: Data? = nil) -> Wine {
    let wine = Wine(producer: "Giuseppe Rinaldi", name: "Brunate", vintage: "2019",
                    region: "Barolo", grape: "Nebbiolo", shop: "Enoteca Sciolla",
                    price: "68.50", currency: .CHF, labelPhoto: labelPhoto)
    wine.addedByHand = true
    wine.status = .tasted
    wine.verdict = .loved
    wine.boughtPrice = "62"
    wine.boughtCurrency = .SEK
    wine.boughtDate = "14 Aug 2026"
    wine.qty = 3
    wine.scannedAt = "02 Aug 2026"
    wine.openedAt = "14 Aug 2026"
    wine.pourPhoto = pourPhoto
    return wine
}

// MARK: - Round-trip integrity

@Suite("SwiftData round trip · every field")
struct RoundTripTests {

    @Test("A fully populated bottle comes back out of the store identical")
    func everyFieldSurvives() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let original = fullyPopulated(labelPhoto: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                                      pourPhoto: Data([0x89, 0x50, 0x4E, 0x47]))
        write.insert(original)
        try write.save()

        let wines = try allWines(reader(container))
        #expect(wines.count == 1)
        let back = try #require(wines.first)

        #expect(back.producer == "Giuseppe Rinaldi")
        #expect(back.name == "Brunate")
        #expect(back.vintage == "2019")
        #expect(back.region == "Barolo")
        #expect(back.grape == "Nebbiolo")
        #expect(back.shop == "Enoteca Sciolla")
        #expect(back.addedByHand == true)
        #expect(back.statusRaw == WineStatus.tasted.rawValue)
        #expect(back.status == .tasted)
        #expect(back.verdictRaw == Verdict.loved.rawValue)
        #expect(back.verdict == .loved)
        #expect(back.price == "68.50")
        #expect(back.currencyRaw == "CHF")
        #expect(back.currency == .CHF)
        #expect(back.boughtPrice == "62")
        #expect(back.boughtCurrencyRaw == "SEK")
        #expect(back.boughtCurrency == .SEK)
        #expect(back.boughtDate == "14 Aug 2026")
        #expect(back.qty == 3)
        #expect(back.scannedAt == "02 Aug 2026")
        #expect(back.openedAt == "14 Aug 2026")
        #expect(back.labelPhoto == Data([0xFF, 0xD8, 0xFF, 0xE0]))
        #expect(back.pourPhoto == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(back.createdAt == original.createdAt)
    }

    /// The distinction the whole price line rests on: `nil` means "no price and
    /// none was ever entered", `""` means "the field was visited and left
    /// blank". `displayPrice` renders them identically but `hasPrice` does not,
    /// and a `nil` that came back as `""` would flip a fact on the detail page.
    @Test("An absent price stays nil and does not come back as an empty string")
    func absentOptionalsStayNil() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "")
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.price == nil)
        #expect(back.price != "")
        #expect(back.boughtPrice == nil)
        #expect(back.boughtDate == nil)
        #expect(back.openedAt == nil)
        #expect(back.verdictRaw == nil)
        #expect(back.verdict == nil)
        #expect(back.labelPhoto == nil)
        #expect(back.pourPhoto == nil)
        #expect(back.hasPrice == false)
    }

    /// `currency` is a computed bridge over `currencyRaw`. Setting the enum must
    /// land in the string column, and the string column is what the next launch
    /// reads back.
    @Test("Currency survives as its raw value in both currency columns",
          arguments: CurrencyCode.allCases)
    func currencyBridging(code: CurrencyCode) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", currency: code)
        wine.boughtCurrency = code
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.currencyRaw == code.rawValue)
        #expect(back.currency == code)
        #expect(back.boughtCurrencyRaw == code.rawValue)
        #expect(back.boughtCurrency == code)
    }

    @Test("Every status round-trips through its raw column",
          arguments: WineStatus.allCases)
    func statusBridging(status: WineStatus) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        wine.status = status
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.statusRaw == status.rawValue)
        #expect(back.status == status)
    }

    @Test("Every verdict round-trips, and clearing it writes a real nil",
          arguments: Verdict.allCases)
    func verdictBridging(verdict: Verdict) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        wine.verdict = verdict
        write.insert(wine)
        try write.save()

        let readBack = reader(container)
        let back = try #require(try allWines(readBack).first)
        #expect(back.verdictRaw == verdict.rawValue)
        #expect(back.verdict == verdict)

        back.verdict = nil
        try readBack.save()
        #expect(try #require(try allWines(reader(container)).first).verdictRaw == nil)
    }

    /// `createdAt` orders the note timeline, so sub-second precision is not
    /// decoration — two notes taken in the same minute must not collapse.
    @Test("Dates keep enough precision to order two notes taken together")
    func datePrecision() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        let first = TastingNote(kind: .text, phase: .pre, text: "first")
        let second = TastingNote(kind: .text, phase: .pre, text: "second")
        second.createdAt = first.createdAt.addingTimeInterval(0.001)
        first.wine = wine
        second.wine = wine
        write.insert(first)
        write.insert(second)
        try write.save()

        let notes = try allNotes(reader(container)).sorted { $0.createdAt < $1.createdAt }
        #expect(notes.count == 2)
        #expect(notes.first?.text == "first")
        #expect(notes.last?.text == "second")
        #expect(notes[0].createdAt < notes[1].createdAt)
    }
}

// MARK: - Photo blobs

@Suite("Photo blobs · external storage")
struct PhotoBlobTests {

    /// `.externalStorage` moves large values out of the row and leaves a
    /// reference behind. A blob that comes back short, reordered or nil is a
    /// silent loss of the only copy of the label shot.
    @Test("A megabyte label photo comes back byte for byte")
    func largeBlobSurvives() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let blob = megabyte()
        #expect(blob.count == 1_048_576)

        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", labelPhoto: blob)
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        let out = try #require(back.labelPhoto)
        #expect(out.count == blob.count)
        #expect(out == blob)
        #expect(out.first == blob.first)
        #expect(out.last == blob.last)
    }

    @Test("Both photo columns can hold a megabyte at once and stay distinct")
    func twoLargeBlobsDoNotCrossOver() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        var label = megabyte()
        label[0] = 0xAA
        var pour = megabyte()
        pour[0] = 0xBB

        let wine = fullyPopulated(labelPhoto: label, pourPhoto: pour)
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.labelPhoto?.first == 0xAA)
        #expect(back.pourPhoto?.first == 0xBB)
        #expect(back.labelPhoto == label)
        #expect(back.pourPhoto == pour)
        #expect(back.labelPhoto != back.pourPhoto)
    }

    /// An empty `Data` is not the same fact as no data: the detail hero draws a
    /// photo box for one and collapses for the other. `UIImage(data:)` fails on
    /// both, so an empty blob shows an empty frame — but the model must at
    /// least report it faithfully rather than folding it into nil.
    @Test("An empty Data blob stays empty rather than becoming nil")
    func emptyBlobIsNotNil() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", labelPhoto: Data())
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.labelPhoto != nil, "documented current behaviour")
        #expect(back.labelPhoto?.isEmpty == true)
        #expect(back.labelPhoto?.count == 0)
    }

    @Test("A photo can be replaced and cleared without disturbing the other one")
    func blobsCanBeClearedIndependently() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated(labelPhoto: Data([1, 2, 3]), pourPhoto: Data([9, 9]))
        write.insert(wine)
        try write.save()

        let editContext = reader(container)
        let mid = try #require(try allWines(editContext).first)
        mid.labelPhoto = Data([4, 5, 6, 7])
        try editContext.save()
        #expect(try #require(try allWines(reader(container)).first).labelPhoto == Data([4, 5, 6, 7]))

        mid.labelPhoto = nil
        try editContext.save()
        let final = try #require(try allWines(reader(container)).first)
        #expect(final.labelPhoto == nil)
        #expect(final.pourPhoto == Data([9, 9]), "clearing one photo must not touch the other")
    }

    /// Bytes that are not valid text, and bytes that would be mangled by any
    /// string round trip. Photo data is arbitrary binary and must be treated as
    /// such.
    @Test("Non-UTF8 and null bytes survive a save")
    func binarySafeBytes() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let blob = Data([0x00, 0xFF, 0xFE, 0x00, 0x80, 0xC0, 0x0A, 0x0D, 0x1A, 0x00])
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", labelPhoto: blob)
        write.insert(wine)
        try write.save()

        #expect(try #require(try allWines(reader(container)).first).labelPhoto == blob)
    }
}

// MARK: - Relationships and cascade

@Suite("Notes · relationship, split and cascade")
struct RelationshipTests {

    private func wineWithNotes(_ context: ModelContext) -> Wine {
        let wine = fullyPopulated()
        context.insert(wine)
        for (index, spec) in [(TastingNote.Phase.pre, "smells like the shop"),
                              (.pre, "second thought before opening"),
                              (.post, "better in the second glass"),
                              (.post, "still going an hour later")].enumerated() {
            let note = TastingNote(kind: index.isMultiple(of: 2) ? .text : .voice,
                                   phase: spec.0, text: spec.1)
            note.createdAt = Date().addingTimeInterval(Double(index))
            note.wine = wine
            context.insert(note)
        }
        return wine
    }

    @Test("Notes attached before the save are all there afterwards")
    func notesSurviveTheSave() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        _ = wineWithNotes(write)
        try write.save()

        let read = reader(container)
        #expect(try allNotes(read).count == 4)
        let back = try #require(try allWines(read).first)
        #expect(back.notes.count == 4)
        #expect(Set(back.notes.map(\.text)).count == 4)
    }

    @Test("The inverse is populated in both directions after a re-read")
    func inverseIsWiredBothWays() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        _ = wineWithNotes(write)
        try write.save()

        let read = reader(container)
        let wine = try #require(try allWines(read).first)
        for note in try allNotes(read) {
            #expect(note.wine != nil)
            #expect(note.wine?.persistentModelID == wine.persistentModelID)
        }
    }

    @Test("preNotes and postNotes split by phase and sort by creation time")
    func phaseSplitSurvivesTheStore() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        _ = wineWithNotes(write)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.preNotes.count == 2)
        #expect(back.postNotes.count == 2)
        #expect(back.preNotes.map(\.text) == ["smells like the shop",
                                              "second thought before opening"])
        #expect(back.postNotes.map(\.text) == ["better in the second glass",
                                               "still going an hour later"])
        #expect(back.preNotes.allSatisfy { $0.phase == .pre })
        #expect(back.postNotes.allSatisfy { $0.phase == .post })
        #expect(back.preNotes.count + back.postNotes.count == back.notes.count)
    }

    @Test("Note kind round-trips, so a typed note is never labelled Dictated")
    func kindSurvivesTheStore() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        let typed = TastingNote(kind: .text, phase: .pre, text: "typed", when: "05 Sep · 14:32")
        let spoken = TastingNote(kind: .voice, phase: .pre, text: "spoken", when: "05 Sep · 14:33")
        typed.wine = wine
        spoken.wine = wine
        write.insert(typed)
        write.insert(spoken)
        try write.save()

        let notes = try allNotes(reader(container))
        let byText = Dictionary(uniqueKeysWithValues: notes.map { ($0.text, $0) })
        #expect(byText["typed"]?.kind == .text)
        #expect(byText["typed"]?.label == "Typed · 05 Sep · 14:32")
        #expect(byText["spoken"]?.kind == .voice)
        #expect(byText["spoken"]?.label == "Dictated · 05 Sep · 14:33")
    }

    /// The cascade is the reason deleting a bottle is safe at all. Asserted by
    /// fetching `TastingNote` directly: an orphan is by construction not
    /// reachable from the wine that no longer exists.
    @Test("Deleting a wine cascades to its notes and leaves no orphans")
    func cascadeLeavesNoOrphans() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        let wine = wineWithNotes(write)
        try write.save()
        #expect(try allNotes(reader(container)).count == 4)

        write.delete(wine)
        try write.save()

        let after = reader(container)
        #expect(try allWines(after).isEmpty)
        #expect(try allNotes(after).isEmpty, "a surviving note is an orphan row")
    }

    @Test("Deleting one bottle leaves the other bottle's notes untouched")
    func cascadeIsScopedToOneWine() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        let doomed = wineWithNotes(write)
        let keeper = wineWithNotes(write)
        keeper.producer = "Keeper"
        try write.save()
        #expect(try allNotes(reader(container)).count == 8)

        write.delete(doomed)
        try write.save()

        let after = reader(container)
        #expect(try allWines(after).count == 1)
        #expect(try allWines(after).first?.producer == "Keeper")
        #expect(try allNotes(after).count == 4)
        #expect(try allNotes(after).allSatisfy { $0.wine != nil })
    }

    @Test("Deleting a note does not take the bottle with it")
    func deletingANoteDoesNotCascadeUpwards() throws {
        let container = try newContainer()
        let write = ModelContext(container)
        _ = wineWithNotes(write)
        try write.save()

        let read = reader(container)
        let note = try #require(try allNotes(read).first)
        read.delete(note)
        try read.save()

        let after = reader(container)
        #expect(try allWines(after).count == 1)
        #expect(try allNotes(after).count == 3)
        #expect(try #require(try allWines(after).first).notes.count == 3)
    }

    @Test("Reassigning a note moves it between bottles rather than duplicating it")
    func reassigningANoteDoesNotDuplicateIt() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let a = fullyPopulated()
        a.producer = "A"
        let b = fullyPopulated()
        b.producer = "B"
        write.insert(a)
        write.insert(b)
        let note = TastingNote(kind: .text, phase: .pre, text: "moves")
        note.wine = a
        write.insert(note)
        try write.save()

        note.wine = b
        try write.save()

        let after = reader(container)
        #expect(try allNotes(after).count == 1)
        let wines = try allWines(after)
        #expect(wines.first { $0.producer == "A" }?.notes.isEmpty == true)
        #expect(wines.first { $0.producer == "B" }?.notes.count == 1)
    }
}

// MARK: - Forward compatibility

@Suite("Unknown raw values · an older build reading a newer store")
struct RawValueFallbackTests {

    /// A status written by a future build ("cellared", say) must not crash the
    /// read. It falls back to `.new`.
    @Test("An unknown statusRaw falls back to .new instead of trapping",
          arguments: ["cellared", "", " ", "NEW", "new ", "1", "null",
                      "'; DROP TABLE ZWINE; --", "\u{1F377}"])
    func unknownStatus(raw: String) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        wine.statusRaw = raw
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.statusRaw == raw, "the unknown value is preserved, not rewritten")
        #expect(back.status == .new)
        #expect(back.verdict == .loved, "the verdict column is untouched and still supplies the accent")
    }

    /// FINDING: Vinnota/Model/Wine.swift:80 — the fallback is `.new`, which is
    /// the *most* permissive state. `canDelete` is `!isTasted`
    /// (Wine.swift:155) and `isTasted` reads the fallback, so a bottle whose
    /// status column this build cannot parse gets the trash icon back even if
    /// it was drunk. The guard "tasted bottles stay on the record" is only as
    /// strong as the raw string.
    ///
    /// Reachability: this build never writes an unparseable status — the only
    /// writers are `Wine.init` and the `status` setter, both of which write a
    /// `WineStatus.rawValue`. It takes a store written by a later build with a
    /// new case (then opened by this one), or a damaged row. That is a real
    /// forward-compatibility path for a local SwiftData store that survives app
    /// updates, but it is not reachable from this build alone. The safe
    /// fallback for a *guard* is the restrictive end: an unreadable status
    /// should not re-arm deletion.
    @Test("FINDING: an unknown status re-arms the delete button on a tasted bottle")
    func unknownStatusReopensDeletion() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        #expect(wine.status == .tasted)
        #expect(wine.canDelete == false)

        write.insert(wine)
        wine.statusRaw = "cellared"
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.status == .new, "documented current behaviour")
        #expect(back.isTasted == false)
        #expect(back.canDelete, "documented current behaviour — deletion is re-armed")
        // `fullyPopulated` sets `addedByHand`, so `.new` renders as the
        // hand-entry chip here; a scanned bottle would read "Scanned". Either
        // way the chip claims the bottle was never opened.
        #expect(back.statusLabel == "Added by hand")
    }

    /// `WineFilter.matches` compares against `wine.status.rawValue` — the
    /// fallback — and not against the stored column, so a bottle carrying a
    /// status this build cannot read is filed under "Scanned" rather than
    /// disappearing from every tab. Losing a bottle from the cellar list would
    /// be worse; being told a tasted bottle was merely scanned is what actually
    /// happens.
    @Test("An unknown statusRaw files the bottle under the Scanned tab")
    func unknownStatusFiltersAsScanned() throws {
        let wine = fullyPopulated()
        wine.statusRaw = "cellared"
        #expect(WineFilter.all.matches(wine), "never lost from the cellar list")
        #expect(WineFilter.new.matches(wine), "documented current behaviour")
        for filter in WineFilter.allCases where filter != .all && filter != .new {
            #expect(filter.matches(wine) == false,
                    "\(filter.rawValue) must not claim a bottle it cannot read")
        }
        #expect(WineFilter.tasted.matches(wine) == false,
                "though the bottle was tasted before this build read it")
    }

    @Test("An unknown verdictRaw reads as no verdict rather than trapping",
          arguments: ["adored", "", "LOVED", "loved ", "0", "\u{202E}dellac"])
    func unknownVerdict(raw: String) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        wine.verdictRaw = raw
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.verdictRaw == raw)
        #expect(back.verdict == nil)
        #expect(back.status == .tasted, "the status column is untouched and now supplies the accent")
    }

    /// A currency this build does not know must not silently reprice the
    /// bottle. It cannot: the amount is a string and only the symbol changes.
    @Test("An unknown currencyRaw falls back to EUR and leaves the amount alone",
          arguments: ["JPY", "XBT", "", "eur", "EUR ", "$", "€"])
    func unknownCurrency(raw: String) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        wine.currencyRaw = raw
        wine.boughtCurrencyRaw = raw
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.currencyRaw == raw)
        #expect(back.currency == .EUR)
        #expect(back.boughtCurrency == .EUR)
        #expect(back.price == "68.50", "the amount is untouched by the currency fallback")
        #expect(back.boughtPrice == "62")
        #expect(back.displayPrice == "€62", "shown in the fallback currency, not the unknown one")
    }

    /// FINDING: Vinnota/Model/Wine.swift:88 — an unknown currency is displayed
    /// as euros with no marker that the code was not understood. A CHF bottle
    /// whose currency column is corrupted prints "€62", which is a wrong number
    /// rather than a missing one.
    @Test("FINDING: an unknown currency silently reprints the amount as euros")
    func unknownCurrencyMisstatesTheCurrency() throws {
        let wine = fullyPopulated()
        wine.boughtCurrencyRaw = "JPY"
        #expect(wine.boughtPrice == "62")
        #expect(wine.displayPrice == "€62", "documented current behaviour")
        #expect(wine.displayPrice != "¥62")
        #expect(wine.displayPrice.contains("JPY") == false)
    }

    @Test("An unknown note kind or phase falls back rather than trapping",
          arguments: ["shouted", "", "TEXT", "pre "])
    func unknownNoteRaws(raw: String) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        let note = TastingNote(kind: .voice, phase: .post, text: "n")
        note.wine = wine
        write.insert(note)
        note.kindRaw = raw
        note.phaseRaw = raw
        try write.save()

        let back = try #require(try allNotes(reader(container)).first)
        #expect(back.kind == .text, "kind falls back to .text")
        #expect(back.phase == .pre, "phase falls back to .pre")
        #expect(back.label.hasPrefix("Typed · "))
    }

    /// The phase fallback is not free: a post-tasting note whose phase column is
    /// unreadable is re-filed under "Before opening" on the detail page.
    @Test("An unreadable phase moves a post note into the pre column")
    func unknownPhaseMovesTheNote() throws {
        let wine = fullyPopulated()
        let note = TastingNote(kind: .text, phase: .post, text: "in the glass")
        note.wine = wine
        wine.notes = [note]
        #expect(wine.postNotes.count == 1)

        note.phaseRaw = "during"
        #expect(wine.postNotes.isEmpty, "documented current behaviour")
        #expect(wine.preNotes.count == 1)
    }

    /// Writing through the typed property normalises a corrupt column, which is
    /// the only self-healing the model has.
    @Test("Assigning the typed property rewrites a corrupt raw column")
    func writingThroughTheBridgeHeals() throws {
        let wine = fullyPopulated()
        wine.statusRaw = "cellared"
        wine.currencyRaw = "JPY"
        wine.verdictRaw = "adored"

        wine.status = .bought
        wine.currency = .GBP
        wine.verdict = .meh

        #expect(wine.statusRaw == "bought")
        #expect(wine.currencyRaw == "GBP")
        #expect(wine.verdictRaw == "meh")
    }
}

// MARK: - Store growth

@Suite("Store growth · no duplicate rows")
struct StoreGrowthTests {

    @Test("Saving the same bottle ten times leaves one row")
    func repeatedSavesDoNotDuplicate() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        for index in 0..<10 {
            wine.qty = index
            try write.save()
        }

        let after = reader(container)
        #expect(try allWines(after).count == 1)
        #expect(try allWines(after).first?.qty == 9)
    }

    @Test("Inserting the same instance repeatedly does not duplicate it")
    func repeatedInsertsDoNotDuplicate() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        for _ in 0..<5 { write.insert(wine) }
        try write.save()

        #expect(try allWines(reader(container)).count == 1)
    }

    /// A photo rewritten on every save — which is what re-picking a pour photo
    /// does — must replace the blob, not accumulate copies visible as extra
    /// rows.
    @Test("Rewriting the photo repeatedly keeps one row and the last blob")
    func rewritingBlobsDoesNotGrowTheStore() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        for index in UInt8(0)..<UInt8(8) {
            wine.pourPhoto = Data(repeating: index, count: 4096)
            try write.save()
        }

        let after = reader(container)
        #expect(try allWines(after).count == 1)
        #expect(try #require(try allWines(after).first).pourPhoto == Data(repeating: 7, count: 4096))
    }

    @Test("Two distinct bottles with identical contents are two rows")
    func identicalContentIsNotDeduplicated() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        write.insert(fullyPopulated())
        write.insert(fullyPopulated())
        try write.save()

        #expect(try allWines(reader(container)).count == 2)
    }

    @Test("Adding notes to a saved bottle does not re-add the bottle")
    func addingNotesDoesNotDuplicateTheWine() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = fullyPopulated()
        write.insert(wine)
        try write.save()

        for index in 0..<6 {
            let note = TastingNote(kind: .text, phase: .post, text: "note \(index)")
            note.wine = wine
            write.insert(note)
            try write.save()
        }

        let after = reader(container)
        #expect(try allWines(after).count == 1)
        #expect(try allNotes(after).count == 6)
    }
}

// MARK: - Price fields are free text

@Suite("Price fields · free text, never parsed")
struct PriceStorageTests {

    /// Every one of these is typeable, and several are pasteable from a
    /// currency converter. The store keeps a `String`, so the property to lock
    /// down is that nothing anywhere silently reinterprets it as a number.
    @Test("What is typed is exactly what is stored", arguments: [
        "-45",              // a decimal pad has no minus, but a paste does
        "1e309",            // overflows Double — must never reach one
        "NaN",
        "Infinity",
        "1,234.56",         // US thousands separator
        "1.234,56",         // European thousands separator
        "12,50",            // European decimal comma — this will be typed
        "€45",              // the symbol typed into the amount field
        "45 €",
        "0",
        "00045",
        "45.",
        ".50",
        "45.000000000000001",
        "9999999999999999999999999999",
        "45 CHF",
        "  45  ",
    ])
    func amountsAreStoredVerbatim(typed: String) throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", price: typed, currency: .EUR)
        wine.boughtPrice = typed
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.price == typed)
        #expect(back.boughtPrice == typed)
    }

    /// FINDING: Vinnota/Model/Enums.swift:129 — `format` prepends the symbol
    /// unconditionally, so a user who types the currency symbol into the amount
    /// field (an easy mistake, and the paste of a whole price string) gets it
    /// twice. Nothing strips or rejects it on the way in.
    @Test("FINDING: a currency symbol typed into the amount is printed twice")
    func doubledCurrencySymbol() {
        #expect(CurrencyCode.EUR.format("€45") == "€€45", "documented current behaviour")
        #expect(CurrencyCode.USD.format("$45") == "$$45", "documented current behaviour")
        #expect(CurrencyCode.SEK.format("45 kr") == "45 kr kr", "documented current behaviour")
    }

    /// FINDING: Vinnota/Model/Enums.swift:129 and Vinnota/Model/AppState.swift:145
    /// — nothing rejects a negative amount. `price.isBlank ? nil : price.trimmed`
    /// is the only gate the commit path applies, so "-45" is stored and the
    /// detail page reads "paid €-45".
    @Test("FINDING: a negative amount is accepted and displayed as one")
    func negativeAmountIsAccepted() throws {
        var form = WineForm()
        form.producer = "Rinaldi"
        form.price = "-45"
        let wine = form.makeWine()
        #expect(wine.price == "-45", "documented current behaviour")
        #expect(wine.displayPrice == "€-45", "documented current behaviour")
        #expect(wine.hasPrice)
    }

    /// Padding is trimmed on the commit path but not by the model, so where a
    /// price is written matters. The "Bought it" sheet writes `wine.boughtPrice`
    /// straight from the field.
    @Test("The commit path trims the shelf price; a raw assignment does not")
    func trimmingIsAPropertyOfTheCommitPathOnly() {
        var form = WineForm()
        form.producer = "Rinaldi"
        form.price = "  45  "
        #expect(form.makeWine().price == "45")

        let wine = form.makeWine()
        wine.boughtPrice = "  45  "
        #expect(wine.boughtPrice == "  45  ")
        #expect(wine.displayPrice == "€  45  ", "documented current behaviour")
    }

    @Test("A very long amount neither crashes nor is truncated by the store")
    func absurdlyLongAmount() throws {
        let container = try newContainer()
        let write = ModelContext(container)

        let long = String(repeating: "9", count: 5_000)
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", price: long)
        write.insert(wine)
        try write.save()

        let back = try #require(try allWines(reader(container)).first)
        #expect(back.price?.count == 5_000)
        #expect(back.price == long)
        #expect(back.displayPrice.count == 5_001)
    }
}

// MARK: - AppState navigation

@MainActor
@Suite("AppState · navigation and sheets")
struct NavigationTests {

    @Test("A fresh state opens on the cellar with nothing presented")
    func initialState() {
        let app = AppState()
        #expect(app.screen == .cellar)
        #expect(app.sheet == nil)
        #expect(app.selected == nil)
        #expect(app.editing == nil)
        #expect(app.filter == .all)
        #expect(app.searchFilter == .all)
        #expect(app.query.isEmpty)
        #expect(app.toast == nil)
        #expect(app.currencyTarget == .form)
        #expect(app.voiceTarget == .form)
        #expect(app.showsNav)
    }

    @Test("go() moves to the requested screen",
          arguments: [AppState.Screen.cellar, .search, .scan, .review, .detail, .tasting])
    func goSetsTheScreen(screen: AppState.Screen) {
        let app = AppState()
        app.go(screen)
        #expect(app.screen == screen)
    }

    /// Navigating out from under an open sheet must take the sheet with it,
    /// otherwise a currency picker stays on top of the cellar.
    @Test("go() dismisses whatever sheet is open",
          arguments: [AppState.Sheet.voice, .currency, .bought, .delete, .account])
    func goClosesTheSheet(sheet: AppState.Sheet) {
        let app = AppState()
        app.present(sheet)
        #expect(app.sheet == sheet)
        app.go(.detail)
        #expect(app.sheet == nil)
        #expect(app.screen == .detail)
    }

    @Test("present() and closeSheet() are symmetric",
          arguments: [AppState.Sheet.voice, .currency, .bought, .delete, .account])
    func sheetLifecycle(sheet: AppState.Sheet) {
        let app = AppState()
        app.present(sheet)
        #expect(app.sheet == sheet)
        app.closeSheet()
        #expect(app.sheet == nil)
    }

    @Test("Presenting a second sheet replaces the first rather than stacking")
    func sheetsDoNotStack() {
        let app = AppState()
        app.present(.bought)
        app.present(.currency)
        #expect(app.sheet == .currency)
        app.closeSheet()
        #expect(app.sheet == nil, "closing must not reveal the sheet underneath")
    }

    @Test("closeSheet() on nothing is a no-op")
    func closingNothingIsSafe() {
        let app = AppState()
        app.closeSheet()
        #expect(app.sheet == nil)
        #expect(app.screen == .cellar)
    }

    /// The scan button is drawn only where a list is showing.
    @Test("showsNav is true only on the two list screens",
          arguments: [(AppState.Screen.cellar, true), (.search, true), (.scan, false),
                      (.review, false), (.detail, false), (.tasting, false)])
    func navVisibility(screen: AppState.Screen, expected: Bool) {
        let app = AppState()
        app.go(screen)
        #expect(app.showsNav == expected)
    }

    /// The screen does not clear `selected`: the tasting screen navigates back
    /// to the detail screen for the same bottle, which depends on it surviving.
    @Test("go() keeps the selected bottle")
    func selectionSurvivesNavigation() {
        let app = AppState()
        let wine = fullyPopulated()
        app.selected = wine
        app.go(.tasting)
        app.go(.detail)
        #expect(app.selected === wine)
    }

    @Test("The two filter tabs are independent")
    func cellarAndSearchFiltersAreSeparate() {
        let app = AppState()
        app.filter = .bought
        app.searchFilter = .tasted
        #expect(app.filter == .bought)
        #expect(app.searchFilter == .tasted)
        app.go(.search)
        #expect(app.filter == .bought, "navigating does not reset either tab")
        #expect(app.searchFilter == .tasted)
    }
}

// MARK: - AppState toast

@MainActor
@Suite("AppState · toast lifecycle")
struct ToastTests {

    @Test("A toast is shown immediately")
    func toastAppears() {
        let app = AppState()
        app.showToast("In the rack")
        #expect(app.toast == "In the rack")
    }

    @Test("A second toast replaces the first")
    func toastsReplaceEachOther() {
        let app = AppState()
        app.showToast("first")
        app.showToast("second")
        #expect(app.toast == "second")
    }

    /// Polls rather than sleeping a fixed span: the assertion is "it becomes
    /// nil", and on a contended CI runner a fixed sleep sized to the real 2.6s
    /// lifetime has too little margin. This failed in CI for exactly that
    /// reason, on a run that took 312s against 4s locally.
    private func waitForToastToClear(_ app: AppState,
                                     within limit: Duration = .seconds(15)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while ContinuousClock.now < deadline {
            if app.toast == nil { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return app.toast == nil
    }

    /// The replacement cancels the first toast's timer. Without that, the
    /// earlier timer would fire mid-way through the second toast and blank it.
    ///
    /// The two lifetimes are deliberately far apart — the first expires almost
    /// at once, the second not for half a minute — so the check cannot flake on
    /// a slow machine. A delayed wake makes the first timer *more* likely to
    /// have fired, not less, so slowness cannot mask the bug.
    @Test("The replaced toast's timer does not blank its successor", .timeLimit(.minutes(1)))
    func replacementCancelsTheOldTimer() async throws {
        let app = AppState()
        app.showToast("first", for: .milliseconds(50))
        app.showToast("second", for: .seconds(30))
        try await Task.sleep(for: .seconds(1))
        #expect(app.toast == "second",
                "the first toast's timer was due long ago and must have been cancelled")
    }

    @Test("A toast clears itself when its life is up", .timeLimit(.minutes(1)))
    func toastExpires() async throws {
        let app = AppState()
        app.showToast("Added to the book", for: .milliseconds(50))
        #expect(app.toast != nil, "the toast is visible before its timer fires")
        #expect(await waitForToastToClear(app), "the toast never cleared itself")
    }

    /// The shipped lifetime is still the design's 2.6s — the parameter above is
    /// a test seam, not a behaviour change, and this pins the default.
    @Test("The default lifetime is unchanged")
    func defaultLifetimeIsTwoPointSix() async throws {
        let app = AppState()
        app.showToast("Added to the book")
        try await Task.sleep(for: .seconds(1))
        #expect(app.toast != nil, "a 2.6s toast is still up after 1s")
    }

    @Test("reset() clears a live toast at once")
    func resetClearsTheToast() {
        let app = AppState()
        app.showToast("Changes saved")
        app.reset()
        #expect(app.toast == nil)
    }
}

// MARK: - AppState reset

@MainActor
@Suite("AppState.reset · the sign-out path")
struct ResetTests {

    private func dirtied() -> AppState {
        let app = AppState()
        app.screen = .tasting
        app.sheet = .bought
        app.selected = fullyPopulated()
        app.filter = .bought
        app.searchFilter = .tasted
        app.query = "rinaldi"
        app.currencyTarget = .buy
        app.voiceTarget = .tasting
        app.form.producer = "Half typed"
        app.form.price = "45"
        app.form.notes = [(when: "05 Sep · 14:32", text: "draft", typed: true)]
        app.buy.price = "62"
        app.buy.shop = "Enoteca"
        app.tasting.text = "half a tasting note"
        app.tasting.verdict = .loved
        app.editing = fullyPopulated()
        return app
    }

    @Test("Navigation, selection and search all go back to their defaults")
    func navigationIsCleared() {
        let app = dirtied()
        app.reset()
        #expect(app.screen == .cellar)
        #expect(app.sheet == nil)
        #expect(app.selected == nil)
        #expect(app.filter == .all)
        #expect(app.searchFilter == .all)
        #expect(app.query.isEmpty)
    }

    @Test("Every draft form is emptied")
    func draftsAreCleared() {
        let app = dirtied()
        app.reset()
        #expect(app.form.producer.isEmpty)
        #expect(app.form.price.isEmpty)
        #expect(app.form.notes.isEmpty)
        #expect(app.form.labelPhoto == nil)
        #expect(app.buy.price.isEmpty)
        #expect(app.buy.shop.isEmpty)
        #expect(app.buy.qty == "1")
        #expect(app.tasting.text.isEmpty)
        #expect(app.tasting.verdict == nil)
        #expect(app.tasting.pourPhoto == nil)
        #expect(app.tasting.notes.isEmpty)
    }

    /// FINDING: Vinnota/Model/AppState.swift:73 — `reset()` clears `form`,
    /// `buy`, `tasting` and `selected`, but never `editing`. The comment on the
    /// method says it exists "so a later session does not resume into the
    /// previous user's half-finished form", and this is exactly the pointer
    /// that breaks that promise. It also keeps the signed-out user's `Wine`
    /// alive for the whole of the next session.
    ///
    /// NOT REACHABLE TODAY, and the difference matters. Signing out runs only
    /// from `AccountSheet` (Vinnota/Views/Sheets/AccountSheet.swift:101), which
    /// is presented from exactly one place — the cellar header avatar
    /// (Vinnota/Views/CellarView.swift:33). `editing` is set in exactly one
    /// place, the detail screen's pencil (Vinnota/Views/DetailView.swift:101),
    /// which moves straight to `.review` in the same closure; and both ways off
    /// the review screen — `leave()` (ReviewView.swift:108) and the editing
    /// branch of `save()` (ReviewView.swift:262) — nil it out before
    /// navigating. So no route reaches the cellar, and therefore the sign-out
    /// button, with `editing` still set.
    ///
    /// It is a latent hazard rather than a live one: the moment a second entry
    /// point to the account sheet appears (a search-screen avatar, a settings
    /// row on the review screen, a revoked-credential sign-out), the write in
    /// `staleEditingSurvivesAFreshForm` below becomes real. `reset()` should
    /// clear `editing` regardless — every other draft pointer it holds is
    /// cleared, and this is the only one whose survival can overwrite a row.
    @Test("FINDING: reset() leaves `editing` pointing at the previous bottle")
    func resetDoesNotClearEditing() {
        let app = dirtied()
        let stale = app.editing
        app.reset()
        #expect(app.editing != nil, "documented current behaviour")
        #expect(app.editing === stale, "still the pre-sign-out bottle")
        #expect(app.selected == nil, "while `selected` — the read-only pointer — was cleared")
    }

    /// The same pointer viewed from the other side: a fresh form plus a stale
    /// `editing` is precisely the state the scanner hands the Review screen
    /// (Vinnota/Views/ScanView.swift:147 and :197 replace `form` without
    /// touching `editing`). The overwrite is spelled out by calling
    /// `apply(to:)` directly, which is the line `ReviewView.save()` runs when
    /// `app.editing != nil` — the view itself is not exercised, and, as the
    /// test above records, no real navigation reaches this state today.
    @Test("FINDING: a reset state still reads as 'editing' to the Review screen")
    func staleEditingSurvivesAFreshForm() {
        let app = dirtied()
        let victim = app.editing
        app.reset()

        // What ScanView does on the way to the review screen.
        app.form = WineForm()
        app.form.producer = "A completely different producer"
        app.go(.review)

        #expect(app.editing != nil, "documented current behaviour: isEditing is true")
        #expect(app.editing === victim)

        // And what ReviewView.save() would then do with it.
        app.form.apply(to: try! #require(app.editing))
        #expect(victim?.producer == "A completely different producer",
                "the wrong bottle has been overwritten")
    }

    /// `reset()` drops the app's reference to the bottle; it must not delete it.
    @Test("reset() does not touch the store")
    func resetDoesNotDeleteAnything() throws {
        let container = try newContainer()
        let context = ModelContext(container)
        let wine = fullyPopulated()
        context.insert(wine)
        try context.save()

        let app = AppState()
        app.selected = wine
        app.editing = wine
        app.reset()

        #expect(try allWines(reader(container)).count == 1)
    }
}

// MARK: - BuyForm

@Suite("BuyForm")
struct BuyFormTests {

    /// The sheet opens pre-filled: today's date, one bottle, no price yet.
    @Test("Defaults match what the sheet is expected to show")
    func defaults() {
        let form = BuyForm()
        #expect(form.date == Formatters.today())
        #expect(form.qty == "1")
        #expect(form.price.isEmpty)
        #expect(form.currency == .EUR)
        #expect(form.shop.isEmpty)
    }
}

// MARK: - TastingForm

@Suite("TastingForm")
struct TastingFormTests {

    @Test("Defaults are empty across the board")
    func defaults() {
        let form = TastingForm()
        #expect(form.text.isEmpty)
        #expect(form.verdict == nil)
        #expect(form.pourPhoto == nil)
        #expect(form.notes.isEmpty)
    }

    /// Every stored property, one by one. A field added later and left out of
    /// `reset()` would leak the previous bottle's tasting into the next one —
    /// the pour photo most visibly, since it becomes the detail hero.
    @Test("reset() clears every field, enumerated")
    func resetClearsEverything() {
        var form = TastingForm()
        form.text = "Tar and roses, and then some."
        form.verdict = .disliked
        form.pourPhoto = Data([1, 2, 3, 4])
        form.notes = [(when: "05 Sep · 20:10", text: "first glass", typed: false),
                      (when: "05 Sep · 21:40", text: "second glass", typed: true)]

        form.reset()

        #expect(form.text.isEmpty)
        #expect(form.text == "")
        #expect(form.verdict == nil)
        #expect(form.pourPhoto == nil)
        #expect(form.notes.isEmpty)
        #expect(form.notes.count == 0)
    }

    @Test("Resetting through AppState clears the draft on the state itself")
    func resetThroughAppState() async {
        await MainActor.run {
            let app = AppState()
            app.tasting.text = "leaked"
            app.tasting.verdict = .meh
            app.tasting.pourPhoto = Data([9])
            app.tasting.notes = [(when: "w", text: "t", typed: false)]
            app.tasting.reset()
            #expect(app.tasting.text.isEmpty)
            #expect(app.tasting.verdict == nil)
            #expect(app.tasting.pourPhoto == nil)
            #expect(app.tasting.notes.isEmpty)
        }
    }
}

// MARK: - WineForm defaults

@Suite("WineForm defaults and photo carry-over")
struct WineFormDefaultsTests {

    @Test("A new form is empty and not marked as recognised")
    func defaults() {
        let form = WineForm()
        #expect(form.producer.isEmpty)
        #expect(form.name.isEmpty)
        #expect(form.vintage.isEmpty)
        #expect(form.region.isEmpty)
        #expect(form.grape.isEmpty)
        #expect(form.shop.isEmpty)
        #expect(form.price.isEmpty)
        #expect(form.currency == .EUR)
        #expect(form.text.isEmpty)
        #expect(form.recognized == false)
        #expect(form.labelPhoto == nil)
        #expect(form.notes.isEmpty)
    }

    /// A photo-carrying form is not "by hand" even when OCR read nothing, so a
    /// picked library photo is not described as a typed-in bottle.
    @Test("addedByHand depends on both recognition and the photo",
          arguments: [(false, false, true), (true, false, false),
                      (false, true, false), (true, true, false)])
    func handEntryFlag(recognized: Bool, hasPhoto: Bool, expected: Bool) {
        var form = WineForm()
        form.producer = "Rinaldi"
        form.recognized = recognized
        form.labelPhoto = hasPhoto ? Data([1]) : nil
        #expect(form.makeWine().addedByHand == expected)
    }

    /// An empty photo is not nil, so it counts as "carrying a label" and
    /// suppresses the hand-entry flag even though nothing can be drawn from it.
    @Test("FINDING: an empty photo blob suppresses the 'Added by hand' chip")
    func emptyPhotoSuppressesHandEntry() {
        var form = WineForm()
        form.producer = "Rinaldi"
        form.labelPhoto = Data()
        let wine = form.makeWine()
        #expect(wine.addedByHand == false, "documented current behaviour")
        #expect(wine.statusLabel == "Scanned", "though nothing was scanned")
    }

    @Test("The label photo is carried into the saved bottle intact")
    func photoReachesTheBottle() throws {
        let container = try newContainer()
        let context = ModelContext(container)

        var form = WineForm()
        form.producer = "Rinaldi"
        form.labelPhoto = megabyte()
        let wine = form.makeWine()
        context.insert(wine)
        try context.save()

        #expect(try #require(try allWines(reader(container)).first).labelPhoto?.count == 1_048_576)
    }

    /// `apply(to:)` is the edit path. It must overwrite the photo column too,
    /// otherwise an edited bottle keeps a photo the form no longer holds.
    @Test("apply(to:) writes the photo column, including clearing it")
    func applyWritesThePhoto() {
        let wine = fullyPopulated(labelPhoto: Data([1, 2, 3]))
        var form = WineForm(editing: wine)
        form.labelPhoto = nil
        form.apply(to: wine)
        #expect(wine.labelPhoto == nil)
    }
}

// MARK: - Formatters

@Suite("Formatters")
struct FormatterTests {

    /// Built through `Calendar.current` so the assertion holds in any timezone
    /// the test machine happens to be in.
    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts)!
    }

    @Test("today() is two-digit day, three-letter month, four-digit year")
    func todayShape() {
        #expect(Formatters.today(date(2026, 9, 5)) == "05 Sep 2026")
        #expect(Formatters.today(date(2026, 1, 1)) == "01 Jan 2026")
        #expect(Formatters.today(date(2026, 12, 31)) == "31 Dec 2026")
    }

    @Test("Every month maps to its own three-letter abbreviation")
    func everyMonth() {
        let expected = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        for month in 1...12 {
            #expect(Formatters.today(date(2026, month, 15)) == "15 \(expected[month - 1]) 2026")
        }
    }

    @Test("stamp() is day, month, a middle dot and a 24-hour clock")
    func stampShape() {
        #expect(Formatters.stamp(date(2026, 9, 5, 14, 32)) == "05 Sep · 14:32")
        #expect(Formatters.stamp(date(2026, 8, 12, 18, 40)) == "12 Aug · 18:40")
    }

    /// A note taken at midnight must read "00:00", not "12:00" and not "0:0".
    @Test("stamp() zero-pads both clock fields and does not go to 12-hour")
    func stampPadding() {
        #expect(Formatters.stamp(date(2026, 3, 1, 0, 0)) == "01 Mar · 00:00")
        #expect(Formatters.stamp(date(2026, 3, 1, 0, 5)) == "01 Mar · 00:05")
        #expect(Formatters.stamp(date(2026, 3, 1, 9, 9)) == "01 Mar · 09:09")
        #expect(Formatters.stamp(date(2026, 3, 1, 23, 59)) == "01 Mar · 23:59")
        #expect(Formatters.stamp(date(2026, 3, 1, 13, 0)) == "01 Mar · 13:00")
    }

    @Test("stamp() uses a middle dot, not a bullet or a hyphen")
    func stampSeparator() {
        let out = Formatters.stamp(date(2026, 9, 5, 14, 32))
        #expect(out.contains("\u{00B7}"))
        #expect(out.contains("\u{2022}") == false)
        #expect(out.contains(" - ") == false)
    }

    @Test("A leap day formats without special-casing")
    func leapDay() {
        #expect(Formatters.today(date(2028, 2, 29)) == "29 Feb 2028")
        #expect(Formatters.stamp(date(2028, 2, 29, 12, 0)) == "29 Feb · 12:00")
    }

    @Test("Years outside the current century are printed as they are")
    func unusualYears() {
        #expect(Formatters.today(date(1999, 12, 31)) == "31 Dec 1999")
        #expect(Formatters.today(date(2100, 1, 1)) == "01 Jan 2100")
    }

    /// `stamp()` is the default for a note's `when`, and both are stored as
    /// plain strings, so what they produce is what the store keeps forever.
    @Test("A note stamps itself with the same string Formatters produces")
    func noteUsesTheStamp() throws {
        let container = try newContainer()
        let context = ModelContext(container)

        let wine = fullyPopulated()
        context.insert(wine)
        let note = TastingNote(kind: .voice, phase: .post, text: "n")
        note.wine = wine
        context.insert(note)
        try context.save()

        let back = try #require(try allNotes(reader(container)).first)
        #expect(back.when == Formatters.stamp(back.createdAt))
        #expect(back.label == "Dictated · " + back.when)
    }
}

// MARK: - Settings

/// These read and write `UserDefaults.standard`, so they run one at a time and
/// each restores what it found. The key strings are duplicated from
/// `Settings.Key`, which is private — they are the on-disk contract, so a
/// change to one of them is a migration and worth failing on.
@Suite("Settings · defaults and persistence", .serialized)
struct SettingsTests {

    private static let keys = ["defaultCurrency", "showShelfPrice", "labelRecognition"]

    private func withCleanDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = Self.keys.map { defaults.object(forKey: $0) }
        for key in Self.keys { defaults.removeObject(forKey: key) }
        defer {
            for (key, value) in zip(Self.keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try body()
    }

    @Test("With nothing stored, the defaults are EUR and both toggles on")
    func unsetDefaults() {
        withCleanDefaults {
            #expect(Settings.defaultCurrency == .EUR)
            #expect(Settings.showShelfPrice == true)
            #expect(Settings.labelRecognition == true)
        }
    }

    @Test("Each currency survives a write and a read")
    func currencyPersists() {
        withCleanDefaults {
            for code in CurrencyCode.allCases {
                Settings.defaultCurrency = code
                #expect(Settings.defaultCurrency == code)
                #expect(UserDefaults.standard.string(forKey: "defaultCurrency") == code.rawValue)
            }
        }
    }

    /// The stored value is a raw string, so a build that no longer knows a code
    /// must fall back rather than trap — the same forward-compatibility seam as
    /// the store columns.
    @Test("An unreadable stored currency falls back to EUR")
    func corruptCurrencyFallsBack() {
        withCleanDefaults {
            for junk in ["JPY", "", "eur", "42", "€"] {
                UserDefaults.standard.set(junk, forKey: "defaultCurrency")
                #expect(Settings.defaultCurrency == .EUR)
            }
        }
    }

    /// A non-string value under the key must not crash the getter either.
    @Test("A wrong-typed stored currency falls back to EUR")
    func wrongTypedCurrencyFallsBack() {
        withCleanDefaults {
            UserDefaults.standard.set(42, forKey: "defaultCurrency")
            #expect(Settings.defaultCurrency == .EUR)
            UserDefaults.standard.set(["EUR"], forKey: "defaultCurrency")
            #expect(Settings.defaultCurrency == .EUR)
        }
    }

    /// The toggles default to `true`, so they must distinguish "never set" from
    /// "set to false" — an `object(forKey:) as? Bool` that fell through to
    /// `bool(forKey:)` would turn both defaults off.
    @Test("Both toggles distinguish 'never set' from 'set to false'")
    func togglesRoundTrip() {
        withCleanDefaults {
            #expect(Settings.showShelfPrice == true)
            Settings.showShelfPrice = false
            #expect(Settings.showShelfPrice == false)
            Settings.showShelfPrice = true
            #expect(Settings.showShelfPrice == true)

            #expect(Settings.labelRecognition == true)
            Settings.labelRecognition = false
            #expect(Settings.labelRecognition == false)
            Settings.labelRecognition = true
            #expect(Settings.labelRecognition == true)
        }
    }

    @Test("The two toggles are independent keys")
    func togglesAreIndependent() {
        withCleanDefaults {
            Settings.showShelfPrice = false
            #expect(Settings.labelRecognition == true)
            Settings.labelRecognition = false
            Settings.showShelfPrice = true
            #expect(Settings.showShelfPrice == true)
            #expect(Settings.labelRecognition == false)
        }
    }

    /// The scanner seeds a new form's currency from this preference, which is
    /// the only place the setting reaches the model.
    @Test("The stored currency is what a scanned form starts in")
    func settingSeedsTheForm() {
        withCleanDefaults {
            Settings.defaultCurrency = .SEK
            let reading = LabelReading(producer: "Rinaldi", name: "", vintage: "2019",
                                       region: "", grape: "", recognized: true)
            let form = WineForm(reading: reading, photo: nil,
                                currency: Settings.defaultCurrency)
            #expect(form.currency == .SEK)
            #expect(form.makeWine().currency == .SEK)
            #expect(form.makeWine().boughtCurrency == .SEK)
        }
    }
}
