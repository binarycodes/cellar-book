import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Vinnota

// MARK: - Fixtures
//
// Everything here builds a `Wine` through its real initialiser and then sets
// the stored properties the app's own commit paths set (`TastingView.markTasted`,
// `BoughtSheet.confirm`, `DetailView.set(_:toast:)`). Nothing re-implements a
// derived property — the point of these tests is to pin down what `Wine` and the
// two enums already decide, because those decisions are what the user sees.

private func bottle(
    producer: String = "Rinaldi",
    name: String = "",
    vintage: String = "",
    region: String = "",
    grape: String = "",
    shop: String = "",
    status: WineStatus = .new,
    verdict: Verdict? = nil,
    addedByHand: Bool = false
) -> Wine {
    let wine = Wine(producer: producer, name: name, vintage: vintage,
                    region: region, grape: grape, shop: shop)
    wine.status = status
    wine.verdict = verdict
    wine.addedByHand = addedByHand
    return wine
}

/// A fully filled bottle, so a search test can say which field it hit.
private func fullBottle() -> Wine {
    bottle(producer: "Giuseppe Rinaldi", name: "Brunate", vintage: "2019",
           region: "Barolo", grape: "Nebbiolo", shop: "Enoteca Sciolla")
}

private func newContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema([Wine.self, TastingNote.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

/// `Color` is `Equatable`, but two colours built by different expressions can
/// compare unequal even when they paint the same pixels. Resolving through
/// `UIColor` compares what the user actually sees, which is the property these
/// mapping tests care about.
private func rgba(_ color: Color) -> [CGFloat] {
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let components = ui.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil)?
        .components ?? []
    return components.map { ($0 * 1000).rounded() / 1000 }
}

private func elapsed(_ body: () -> Void) -> TimeInterval {
    let start = Date()
    body()
    return Date().timeIntervalSince(start)
}

/// The real runs land around 0.05s, so 5s is a ~100× margin — generous enough
/// never to flake on a loaded machine, tight enough that a runaway scan fails
/// the suite instead of wedging it.
private let budget: TimeInterval = 5

/// Every `(status, addedByHand)` pair the chip has to render, hoisted out of the
/// test so `chipTableIsExhaustive` can check it really is every pair. Written as
/// literals rather than derived, so a change to the rule fails the test instead
/// of agreeing with itself.
private let chipCases: [(status: WineStatus, byHand: Bool, expected: String)] = [
    (.new,    false, "Scanned"),
    (.new,    true,  "Added by hand"),
    (.want,   false, "Want to try"),
    (.want,   true,  "Want to try"),
    (.maybe,  false, "Undecided"),
    (.maybe,  true,  "Undecided"),
    (.not,    false, "Passed"),
    (.not,    true,  "Passed"),
    (.bought, false, "In the rack"),
    (.bought, true,  "In the rack"),
    (.tasted, false, "Tasted"),
    (.tasted, true,  "Tasted"),
]

// MARK: - Which fields search reads

@Suite("Wine.matches · fields searched")
struct SearchFieldTests {

    @Test("Producer, cuvée, region, grape and shop are all searchable",
          arguments: [
            ("giuseppe rinaldi", "producer"),
            ("brunate",          "cuvée"),
            ("barolo",           "region"),
            ("nebbiolo",         "grape"),
            ("enoteca sciolla",  "shop"),
          ])
    func everySearchedField(query: String, field: String) {
        #expect(fullBottle().matches(query: query), "\(field) should be searchable")
    }

    /// The placeholder promises "Producer, region, grape". The row that comes
    /// back leads with the vintage in a 42pt column, so a user reading the
    /// results has every reason to think the year is searchable too.
    ///
    /// FINDING: Vinnota/Model/Wine.swift:162 omits `vintage` from the searched
    /// fields. Typing the year of a bottle you can see in the list returns
    /// "No bottle matches that."
    @Test("FINDING: the vintage is not searchable")
    func vintageIsNotSearched() {
        let wine = fullBottle()
        #expect(wine.displayVintage == "2019")
        #expect(wine.matches(query: "2019") == false, "documented current behaviour")
    }

    /// Notes are a separate `@Model`; `matches` never touches the relationship.
    /// FINDING: Vinnota/Model/Wine.swift:162 — a bottle whose only mention of
    /// "cork taint" is in a tasting note cannot be found by searching for it.
    @Test("FINDING: tasting notes are not searchable")
    func notesAreNotSearched() {
        let wine = fullBottle()
        let note = TastingNote(kind: .text, phase: .post, text: "unmistakable cork taint")
        note.wine = wine
        wine.notes = [note]

        #expect(wine.notes.first?.text.contains("cork taint") == true)
        #expect(wine.matches(query: "cork taint") == false, "documented current behaviour")
    }

    /// Price and dates are not searched either — asserted so that adding them
    /// later is a deliberate change with a failing test to update.
    @Test(arguments: ["45", "€45", "05 Sep 2026"])
    func pricesAndDatesAreNotSearched(query: String) {
        let wine = fullBottle()
        wine.price = "45"
        wine.boughtPrice = "45"
        wine.boughtDate = "05 Sep 2026"
        #expect(wine.matches(query: query) == false)
    }

    @Test("Matching is case-insensitive in both directions",
          arguments: ["BAROLO", "BaRoLo"])
    func caseIsIgnored(query: String) {
        #expect(fullBottle().matches(query: query))
        #expect(bottle(producer: "BAROLO").matches(query: query))
    }

    @Test("A partial run of characters matches, anywhere in the word",
          arguments: [
            ("gius",      true),   // start of a word
            ("aldi",      true),   // end of a word
            ("ebbio",     true),   // buried in the middle
            ("o",         true),   // a single letter
            ("naldi bru", true),   // across a word boundary
            ("innal",     false),  // letters that are all present but not in order
            ("ldia",      false),
          ])
    func partialMatches(query: String, expected: Bool) {
        #expect(fullBottle().matches(query: query) == expected)
    }

    @Test("A query that is nowhere in any field does not match")
    func missMatchesNothing() {
        #expect(fullBottle().matches(query: "Riesling") == false)
        #expect(fullBottle().matches(query: "giuseppe rinaldix") == false)
    }
}

// MARK: - The empty query

@Suite("Wine.matches · the empty query means no filter")
struct EmptyQueryTests {

    /// Space, tab and the Unicode spaces a paste can carry are all trimmed by
    /// `.whitespaces`, so each of these shows the whole cellar.
    @Test(arguments: [
        "",
        " \t \t ",
        "\u{00A0}",         // NO-BREAK SPACE
        "\u{2009}",         // THIN SPACE
        "\u{3000}",         // IDEOGRAPHIC SPACE
    ])
    func blankQueriesMatchEveryBottle(query: String) {
        #expect(fullBottle().matches(query: query))
        #expect(bottle(producer: "", name: "", region: "", grape: "", shop: "")
                    .matches(query: query),
                "even a bottle with nothing in any searched field")
    }

    @Test("Padding around a real query is trimmed away")
    func paddingIsTrimmed() {
        #expect(fullBottle().matches(query: "   barolo   "))
        #expect(fullBottle().matches(query: "\tbarolo\t"))
    }

    /// `matches` trims `.whitespaces`, which does not include newlines, while
    /// every other blank check in the app uses `.whitespacesAndNewlines`. The
    /// newline-*only* query is already pinned down in FormValidationTests; the
    /// case that bites a real user is a **paste**, which routinely carries a
    /// trailing newline and turns a good query into a guaranteed miss.
    ///
    /// FINDING: Vinnota/Model/Wine.swift:160 — use `.whitespacesAndNewlines`.
    @Test("FINDING: a pasted query with a newline on it finds nothing")
    func newlinePaddingIsNotTrimmed() {
        let wine = fullBottle()
        #expect(wine.matches(query: "barolo"))
        #expect(wine.matches(query: "barolo\n") == false, "documented current behaviour")
        #expect(wine.matches(query: "\nbarolo") == false, "documented current behaviour")
        #expect(wine.matches(query: "barolo\r\n") == false, "documented current behaviour")
    }

    /// A zero-width space is not whitespace, so it survives the trim — but the
    /// comparison treats it as ignorable, so it still behaves as "no filter"
    /// rather than hiding the cellar. Benign, and worth knowing it is benign.
    @Test("A zero-width space query is harmless")
    func zeroWidthSpaceQuery() {
        #expect(fullBottle().matches(query: "\u{200B}"))
    }
}

// MARK: - Diacritics

@Suite("Wine.matches · accents")
struct DiacriticTests {

    /// The whole domain is accented — Château, Rhône, Pétrus, Gevrey-Chambertin
    /// — and an iOS keyboard makes an accented character deliberate work. The
    /// search field even disables autocorrect and autocapitalisation, so nothing
    /// is going to put the circumflex there for the user.
    ///
    /// FINDING: Vinnota/Model/Wine.swift:160,163 lowercases but does not fold
    /// diacritics, so the unaccented spelling — which is what most users type —
    /// matches nothing. `localizedStandardContains` (or `range(of:options:
    /// [.caseInsensitive, .diacriticInsensitive])`) would fix it.
    @Test("FINDING: an unaccented query does not find an accented bottle",
          arguments: [
            ("Château Margaux",  "chateau"),
            ("Côtes du Rhône",   "rhone"),
            ("Pétrus",           "petrus"),
            ("Gevrey-Chambertin Clos Saint-Jacques", "clos saint-jacques"),
          ])
    func unaccentedQueryMisses(field: String, query: String) {
        let wine = bottle(producer: field)
        // The last row is the control: no accent in the field, so it matches.
        let hasAccent = field.folding(options: .diacriticInsensitive, locale: nil) != field
        #expect(wine.matches(query: query) == !hasAccent, "documented current behaviour")
    }

    @Test("Typing the accent does work",
          arguments: [
            ("Château Margaux", "château"),
            ("Château Margaux", "CHÂTEAU"),
            ("Côtes du Rhône",  "rhône"),
            ("Pétrus",          "pétrus"),
          ])
    func accentedQueryHits(field: String, query: String) {
        #expect(bottle(producer: field).matches(query: query))
    }

    /// The mirror image: an accented query against an unaccented bottle also
    /// misses, so an OCR read that dropped the accent is unfindable by the
    /// correct spelling.
    @Test("FINDING: an accented query does not find an unaccented bottle")
    func accentedQueryMissesPlainBottle() {
        #expect(bottle(producer: "Chateau Margaux").matches(query: "château") == false,
                "documented current behaviour")
    }

    /// Composed vs decomposed is the one normalisation question that *does* go
    /// the right way: Swift's comparison is canonically equivalent, so a bottle
    /// scanned as U+0065 U+0301 is found by a query typed as U+00E9 and back.
    @Test("Composed and decomposed accents are interchangeable")
    func canonicalEquivalence() {
        let composed = "Ch\u{00E2}teau P\u{00E9}trus"      // â, é
        let decomposed = "Cha\u{0302}teau Pe\u{0301}trus"  // a + ̂ , e + ́
        #expect(Array(composed.unicodeScalars) != Array(decomposed.unicodeScalars),
                "genuinely different bytes")
        #expect(composed == decomposed,
                "…which Swift's own `==` already treats as the same string")

        #expect(bottle(producer: composed).matches(query: decomposed))
        #expect(bottle(producer: decomposed).matches(query: composed))
        #expect(bottle(producer: decomposed).matches(query: "p\u{00E9}trus"))
        #expect(bottle(producer: composed).matches(query: "pe\u{0301}trus"))
    }

    /// German sharp s does not fold to "ss" here either — same root cause,
    /// recorded so the fix above is judged against it.
    @Test("FINDING: ß is not folded to ss")
    func sharpSIsNotFolded() {
        #expect(bottle(producer: "Weingut Straße").matches(query: "strasse") == false,
                "documented current behaviour")
        #expect(bottle(producer: "Weingut Straße").matches(query: "straße"))
    }
}

// MARK: - The joined-fields seam

@Suite("Wine.matches · fields are joined before the search")
struct JoinedFieldTests {

    /// `matches` joins the five fields with a space and searches the result, so
    /// a query can straddle two fields. "brunate barolo" is not in any single
    /// field, but it matches — which is usually what a user wanted anyway.
    @Test("A query can span two adjacent fields")
    func queryCanSpanFields() {
        #expect(fullBottle().matches(query: "brunate barolo"))
        #expect(fullBottle().matches(query: "rinaldi brunate"))
    }

    /// The other half of the same behaviour: an *empty* field still contributes
    /// its separator, so two spaces appear where it was and a natural query
    /// across the gap misses.
    ///
    /// FINDING: Vinnota/Model/Wine.swift:163 joins unconditionally. Filtering
    /// blank fields out before joining — as `subtitle` and `eyebrow` already do
    /// — would make this consistent.
    @Test("FINDING: a blank field leaves a double space that breaks a spanning query")
    func blankFieldBreaksASpanningQuery() {
        let noCuvee = bottle(producer: "Rinaldi", name: "", region: "Barolo")
        #expect(noCuvee.matches(query: "rinaldi barolo") == false,
                "documented current behaviour")
        #expect(noCuvee.matches(query: "rinaldi  barolo"), "two spaces do match")
    }

    /// Search never looks past the searched fields into the ones next door.
    @Test("Each field is matched on its own content")
    func fieldsAreNotConfused() {
        let wine = bottle(producer: "Rinaldi", region: "Barolo", shop: "Enoteca")
        #expect(wine.matches(query: "enoteca"))
        #expect(wine.matches(query: "vinoteca") == false)
    }
}

// MARK: - Untrusted query text

@Suite("Wine.matches · untrusted input is literal text")
struct SearchRobustnessTests {

    /// The query goes straight into `String.contains`, which is a literal
    /// substring search. If it were ever swapped for `NSPredicate`, `LIKE` or a
    /// regex, these would start throwing or matching everything. One
    /// representative per family rather than a long list of near-twins: an
    /// unbalanced group that would fail to compile, a character class, anchors,
    /// an escape, a catastrophic-backtracking pattern, the two SQL wildcards,
    /// and a format specifier.
    @Test("Regex metacharacters are searched literally, never compiled",
          arguments: [
            ".*", "(((", "[a-z]+", "^Rinaldi$", "\\d{4}", "a|b",
            "\\", "(?i)rinaldi", "(a+)+$", "%", "_", "%@", "'",
          ])
    func metacharactersAreLiteral(query: String) {
        let plain = bottle(producer: "Giuseppe Rinaldi", region: "Barolo")
        #expect(plain.matches(query: query) == false,
                "a pattern must not match a bottle that does not contain it as text")

        // …and the same characters *are* found when they are really in the data.
        let literal = bottle(producer: "Giuseppe Rinaldi \(query) Barolo")
        #expect(literal.matches(query: query))
    }

    /// The cases that separate "literal" from "pattern" most clearly: a
    /// single-character wildcard must not match the character it stands in for.
    /// `.` is the regex one, `_` the SQL one — `matches` runs in Swift, not in
    /// the store, so nothing ever reaches a `LIKE` either.
    @Test("A single-character wildcard matches only itself")
    func wildcardsAreNotWildcards() {
        #expect(bottle(producer: "Dom. Rinaldi").matches(query: "m. r"))
        #expect(bottle(producer: "Dom Rinaldi").matches(query: "m. r") == false)
        #expect(bottle(producer: "Rinaldi").matches(query: ".") == false)
        #expect(bottle(producer: "Rinaldi").matches(query: "R_naldi") == false)
        #expect(bottle(producer: "100% Nebbiolo").matches(query: "100%"))
    }

    @Test("Emoji, RTL text and control characters are ordinary query text",
          arguments: [
            "🍇🍷",
            "\u{202E}gnitset",              // RIGHT-TO-LEFT OVERRIDE
            "\u{200F}מרגו\u{200E}",          // RTL/LTR marks around Hebrew
            "\u{0000}",                      // NUL
            "\u{1F1EB}\u{1F1F7}",            // flag, a two-scalar grapheme
            "e\u{0301}\u{0323}",             // stacked combining marks
        ])
    func exoticTextIsJustText(query: String) {
        #expect(bottle(producer: "Château Margaux \(query)").matches(query: query))
        #expect(bottle(producer: "Château Margaux").matches(query: query) == false)
    }

    @Test("An RTL producer is findable by an RTL substring")
    func rtlSubstring() {
        #expect(bottle(producer: "شاتو مارغو", region: "بوردو").matches(query: "مارغو"))
        #expect(bottle(producer: "שאטו מרגו").matches(query: "מרגו"))
    }

    @Test("A very long query returns quickly and does not crash")
    func veryLongQuery() {
        let wine = fullBottle()
        let long = String(repeating: "a", count: 200_000)
        let emoji = String(repeating: "🍷", count: 50_000)

        let took = elapsed {
            #expect(wine.matches(query: long) == false)
            #expect(wine.matches(query: emoji) == false)
            #expect(wine.matches(query: String(repeating: " ", count: 100_000)),
                    "100k spaces is still an empty query")
        }
        #expect(took < budget)
    }

    @Test("A very long field does not blow up the search")
    func veryLongField() {
        let wine = bottle(producer: String(repeating: "Château Rinaldi ", count: 20_000))
        let took = elapsed {
            #expect(wine.matches(query: "château rinaldi"))
            #expect(wine.matches(query: "riesling") == false)
        }
        #expect(took < budget)
    }

    /// Searching must never mutate the bottle it is filtering.
    @Test("matches has no side effects")
    func noSideEffects() {
        let wine = fullBottle()
        wine.status = .bought
        _ = wine.matches(query: "barolo")
        _ = wine.matches(query: ".*")
        _ = wine.matches(query: "")
        #expect(wine.producer == "Giuseppe Rinaldi")
        #expect(wine.status == .bought)
        #expect(wine.vintage == "2019")
    }
}

// MARK: - Status chip copy

@Suite("Wine.statusLabel")
struct StatusLabelTests {

    /// `addedByHand` only ever changes the `.new` chip: once a bottle has been
    /// ranked, bought or drunk, its own status is the truer label.
    @Test(arguments: chipCases)
    func chipCopy(row: (status: WineStatus, byHand: Bool, expected: String)) {
        #expect(bottle(status: row.status, addedByHand: row.byHand).statusLabel
                == row.expected)
    }

    /// The table above is only as good as its coverage, so check the coverage
    /// rather than merely counting the enum: every status must appear with
    /// `addedByHand` both ways, or a new status could ship with no pinned chip.
    @Test("Every status is in the chip table, both ways")
    func chipTableIsExhaustive() {
        for status in WineStatus.allCases {
            let rows = chipCases.filter { $0.status == status }
            #expect(Set(rows.map(\.byHand)) == [true, false],
                    "\(status.rawValue) is missing a row")
        }
        #expect(chipCases.count == WineStatus.allCases.count * 2,
                "and no status is pinned twice over")
    }

    /// The unqualified enum label still says "Scanned" for `.new`; the untruth
    /// is corrected by `Wine.statusLabel`, not by the enum, so a view that
    /// reaches for `wine.status.label` would reintroduce the bug.
    @Test("The bare enum label is the un-corrected copy")
    func enumLabelIsUncorrected() {
        #expect(WineStatus.new.label == "Scanned")
        #expect(bottle(status: .new, addedByHand: true).status.label == "Scanned")
        #expect(bottle(status: .new, addedByHand: true).statusLabel == "Added by hand")
    }

    @Test("Default bottles are `.new` and not marked hand-entered")
    func defaults() {
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "")
        #expect(wine.status == .new)
        #expect(wine.addedByHand == false)
        #expect(wine.statusLabel == "Scanned")
        #expect(wine.verdict == nil)
        #expect(wine.qty == 1)
        #expect(wine.openedAt == nil)
    }

    /// A corrupt or future `statusRaw` falls back to `.new` rather than
    /// trapping — the store is the only thing that can produce this.
    @Test func unknownStoredStatusFallsBackToNew() {
        let wine = bottle()
        wine.statusRaw = "cellared"
        #expect(wine.status == .new)
        #expect(wine.statusLabel == "Scanned")

        wine.verdictRaw = "ecstatic"
        #expect(wine.verdict == nil)
    }
}

// MARK: - Display strings

@Suite("Wine display strings")
struct DisplayStringTests {

    /// Older rows stored an em dash to mean "no cuvée"; `displayName` turns
    /// that back into nothing so the card does not print a stray dash.
    @Test("The em-dash sentinel and blanks both display as nothing",
          arguments: ["—", "", " ", "   ", "\t", "\n", "\u{00A0}"])
    func emptyCuvees(name: String) {
        #expect(bottle(name: name).displayName == "")
        #expect(bottle(name: name, region: "Barolo").subtitle == "Barolo",
                "no leading separator")
    }

    @Test("A real cuvée is passed through untouched",
          arguments: ["Brunate", "Clos du —", "——", "Côte-Rôtie", "-", "– ", "N.V."])
    func realCuvees(name: String) {
        #expect(bottle(name: name).displayName == name)
    }

    /// The sentinel is compared without trimming, so a padded em dash — which
    /// only a legacy row can hold, since the commit path trims — still prints.
    /// FINDING: Vinnota/Model/Wine.swift:127 compares `name == "—"` before
    /// `isBlank`; `name.trimmed == "—"` would cover the legacy row too.
    @Test("FINDING: a padded em dash is not recognised as the sentinel")
    func paddedSentinel() {
        #expect(bottle(name: " — ").displayName == " — ", "documented current behaviour")
        #expect(bottle(name: " — ", region: "Barolo").subtitle == " —  · Barolo",
                "documented current behaviour")
    }

    @Test("subtitle joins the cuvée and the region with a middle dot")
    func subtitle() {
        #expect(bottle(name: "Brunate", region: "Barolo").subtitle == "Brunate · Barolo")
        #expect(bottle(name: "Brunate", region: "").subtitle == "Brunate")
        #expect(bottle(name: "", region: "Barolo").subtitle == "Barolo")
        #expect(bottle(name: "", region: "").subtitle == "",
                "the card hides the line entirely")
        #expect(bottle(name: "—", region: "").subtitle == "")
    }

    @Test("eyebrow joins the grape and the region, in that order")
    func eyebrow() {
        #expect(bottle(region: "Barolo", grape: "Nebbiolo").eyebrow == "Nebbiolo · Barolo")
        #expect(bottle(region: "", grape: "Nebbiolo").eyebrow == "Nebbiolo")
        #expect(bottle(region: "Barolo", grape: "").eyebrow == "Barolo")
        #expect(bottle(region: "", grape: "").eyebrow == "")
    }

    /// `eyebrow` uses the raw name, not `displayName`, so it differs from
    /// `subtitle` in what it treats as empty — but it never reads the cuvée, so
    /// the em-dash sentinel cannot leak into it.
    @Test("eyebrow never shows the cuvée")
    func eyebrowIgnoresCuvee() {
        #expect(bottle(name: "—", region: "Barolo", grape: "Nebbiolo").eyebrow
                == "Nebbiolo · Barolo")
    }

    /// A whitespace-only region is not empty, so it does survive into both
    /// joins as a stray separator. The commit path trims, so this is reachable
    /// only from a legacy row.
    @Test("FINDING: a whitespace-only region still contributes a separator")
    func whitespaceRegion() {
        #expect(bottle(name: "Brunate", region: " ").subtitle == "Brunate ·  ",
                "documented current behaviour")
        #expect(bottle(region: " ", grape: "Nebbiolo").eyebrow == "Nebbiolo ·  ",
                "documented current behaviour")
    }

    @Test("hasVintage is false for a blank year, true for anything else",
          arguments: ["", " ", "   ", "\t", "\n", "\r\n", "\u{00A0}", "\u{3000}"])
    func blankVintages(vintage: String) {
        let wine = bottle(vintage: vintage)
        #expect(wine.hasVintage == false, "the card falls back to NV")
        #expect(wine.displayVintage == vintage, "displayVintage is the raw value")
    }

    @Test(arguments: ["2019", "NV", "1985", "20 19", "MMXIX", "0"])
    func realVintages(vintage: String) {
        let wine = bottle(vintage: vintage)
        #expect(wine.hasVintage)
        #expect(wine.displayVintage == vintage)
    }

    /// `hasVintage` trims but `displayVintage` does not, so a padded year is
    /// shown padded. Again only reachable from a legacy row.
    @Test("FINDING: displayVintage does not trim what hasVintage trimmed")
    func paddedVintage() {
        let wine = bottle(vintage: "  2019  ")
        #expect(wine.hasVintage)
        #expect(wine.displayVintage == "  2019  ", "documented current behaviour")
    }

    /// The display fields never touch the underlying store values.
    @Test func displayIsNonDestructive() {
        let wine = bottle(name: "—", vintage: " 2019 ", region: "Barolo")
        _ = (wine.displayName, wine.subtitle, wine.eyebrow, wine.displayVintage, wine.hasVintage)
        #expect(wine.name == "—")
        #expect(wine.vintage == " 2019 ")
    }
}

// MARK: - Money
//
// `displayPrice` and `CurrencyCode.format` were the one part of the two files
// under test that no suite reached: FormValidationTests pins how a price is
// *stored* (`hasPrice`), but nothing pinned how it is *rendered*.

@Suite("Wine.displayPrice and CurrencyCode.format")
struct PriceTests {

    /// The two currencies that are not "symbol then amount": SEK trails, and
    /// CHF carries a thin space rather than the bare `symbol`.
    @Test(arguments: [
        (CurrencyCode.EUR, "45", "€45"),
        (CurrencyCode.USD, "45", "$45"),
        (CurrencyCode.GBP, "45", "£45"),
        (CurrencyCode.CHF, "45", "Fr\u{2009}45"),
        (CurrencyCode.SEK, "45", "45 kr"),
    ])
    func formatting(currency: CurrencyCode, amount: String, expected: String) {
        #expect(currency.format(amount) == expected)
    }

    @Test("CHF's thin space is not the plain symbol")
    func chfIsNotJustItsSymbol() {
        #expect(CurrencyCode.CHF.symbol == "Fr")
        #expect(CurrencyCode.CHF.format("45") != "Fr45")
        #expect(CurrencyCode.CHF.format("45").contains("\u{2009}"))
    }

    @Test("A missing amount is an em dash, never a bare symbol",
          arguments: CurrencyCode.allCases)
    func noAmount(currency: CurrencyCode) {
        #expect(currency.format(nil) == "—")
        #expect(currency.format("") == "—")
    }

    /// The paid price wins when there is one, and it is rendered in the *paid*
    /// currency — the two are independent fields, so a bottle marked in EUR and
    /// bought in SEK must not print the shelf currency.
    @Test func paidPriceWinsAndCarriesItsOwnCurrency() {
        let wine = bottle()
        wine.price = "45"
        wine.currency = .EUR
        #expect(wine.displayPrice == "€45", "no paid price yet, so the shelf price shows")
        #expect(wine.hasPrice)

        wine.boughtPrice = "380"
        wine.boughtCurrency = .SEK
        #expect(wine.displayPrice == "380 kr")
        #expect(wine.hasPrice)
    }

    @Test("With neither price the line is an em dash")
    func noPriceAtAll() {
        let wine = bottle()
        #expect(wine.price == nil)
        #expect(wine.boughtPrice == nil)
        #expect(wine.hasPrice == false)
        #expect(wine.displayPrice == "—")
    }

    /// `Wine.init` seeds `boughtCurrency` from the shelf currency, so a bottle
    /// bought without touching the currency picker renders in the right one.
    @Test func boughtCurrencyDefaultsToTheShelfCurrency() {
        let wine = Wine(producer: "Rinaldi", name: "", vintage: "", region: "",
                        grape: "", shop: "", price: "45", currency: .GBP)
        #expect(wine.boughtCurrency == .GBP)
        wine.boughtPrice = "40"
        #expect(wine.displayPrice == "£40")
    }

    /// `BoughtSheet.confirm` guards with `isEmpty`, not `isBlank`, so a single
    /// space typed into the paid-price field is stored verbatim. `format` only
    /// rejects `isEmpty` too, so it prints the currency symbol against nothing.
    ///
    /// FINDING: Vinnota/Views/Sheets/BoughtSheet.swift:86 and
    /// Vinnota/Model/Enums.swift:130 — both should test `isBlank`.
    @Test("FINDING: a whitespace-only paid price prints a bare currency symbol")
    func whitespacePaidPrice() {
        let wine = bottle()
        wine.price = "45"
        wine.boughtPrice = " "
        #expect(wine.hasPrice, "documented current behaviour")
        #expect(wine.displayPrice == "€ ", "documented current behaviour")
    }

    /// The same seam one step further on: an *empty* paid price is only
    /// reachable from a legacy row, and it hides a perfectly good shelf price.
    @Test("FINDING: an empty paid price hides the shelf price behind an em dash")
    func emptyPaidPriceHidesShelfPrice() {
        let wine = bottle()
        wine.price = "45"
        wine.boughtPrice = ""
        #expect(wine.currency.format(wine.price) == "€45", "the shelf price is still there")
        #expect(wine.displayPrice == "—", "documented current behaviour")
        #expect(wine.hasPrice == false)
    }
}

// MARK: - Notes

@Suite("Wine.preNotes and Wine.postNotes")
struct NoteSplitTests {

    /// `createdAt` is set explicitly: two notes built in the same instant get
    /// equal timestamps, and `sorted(by:)` is not stable, so a test that relied
    /// on insertion order would flake rather than pin the sort.
    private func note(_ phase: TastingNote.Phase, _ text: String,
                      at offset: TimeInterval) -> TastingNote {
        let note = TastingNote(kind: .text, phase: phase, text: text)
        note.createdAt = Date(timeIntervalSince1970: offset)
        return note
    }

    @Test("Each phase gets only its own notes, oldest first")
    func splitAndOrder() {
        let wine = bottle()
        // Deliberately attached newest-first, so the sort has work to do.
        wine.notes = [
            note(.post, "second in the glass", at: 400),
            note(.pre,  "second on the shelf", at: 200),
            note(.post, "first in the glass",  at: 300),
            note(.pre,  "first on the shelf",  at: 100),
        ]

        #expect(wine.preNotes.map(\.text) == ["first on the shelf", "second on the shelf"])
        #expect(wine.postNotes.map(\.text) == ["first in the glass", "second in the glass"])
    }

    @Test("A bottle with no notes has two empty lists")
    func noNotes() {
        let wine = bottle()
        #expect(wine.preNotes.isEmpty)
        #expect(wine.postNotes.isEmpty)
    }

    /// The detail screen's note byline: dictated notes say so, typed ones do not.
    @Test(arguments: [
        (TastingNote.Kind.voice, "Dictated · 12 Aug · 18:40"),
        (TastingNote.Kind.text,  "Typed · 12 Aug · 18:40"),
    ])
    func noteLabel(kind: TastingNote.Kind, expected: String) {
        let note = TastingNote(kind: kind, phase: .pre, text: "tar and roses",
                               when: "12 Aug · 18:40")
        #expect(note.label == expected)
    }

    /// A corrupt or future `kindRaw`/`phaseRaw` falls back rather than trapping,
    /// the same way `status` does.
    @Test func unknownStoredKindAndPhaseFallBack() {
        let note = TastingNote(kind: .voice, phase: .post, text: "x")
        note.kindRaw = "telepathic"
        note.phaseRaw = "during"
        #expect(note.kind == .text)
        #expect(note.phase == .pre)
    }
}

// MARK: - Deletion guard

@Suite("Wine.canDelete · the data-loss guard")
struct DeletionGuardTests {

    /// The boundary, exactly: `.tasted` is the only status that locks a bottle
    /// down. Written as literals so the rule cannot agree with a broken
    /// implementation.
    @Test(arguments: [
        (WineStatus.new,    true),
        (WineStatus.want,   true),
        (WineStatus.maybe,  true),
        (WineStatus.not,    true),
        (WineStatus.bought, true),
        (WineStatus.tasted, false),
    ])
    func onlyTastedBottlesAreProtected(status: WineStatus, deletable: Bool) {
        let wine = bottle(status: status)
        #expect(wine.canDelete == deletable)
        #expect(wine.isTasted == (status == .tasted))
        #expect(wine.canDelete == !wine.isTasted, "the guard is exactly `not tasted`")
    }

    @Test("isBought is exactly `.bought`, and is not implied by `.tasted`")
    func isBought() {
        #expect(bottle(status: .bought).isBought)
        #expect(bottle(status: .tasted).isBought == false,
                "a drunk bottle is no longer in the rack")
        for s in WineStatus.allCases where s != .bought {
            #expect(bottle(status: s).isBought == false)
        }
    }

    /// The keenness control is hidden once the decision has been made for you.
    @Test(arguments: [
        (WineStatus.new,    true),
        (WineStatus.want,   true),
        (WineStatus.maybe,  true),
        (WineStatus.not,    true),
        (WineStatus.bought, false),
        (WineStatus.tasted, false),
    ])
    func showKeen(status: WineStatus, shown: Bool) {
        #expect(bottle(status: status).showKeen == shown)
    }

    /// The guard is keyed on status alone. A bottle carrying a verdict and a
    /// cellar full of post-pour notes is still deletable if its status was
    /// never moved to `.tasted` — which no commit path in the app produces
    /// today, but nothing prevents either.
    @Test("The guard reads status, not evidence of having been drunk")
    func guardIsStatusOnly() {
        let wine = bottle(status: .bought, verdict: .loved)
        let note = TastingNote(kind: .text, phase: .post, text: "drunk and loved")
        note.wine = wine
        wine.notes = [note]
        wine.openedAt = Formatters.today()

        #expect(wine.postNotes.count == 1)
        #expect(wine.verdict == .loved)
        #expect(wine.canDelete, "documented current behaviour")
    }

    /// FINDING: Vinnota/Views/Sheets/DeleteDialog.swift:56 — `confirm()` calls
    /// `context.delete(wine)` without consulting `canDelete`. The guard exists
    /// only as a hidden trash icon in Vinnota/Views/DetailView.swift:104, so a
    /// tasted bottle is protected by the layout and by nothing else. This test
    /// documents that the model does not enforce it; the fix is a `guard
    /// wine.canDelete else { return }` in `confirm()`.
    @Test("FINDING: nothing below the view enforces canDelete")
    func modelDoesNotEnforceTheGuard() throws {
        let context = try newContext()
        let tasted = bottle(status: .tasted, verdict: .loved)
        context.insert(tasted)
        try context.save()
        #expect(tasted.canDelete == false)

        context.delete(tasted)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Wine>()).isEmpty,
                "documented current behaviour: the store deletes it anyway")
    }

    /// When a deletable bottle does go, its notes go with it — the dialog
    /// promises "every note on it go for good", and the cascade rule delivers.
    @Test func deletingABottleTakesItsNotes() throws {
        let context = try newContext()
        let wine = bottle(status: .want)
        context.insert(wine)
        for text in ["smells of tar", "and of roses"] {
            let note = TastingNote(kind: .text, phase: .pre, text: text)
            note.wine = wine
            context.insert(note)
        }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TastingNote>()).count == 2)

        #expect(wine.canDelete)
        context.delete(wine)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Wine>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TastingNote>()).isEmpty,
                "cascade, so no orphaned notes are left behind")
    }
}

// MARK: - Lifecycle

@Suite("The bottle lifecycle")
struct LifecycleTests {

    /// new → want → bought → tasted, driven exactly as the three commit paths
    /// drive it (`DetailView.set`, `BoughtSheet.confirm`, `TastingView.markTasted`),
    /// checking the user-visible consequences at each step.
    @Test func theHappyPath() {
        let wine = bottle(producer: "Rinaldi", status: .new, addedByHand: true)
        #expect(wine.statusLabel == "Added by hand")
        #expect(wine.showKeen)
        #expect(wine.canDelete)
        #expect(wine.verdict == nil)

        wine.status = .want
        #expect(wine.statusLabel == "Want to try")
        #expect(wine.showKeen)
        #expect(wine.canDelete)

        wine.status = .bought
        wine.boughtPrice = "42"
        wine.qty = 6
        #expect(wine.statusLabel == "In the rack")
        #expect(wine.isBought)
        #expect(wine.showKeen == false, "the keenness control is gone")
        #expect(wine.canDelete, "still deletable — nothing has been drunk")

        wine.status = .tasted
        wine.verdict = .loved
        wine.openedAt = Formatters.today()
        #expect(wine.statusLabel == "Tasted")
        #expect(wine.isTasted)
        #expect(wine.isBought == false)
        #expect(wine.showKeen == false)
        #expect(wine.canDelete == false, "the record is now permanent")
    }

    /// Marking tasted is one-way in the UI, but the model itself will happily
    /// go back — and doing so hands the trash icon back.
    @Test("FINDING: the model does not make `.tasted` terminal")
    func tastedIsNotTerminalInTheModel() {
        let wine = bottle(status: .tasted, verdict: .disliked)
        #expect(wine.canDelete == false)
        wine.status = .bought
        #expect(wine.canDelete, "documented current behaviour")
        #expect(wine.verdict == .disliked, "the verdict survives the walk-back")
        #expect(wine.statusLabel == "In the rack")
    }

    @Test("Verdict copy")
    func verdictCopy() {
        #expect(Verdict.loved.label == "Loved it")
        #expect(Verdict.meh.label == "Fine")
        #expect(Verdict.disliked.label == "Not for me")
        #expect(Verdict.loved.caption == "Buy it again")
        #expect(Verdict.meh.caption == "No hurry to repeat")
        #expect(Verdict.disliked.caption == "Note it and move on")
        #expect(Verdict.allCases.count == 3)
    }

    @Test("Verdict dots are the semantic traffic-light colours")
    func verdictDots() {
        #expect(rgba(Verdict.loved.dot) == rgba(Palette.green))
        #expect(rgba(Verdict.meh.dot) == rgba(Palette.yellow))
        #expect(rgba(Verdict.disliked.dot) == rgba(Palette.red))
        #expect(rgba(Verdict.loved.dot) != rgba(Verdict.disliked.dot))
    }

    /// Only `.bought` and `.tasted` get a colour of their own; the three
    /// keenness states are separated by opacity on the same rose, and `.new`
    /// and `.maybe` share theirs exactly.
    @Test func statusRails() {
        #expect(rgba(WineStatus.bought.rail) == rgba(Palette.green))
        #expect(rgba(WineStatus.want.rail) == rgba(Palette.rose(1.0)))
        #expect(rgba(WineStatus.tasted.rail) == rgba(Palette.rose(0.55)))
        #expect(rgba(WineStatus.new.rail) == rgba(Palette.rose(0.22)))
        #expect(rgba(WineStatus.not.rail) == rgba(Palette.rose(0.10)))

        // FINDING (cosmetic): Vinnota/Model/Enums.swift:23,25 — `.new` and
        // `.maybe` are both rose(0.22), so the dot on a card cannot tell a
        // freshly scanned bottle from one you deliberately shrugged at.
        #expect(rgba(WineStatus.maybe.rail) == rgba(WineStatus.new.rail),
                "documented current behaviour")
    }

    /// The accent drawn on the card dot, the search-row rail and the timeline:
    /// once there is a verdict it wins, whatever the status says.
    @Test func verdictAccentBeatsStatusAccent() {
        let untasted = bottle(status: .bought)
        #expect(rgba(untasted.accent) == rgba(WineStatus.bought.rail))

        let loved = bottle(status: .tasted, verdict: .loved)
        #expect(rgba(loved.accent) == rgba(Verdict.loved.dot))
        #expect(rgba(loved.accent) != rgba(WineStatus.tasted.rail))

        let disliked = bottle(status: .tasted, verdict: .disliked)
        #expect(rgba(disliked.accent) == rgba(Verdict.disliked.dot))

        // A verdict can be set on a bottle that was never marked tasted, and
        // it takes the accent over even then.
        let odd = bottle(status: .new, verdict: .meh)
        #expect(rgba(odd.accent) == rgba(Verdict.meh.dot))
        #expect(odd.statusLabel == "Scanned", "the chip still reads from status")
    }
}

// MARK: - Filter tabs
//
// The cellar's *stat counts* are not reachable from a test: `CellarView.stats`
// is a `private var` inside the `View` and counts the `@Query` array inline
// (`wines.count`, `wines.filter { $0.status != .tasted }.count`,
// `wines.filter { $0.verdict == .loved }.count`, Vinnota/Views/CellarView.swift
// :54-57). There is no seam, and re-implementing those three expressions here
// would test a copy rather than the app, so they are deliberately left untested
// — extracting them onto `Wine`/`Array<Wine>` is what would make them testable.
//
// The filter *predicate* is reachable: `WineFilter.matches(_:)` in
// Vinnota/Model/Enums.swift is what both CellarView and SearchView call, so the
// tests below drive the real thing.

@Suite("WineFilter tabs")
struct FilterTests {

    @Test("The All tab shows every bottle, whatever its status",
          arguments: WineStatus.allCases)
    func allShowsEverything(status: WineStatus) {
        #expect(WineFilter.all.matches(bottle(status: status)))
    }

    @Test("Each tab shows exactly the one status it names",
          arguments: [
            (WineFilter.new,    WineStatus.new),
            (WineFilter.want,   WineStatus.want),
            (WineFilter.bought, WineStatus.bought),
            (WineFilter.tasted, WineStatus.tasted),
            (WineFilter.not,    WineStatus.not),
          ])
    func eachTabIsOneStatus(filter: WineFilter, status: WineStatus) {
        for candidate in WineStatus.allCases {
            #expect(filter.matches(bottle(status: candidate)) == (candidate == status),
                    "\(filter.rawValue) vs \(candidate.rawValue)")
        }
    }

    /// FINDING: Vinnota/Model/Enums.swift:35 — `WineFilter` has no `maybe`
    /// case, so a bottle marked "Undecided" appears under All and under nothing
    /// else. Every other status has a tab. The three-way keenness control can
    /// therefore file a bottle somewhere the cellar cannot filter back to.
    @Test("FINDING: an Undecided bottle has no tab of its own")
    func undecidedBottlesHaveNoTab() {
        let undecided = bottle(status: .maybe)
        #expect(undecided.statusLabel == "Undecided")

        let tabsShowingIt = WineFilter.allCases.filter { $0.matches(undecided) }
        #expect(tabsShowingIt == [.all], "documented current behaviour")

        #expect(WineFilter.allCases.count == 6)
        #expect(WineStatus.allCases.count == 6)
        #expect(Set(WineFilter.allCases.map(\.rawValue)).contains("maybe") == false)
    }

    /// The predicate compares raw values, so the two enums are coupled by
    /// string. This pins the coupling down: renaming a `WineStatus` raw value
    /// without renaming the matching `WineFilter` one would silently empty a tab.
    @Test func tabsAreMatchedToStatusesByRawValue() {
        for filter in WineFilter.allCases where filter != .all {
            let matching = WineStatus.allCases.filter { $0.rawValue == filter.rawValue }
            #expect(matching.count == 1,
                    "the \(filter.rawValue) tab must name a real status")
            #expect(filter.matches(bottle(status: matching[0])))
        }
    }

    @Test("Tab copy")
    func tabCopy() {
        #expect(WineFilter.all.label == "All")
        #expect(WineFilter.new.label == "Scanned")
        #expect(WineFilter.want.label == "Wanted")
        #expect(WineFilter.bought.label == "In the rack")
        #expect(WineFilter.tasted.label == "Tasted")
        #expect(WineFilter.not.label == "Passed")
    }

    /// The tab label and the chip on the card are allowed to differ — "Wanted"
    /// vs "Want to try" — but the two that claim to be the same word must be.
    @Test func tabLabelsAgreeWithChipsWhereTheyClaimTo() {
        #expect(WineFilter.new.label == WineStatus.new.label)
        #expect(WineFilter.bought.label == WineStatus.bought.label)
        #expect(WineFilter.tasted.label == WineStatus.tasted.label)
        #expect(WineFilter.not.label == WineStatus.not.label)
        #expect(WineFilter.want.label != WineStatus.want.label)
    }

    /// SearchView composes the two predicates with `&&`; both halves must hold.
    /// This drives the same composition over a small book.
    @Test func searchAndFilterCompose() {
        let book = [
            bottle(producer: "Giuseppe Rinaldi", region: "Barolo", status: .bought),
            bottle(producer: "G.D. Vajra",       region: "Barolo", status: .tasted),
            bottle(producer: "Clos Rougeard",    region: "Saumur", status: .bought),
        ]

        func results(_ query: String, _ filter: WineFilter) -> [String] {
            book.filter { $0.matches(query: query) && filter.matches($0) }.map(\.producer)
        }

        #expect(results("", .all).count == 3)
        #expect(results("barolo", .all).count == 2)
        #expect(results("barolo", .bought) == ["Giuseppe Rinaldi"])
        #expect(results("barolo", .tasted) == ["G.D. Vajra"])
        #expect(results("saumur", .tasted).isEmpty)
        #expect(results("   ", .bought).count == 2, "a blank query leaves the tab alone")
        #expect(results("riesling", .all).isEmpty)
    }
}
