import CoreGraphics
import Foundation
import Testing

@testable import Vinnota

// MARK: - Seam
//
// `LabelScanner.read(_:)` needs Vision and a camera frame, neither of which
// exists headlessly. `LabelScanner.parse(_:)` is already `internal static` and
// is the whole of the wine-specific logic: `read` does nothing but turn
// observations into `(text, height)` pairs and hand them over. So these tests
// drive `parse` directly through the seam that already exists — no access
// levels in the app were changed.

/// A recognised line, as Vision would hand it over: the text plus the glyph
/// height that the ranking heuristic treats as prominence.
private func line(_ text: String, _ height: CGFloat) -> (text: String, height: CGFloat) {
    (text: text, height: height)
}

/// Parses a label given as tallest-to-shortest lines, which is how the
/// heuristic actually thinks about a bottle.
private func parse(_ pairs: [(String, CGFloat)]) -> LabelReading {
    LabelScanner.parse(pairs.map { line($0.0, $0.1) })
}

/// Puts one line of interest next to an inert, taller producer line, so the
/// only thing that can move a field is the line under test.
private func parse(withNeutralProducer text: String) -> LabelReading {
    parse([("Winery", 0.09), (text, 0.04)])
}

/// Seconds spent in `parse`, for the robustness budgets below.
private func elapsed(_ body: () -> Void) -> TimeInterval {
    let start = Date()
    body()
    return Date().timeIntervalSince(start)
}

/// Generous enough never to flake on a loaded CI machine, tight enough that a
/// quadratic blow-up or a runaway scan fails instead of wedging the suite.
private let budget: TimeInterval = 20

// MARK: - Vintage

@Suite("LabelScanner · vintage extraction")
struct LabelScannerVintageTests {

    @Test("Plain four-digit vintages are read", arguments: [
        "2019", "1985", "2021", "1950", "2049",
    ])
    func plainVintages(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == text)
    }

    @Test("The plausible range is 1950...2049 inclusive", arguments: [
        ("1949", ""), ("1950", "1950"), ("2049", "2049"), ("2050", ""),
        ("1899", ""), ("1888", ""), ("2100", ""),
    ])
    func rangeBoundaries(_ text: String, _ expected: String) {
        #expect(parse(withNeutralProducer: text).vintage == expected)
    }

    /// The range is fixed, not relative to today, so a vintage in the near
    /// future is accepted rather than rejected as impossible. That is the
    /// right call for a wine app — futures and en-primeur labels are real —
    /// and this pins it so it cannot drift silently.
    @Test("A near-future year is accepted; an implausibly old one is not")
    func futureAndAncient() {
        #expect(parse(withNeutralProducer: "2049").vintage == "2049")
        #expect(parse(withNeutralProducer: "1899").vintage == "")
    }

    @Test("Alcohol percentages are not vintages", arguments: [
        "13.5%", "ALC. 13.5% BY VOL.", "ALC 14,5 % VOL", "12.5% ALC/VOL", "ALC 13% BY VOL",
    ])
    func alcoholIsNotAVintage(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == "")
    }

    @Test("Bottle volumes are not vintages", arguments: [
        "750 ML", "750ML", "e 750ml", "75 CL", "0.75 L", "1500 ML", "37.5 CL",
    ])
    func volumeIsNotAVintage(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == "")
    }

    @Test("Other three- and five-digit numbers are not vintages", arguments: [
        "750", "999", "12345", "1234567", "€ 24,95", "0000",
    ])
    func otherNumbersAreNotVintages(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == "")
    }

    /// FINDING (LabelScanner.swift:91): the year is matched anywhere in the
    /// text, with nothing distinguishing a vintage from any other in-range
    /// four-digit number on the label. A founding date — which appears on a
    /// great many labels — is therefore read as the vintage. Not fixed here;
    /// this asserts what the parser actually does today, and the Review screen
    /// is where the user would have to catch it.
    @Test("FINDING: a founding date is read as the vintage", arguments: [
        ("EST. 1978", "1978"),
        ("ESTABLISHED 1978", "1978"),
        ("FONDATA NEL 1961", "1961"),
        ("LOT 2019", "2019"),
    ])
    func foundingDateBecomesVintage(_ text: String, _ wrongVintage: String) {
        #expect(parse(withNeutralProducer: text).vintage == wrongVintage)
    }

    /// FINDING (LabelScanner.swift:91): a magnum-scale volume that happens to
    /// land in the plausible range is read as a vintage, where 750 ML and
    /// 1500 ML are correctly ignored.
    @Test("FINDING: a volume inside the plausible range is read as a vintage")
    func inRangeVolumeBecomesVintage() {
        #expect(parse(withNeutralProducer: "1500 ML").vintage == "")
        #expect(parse(withNeutralProducer: "2000 ML").vintage == "2000")
    }

    @Test("A year embedded in a longer phrase is still extracted", arguments: [
        "Vintage 2019", "Anno 2019", "HARVESTED IN 2019 BY HAND",
    ])
    func embeddedYear(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == "2019")
    }

    @Test("Serif look-alike glyphs are corrected when two real digits remain", arguments: [
        ("2O19", "2019"), ("2OI9", "2019"), ("2Ol9", "2019"),
        ("202I", "2021"), ("I999", "1999"), ("l985", "1985"),
    ])
    func confusablesCorrected(_ text: String, _ expected: String) {
        #expect(parse(withNeutralProducer: text).vintage == expected)
    }

    /// The two-real-digit guard is what stops ordinary four-letter words from
    /// being folded into years, and it is the only thing standing between the
    /// confusable pass and nonsense vintages.
    @Test("Four-letter words are not folded into years", arguments: [
        "BOOK", "LOOK", "POOL", "GOOD", "SOIL", "ZOI9", "OZIO", "GOLD",
    ])
    func wordsAreNotYears(_ text: String) {
        #expect(parse(withNeutralProducer: text).vintage == "")
    }

    @Test("A label with no year at all leaves the vintage blank")
    func noYearAnywhere() {
        let r = parse([("VIETTI", 0.09), ("PERBACCO", 0.06), ("NEBBIOLO", 0.04)])
        #expect(r.vintage == "")
        #expect(r.producer == "Vietti")
    }

    /// The line is consumed only when the year is essentially all of it
    /// (`count <= 6`), which decides whether it can go on to be picked as the
    /// cuvée.
    @Test("A bare year line is consumed; a wordy one stays in play as a cuvée")
    func yearLineConsumption() {
        let bare = parse([("Winery", 0.09), ("2019", 0.04), ("Cuvée Blanche", 0.06)])
        #expect(bare.vintage == "2019")
        #expect(bare.name == "Cuvée Blanche")

        let wordy = parse([("Winery", 0.09), ("Vintage 2019", 0.04)])
        #expect(wordy.vintage == "2019")
        #expect(wordy.name == "Vintage 2019")
    }
}

// MARK: - Field assignment

@Suite("LabelScanner · producer, cuvée and region")
struct LabelScannerFieldTests {

    /// A Bordeaux label in the order it appears on the bottle: the château
    /// name is the tallest text, the appellation repeats below it, and the
    /// legal print is the smallest.
    @Test("Bordeaux: tallest line is the producer, next is the cuvée")
    func bordeaux() {
        let r = parse([
            ("CHÂTEAU MARGAUX", 0.09),
            ("MARGAUX", 0.06),
            ("2015", 0.05),
            ("GRAND VIN DE BORDEAUX", 0.03),
            ("MIS EN BOUTEILLE AU CHÂTEAU", 0.02),
            ("13.5% ALC/VOL", 0.015),
            ("750 ML", 0.015),
        ])
        #expect(r.producer == "Château Margaux")
        #expect(r.name == "Margaux")
        #expect(r.vintage == "2015")
        #expect(r.region == "Bordeaux")
        #expect(r.recognized)
    }

    @Test("Barolo: the appellation goes to region, not to producer")
    func barolo() {
        let r = parse([
            ("BAROLO", 0.08),
            ("Giacomo Conterno", 0.06),
            ("Cascina Francia", 0.05),
            ("2019", 0.04),
            ("PIEMONTE, IT", 0.03),
            ("DOCG", 0.03),
            ("14% VOL", 0.01),
        ])
        #expect(r.producer == "Giacomo Conterno")
        #expect(r.name == "Cascina Francia")
        #expect(r.region == "Barolo")
        #expect(r.vintage == "2019")
    }

    /// The appellation is consumed by the region rule even when it is the
    /// tallest text on the label, so the producer falls through to the next
    /// line down. This is the ranking assumption working as documented.
    @Test("A region taller than the producer still lands in region")
    func regionOutranksHeight() {
        let r = parse([("BAROLO", 0.10), ("Vietti", 0.05), ("2019", 0.03)])
        #expect(r.region == "Barolo")
        #expect(r.producer == "Vietti")
        #expect(r.name == "")
    }

    @Test("Burgundy: producer and cuvée survive a wall of legal boilerplate")
    func burgundy() {
        let r = parse([
            ("DOMAINE LEFLAIVE", 0.09),
            ("PULIGNY-MONTRACHET", 0.06),
            ("1ER CRU LES PUCELLES", 0.05),
            ("2018", 0.04),
            ("APPELLATION PULIGNY-MONTRACHET 1ER CRU CONTRÔLÉE", 0.02),
            ("PRODUCT OF FRANCE", 0.02),
            ("750ML", 0.015),
            ("ALC 13% BY VOL", 0.015),
        ])
        #expect(r.producer == "Domaine Leflaive")
        #expect(r.name == "Puligny-Montrachet")
        #expect(r.vintage == "2018")
        // Puligny-Montrachet is not on the appellation list, so nothing on a
        // white-Burgundy label matches and the region is simply left blank.
        #expect(r.region == "")
    }

    @Test("German label: region, grape, producer and cuvée all separate out")
    func germanLabel() {
        let r = parse([
            ("WEINGUT KELLER", 0.08),
            ("ABTSERDE", 0.06),
            ("RIESLING GG", 0.05),
            ("2019", 0.04),
            ("RHEINHESSEN", 0.03),
        ])
        #expect(r.producer == "Weingut Keller")
        #expect(r.name == "Abtserde")
        #expect(r.grape == "Riesling")
        #expect(r.region == "Rheinhessen")
        #expect(r.vintage == "2019")
    }

    @Test("Rioja: an all-caps label is title-cased for display")
    func rioja() {
        let r = parse([
            ("BODEGAS MUGA", 0.09),
            ("RESERVA", 0.06),
            ("RIOJA", 0.05),
            ("2018", 0.04),
            ("TEMPRANILLO", 0.03),
        ])
        #expect(r.producer == "Bodegas Muga")
        #expect(r.name == "Reserva")
        #expect(r.region == "Rioja")
        #expect(r.grape == "Tempranillo")
    }

    @Test("Accented appellations match and keep their diacritics")
    func accentedRegions() {
        let rhone = parse([("E. GUIGAL", 0.09), ("CÔTES DU RHÔNE", 0.06), ("2020", 0.04)])
        #expect(rhone.region == "Côtes du Rhône")
        #expect(rhone.producer == "E. Guigal")

        let priorat = parse([("MAS DOIX", 0.09), ("PRIORAT", 0.05), ("2017", 0.04)])
        #expect(priorat.region == "Priorat")
    }

    /// OCR routinely drops accents; the region list is matched
    /// diacritic-insensitively but reports the canonical spelling.
    @Test("An unaccented misread still snaps to the accented appellation")
    func diacriticInsensitiveRegion() {
        #expect(parse([("Producteur", 0.09), ("COTES DU RHONE", 0.05)]).region == "Côtes du Rhône")
    }

    @Test("A composed vs. decomposed accent parses identically")
    func unicodeNormalisation() {
        let composed = parse([("CHÂTEAU MARGAUX", 0.09), ("2015", 0.04)])
        let decomposed = parse([("CHA\u{0302}TEAU MARGAUX", 0.09), ("2015", 0.04)])
        #expect(composed.producer == decomposed.producer)
        #expect(composed.vintage == decomposed.vintage)
    }

    @Test("A misread place name snaps onto the known appellation")
    func snapToKnownRegion() {
        let r = parse([("Weingut Keller", 0.09), ("RIEINIESSEN, DE", 0.05), ("2019", 0.04)])
        #expect(r.region == "Rheinhessen, DE")
    }

    @Test("A place-plus-country-code line keeps the code upper-cased")
    func placeAndCountryCode() {
        #expect(parse([("Opus One", 0.09), ("napa valley, ca", 0.05)]).region == "Napa Valley, CA")
        #expect(parse([("Vietti", 0.09), ("PIEMONTE, IT", 0.05)]).region == "Piemonte, IT")
    }

    /// FINDING (LabelScanner.swift:194): the "Place, XX" shape is matched
    /// before the appellation list and consumes the line unconditionally, so a
    /// producer written with a country suffix — a common way to print an
    /// importer or estate line — is taken for a region and the producer is
    /// left empty.
    @Test("FINDING: a producer written 'Name, XX' is misread as a region")
    func producerWithCountrySuffixBecomesRegion() {
        let r = parse([("Weingut Keller, DE", 0.09), ("2019", 0.04)])
        #expect(r.region == "Weingut Keller, DE")
        #expect(r.producer == "")
        #expect(r.name == "")
    }

    /// FINDING (LabelScanner.swift:210-221): boilerplate is matched as an
    /// unanchored substring, and the list holds tokens as short as "cl",
    /// "ml", "alc", "vol" and "doc". Those appear inside ordinary producer
    /// names, so real estates are silently discarded from the producer
    /// ranking. "Clos …" and "Vol…" are not edge cases — they are two of the
    /// most common openings in French, Spanish and Italian wine.
    @Test("FINDING: producer names containing a boilerplate token are discarded", arguments: [
        "CLOS MOGADOR",         // "cl"
        "Clos des Papes",       // "cl"
        "VOLNAY",               // "vol"
        "Castello di Volpaia",  // "vol"
        "Malcolm Wines",        // "alc"
        "Docteur Wines",        // "doc"
    ])
    func realProducersReadAsBoilerplate(_ producer: String) {
        let r = parse([(producer, 0.09), ("2019", 0.04)])
        #expect(r.producer == "")
        #expect(r.name == "")
    }

    @Test("Producers without a boilerplate substring survive", arguments: [
        ("Domaine Leflaive", "Domaine Leflaive"),
        ("Emilio Moro", "Emilio Moro"),
        ("La Spinetta", "La Spinetta"),
        ("Vietti", "Vietti"),
    ])
    func ordinaryProducersSurvive(_ input: String, _ expected: String) {
        #expect(parse([(input, 0.09), ("2019", 0.04)]).producer == expected)
    }

    @Test("Genuine boilerplate never becomes the producer", arguments: [
        "PRODUCT OF FRANCE", "CONTAINS SULFITES", "MIS EN BOUTEILLE AU DOMAINE",
        "ESTATE BOTTLED", "GOVERNMENT WARNING", "APPELLATION CONTRÔLÉE",
        "IMBOTTIGLIATO ALL'ORIGINE", "750 ML", "ALC 13.5% BY VOL",
    ])
    func boilerplateIsNeverTheProducer(_ text: String) {
        #expect(parse([(text, 0.09)]).producer == "")
    }

    @Test("A grape line is consumed when it is little more than the variety")
    func grapeConsumption() {
        let bare = parse([("Domaine X", 0.09), ("Pinot Noir", 0.05), ("2019", 0.04)])
        #expect(bare.grape == "Pinot Noir")
        #expect(bare.name == "")

        // Longer than variety + 4, so it stays and can still be the cuvée.
        let wordy = parse([("Domaine X", 0.09), ("Pinot Noir Reserve Bottling", 0.05), ("2019", 0.04)])
        #expect(wordy.grape == "Pinot Noir")
        #expect(wordy.name == "Pinot Noir Reserve Bottling")

        // The cut is at variety + 4 characters. "Riesling" is 8, so 11 is
        // consumed and 13 is not — a pair that straddles the threshold, which
        // the two cases above (exactly equal, and far over) leave unpinned.
        let justUnder = parse([("Weingut X", 0.09), ("Riesling GG", 0.05), ("2019", 0.04)])
        #expect(justUnder.grape == "Riesling")
        #expect(justUnder.name == "")

        let justOver = parse([("Weingut X", 0.09), ("Riesling Sekt", 0.05), ("2019", 0.04)])
        #expect(justOver.grape == "Riesling")
        #expect(justOver.name == "Riesling Sekt")
    }
}

// MARK: - The `recognized` flag

@Suite("LabelScanner · the recognized flag")
struct LabelScannerRecognizedTests {

    /// `recognized` drives the Review screen's "Read off the label"
    /// confirmation, so it must be false exactly when the parse produced
    /// nothing worth confirming.
    @Test("Empty input is not recognized")
    func emptyInput() {
        let r = parse([])
        #expect(!r.recognized)
        #expect(r.producer.isEmpty)
        #expect(r.vintage.isEmpty)
    }

    @Test("A single legible line is recognized")
    func singleLine() {
        let r = parse([("CHÂTEAU MARGAUX", 0.09)])
        #expect(r.recognized)
        #expect(r.producer == "Château Margaux")
    }

    @Test("A year alone is enough to count as recognized")
    func yearAlone() {
        let r = parse([("2019", 0.05)])
        #expect(r.recognized)
        #expect(r.vintage == "2019")
        #expect(r.producer == "")
    }

    @Test("Input that yields neither a producer nor a vintage is not recognized", arguments: [
        [("750", 0.05), ("13.5", 0.04), ("12345", 0.03)],
        [("!!!!!!", 0.05), ("...---...", 0.04)],
        [("PRODUCT OF FRANCE", 0.05), ("CONTAINS SULFITES", 0.04)],
        [("", 0.05), ("", 0.04)],
        [("   ", 0.05), ("\t\n", 0.04)],
    ] as [[(String, CGFloat)]])
    func notRecognized(_ lines: [(String, CGFloat)]) {
        #expect(!parse(lines).recognized)
    }

    /// FINDING (LabelScanner.swift:86): `recognized` is derived from the
    /// producer and the vintage only. A label where the OCR read an
    /// appellation but no estate name and no year is reported as unrecognised
    /// even though `region` is populated, so the Review screen drops its
    /// "Read off the label" state while still showing a field that was in
    /// fact read off the label.
    @Test("FINDING: a region-only read is reported as unrecognized")
    func regionOnlyIsNotRecognized() {
        let r = parse([("BAROLO", 0.05)])
        #expect(r.region == "Barolo")
        #expect(!r.recognized)
    }

    /// The same holds for a grape-only read, and pinning the rule case by case
    /// is what makes the two FINDINGs above legible. The expected flag is
    /// written out rather than recomputed from the parser's own output —
    /// re-deriving it from `producer`/`vintage` would just restate line 86 and
    /// would hold however badly the fields themselves were filled in.
    @Test("recognized is exactly 'a producer or a vintage was found'", arguments: [
        ([("CHÂTEAU MARGAUX", 0.09), ("2015", 0.04)], true),   // both
        ([("2019", 0.05)], true),                              // vintage only
        ([("Vietti", 0.09)], true),                            // producer only
        ([("BAROLO", 0.05)], false),                           // region only
        ([("CHARDONNAY", 0.05)], false),                       // grape only
        ([("750 ML", 0.05)], false),                           // boilerplate only
        ([], false),                                           // nothing
    ] as [([(String, CGFloat)], Bool)])
    func recognizedInvariant(_ lines: [(String, CGFloat)], _ expected: Bool) {
        let r = parse(lines)
        #expect(r.recognized == expected)
        // and the rule it is meant to encode still describes those cases
        #expect(r.recognized == !(r.producer.isEmpty && r.vintage.isEmpty))
    }

    @Test("A default LabelReading, as read() returns for an unusable frame, is not recognized")
    func defaultReading() {
        let r = LabelReading()
        #expect(!r.recognized)
        #expect(r.producer.isEmpty && r.name.isEmpty && r.vintage.isEmpty)
        #expect(r.region.isEmpty && r.grape.isEmpty)
    }
}

// MARK: - Robustness against untrusted camera input

@Suite("LabelScanner · hostile and malformed input")
struct LabelScannerRobustnessTests {

    /// Everything here is text the camera could plausibly produce, whether by
    /// pointing it at a wall of small print, a foreign-language label, or
    /// something that is not a bottle at all. None of it may crash the parse
    /// or run away: an index-out-of-range or an unbounded scan here is a
    /// crash-on-photo bug in the field.

    @Test("An extremely long single line terminates without crashing")
    func veryLongLine() {
        let long = String(repeating: "CHÂTEAU MARGAUX GRAND VIN ", count: 800)   // ~20k chars
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([(long, 0.09), ("2019", 0.04)]) }
        #expect(seconds < budget)
        #expect(reading.vintage == "2019")
        // Not merely non-empty: the long line is still tidied and assigned,
        // so the producer starts with the text that was actually on it.
        #expect(reading.producer.hasPrefix("Château Margaux Grand Vin"))
        #expect(reading.producer.hasSuffix("Château Margaux Grand Vin"))   // trailing space trimmed
    }

    @Test("Thousands of lines terminate without crashing")
    func thousandsOfLines() {
        let many = (0..<1000).map { ("Line number \($0) of label text", CGFloat($0) / 1000) }
        var reading = LabelReading()
        let seconds = elapsed { reading = parse(many) }
        #expect(seconds < budget)
        #expect(reading.recognized)
        // The tallest line wins the producer slot, whatever it happens to be.
        #expect(reading.producer == "Line number 999 of label text")
    }

    @Test("A very long run of repeated digits terminates and yields nothing")
    func repeatedDigits() {
        var nines = LabelReading()
        var cycled = LabelReading()
        let seconds = elapsed {
            nines = parse([(String(repeating: "9", count: 20_000), 0.05)])
            cycled = parse([(String(repeating: "1234567890", count: 2_000), 0.05)])
        }
        #expect(seconds < budget)
        #expect(!nines.recognized)
        #expect(!cycled.recognized)
        #expect(nines.vintage == "")
        #expect(cycled.vintage == "")
    }

    @Test("Punctuation-only text is rejected rather than named a producer", arguments: [
        String(repeating: "!@#$%^&*()", count: 200),
        "................",
        "-----",
        "'''''''",
        "«»¿¡§¶†‡",
        "\\\\//||",
    ])
    func punctuationOnly(_ text: String) {
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([(text, 0.05)]) }
        #expect(seconds < budget)
        #expect(reading.producer == "")
        #expect(!reading.recognized)
    }

    @Test("Degenerate unicode is handled without crashing", arguments: [
        "\u{0301}\u{0301}\u{0301}\u{0301}",          // orphan combining marks
        "\u{200B}\u{200D}\u{FEFF}",                  // zero-width and BOM
        "\u{202E}gnitset",                            // right-to-left override
        "\u{202A}\u{202B}\u{202C}\u{202D}",           // unpaired bidi embeddings
        "👨‍👩‍👧‍👦",                                        // ZWJ grapheme cluster
        "🍷🍷🍷🍷🍷",
        "\u{FFFD}\u{FFFD}",                          // replacement characters
        "a\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}", // stacked diacritics
    ])
    func degenerateUnicode(_ text: String) {
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([(text, 0.05), ("Winery", 0.09)]) }
        #expect(seconds < budget)
        // The only contract is that it comes back at all, with the ordinary
        // line still winning the producer slot.
        #expect(reading.producer == "Winery")
    }

    @Test("A combining-mark bomb terminates")
    func combiningMarkBomb() {
        let bomb = "A" + String(repeating: "\u{0301}", count: 5_000)
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([(bomb, 0.05), ("Winery", 0.09)]) }
        #expect(seconds < budget)
        #expect(reading.producer == "Winery")
    }

    @Test("A long run of ZWJ emoji clusters terminates")
    func emojiClusters() {
        let soup = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([(soup, 0.05), ("Winery", 0.09)]) }
        #expect(seconds < budget)
        #expect(reading.producer == "Winery")
    }

    @Test("Right-to-left and non-Latin scripts parse without crashing")
    func rightToLeftScripts() {
        let arabic = parse([("نبيذ أحمر", 0.06), ("Château", 0.09)])
        #expect(arabic.producer == "Château")

        let hebrew = parse([("יין אדום", 0.06), ("2019", 0.04)])
        #expect(hebrew.vintage == "2019")

        // Arabic-Indic digits are not ASCII digits and are not read as a year.
        #expect(parse(withNeutralProducer: "٢٠١٩").vintage == "")

        let cjk = parse([("赤ワイン", 0.06), ("2019", 0.04)])
        #expect(cjk.vintage == "2019")
    }

    /// The "Place, XX" shape only fires for a 3...30 character place. Asserting
    /// the producer alone would pass whatever the region rule did with these,
    /// so each case pins whether the line was taken as a region at all.
    @Test("The 'Place, XX' shape fires only for a 3...30 character place", arguments: [
        ("A, DE", false),                                     // 1 — below the floor
        ("AB, DE", false),                                    // 2 — below the floor
        ("ABC, DE", true),                                    // 3 — the floor itself
        ("ABCDE, DE", true),
        ("ABCDEF, DE", true),
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZABCD, DE", true),         // 30 — the ceiling
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZABCDE, DE", false),       // 31 — over it
    ])
    func shapeLengthBoundaries(_ text: String, _ isRegion: Bool) {
        var reading = LabelReading()
        let seconds = elapsed { reading = parse([("Winery", 0.09), (text, 0.05)]) }
        #expect(seconds < budget)
        #expect(reading.producer == "Winery")
        #expect(reading.region.hasSuffix(", DE") == isRegion)
        // A line rejected by the shape is not consumed, so it stays in the
        // ranking and becomes the cuvée instead.
        #expect(reading.name.isEmpty == isRegion)
    }

    /// `snapToKnownRegion` spends a tiered edit budget: nothing under six
    /// characters, one edit at six to eight, two above. Only the long-name tier
    /// is exercised elsewhere, so the two cheaper tiers are pinned here — a
    /// widened budget is exactly the change that would start snapping unrelated
    /// estates onto appellations.
    @Test("The snapping budget is nothing under six characters, one edit at six", arguments: [
        ("Mosek, DE", "Mosek, DE"),     // 5 chars, one edit from Mosel — no leeway
        ("Baralo, IT", "Barolo, IT"),   // 6 chars, one edit from Barolo — snaps
        ("Barala, IT", "Barala, IT"),   // 6 chars, two edits — over budget
        ("Chiantt, IT", "Chianti, IT"), // 7 chars, one edit — snaps
    ])
    func snapBudgetTiers(_ text: String, _ expected: String) {
        #expect(parse([("Winery", 0.09), (text, 0.05)]).region == expected)
    }

    @Test("Repeating a snap-eligible line many times terminates")
    func manySnapCandidates() {
        let lines = (0..<500).map { _ in ("Rieiniessen, DE", CGFloat(0.05)) }
        var reading = LabelReading()
        let seconds = elapsed { reading = parse(lines) }
        #expect(seconds < budget)
        #expect(reading.region == "Rheinhessen, DE")
    }

    @Test("Zero and negative glyph heights do not break the ranking")
    func degenerateHeights() {
        // Equal heights leave the order to `sorted`, which is not stable, so
        // the contract is that the two lines fill the two slots — not which
        // one lands where. `!isEmpty` alone would also pass if both slots held
        // the same line, or a slice of one.
        let zero = parse([("Alpha", 0), ("Bravo", 0)])
        #expect(Set([zero.producer, zero.name]) == Set(["Alpha", "Bravo"]))

        let negative = parse([("Alpha", -1), ("Bravo", -2), ("2019", -3)])
        #expect(negative.producer == "Alpha")
        #expect(negative.vintage == "2019")

        let extreme = parse([("Alpha", .greatestFiniteMagnitude), ("Bravo", -.greatestFiniteMagnitude)])
        #expect(extreme.producer == "Alpha")
        #expect(extreme.name == "Bravo")
    }

    @Test("Every line being identical terminates and picks one of them")
    func identicalLines() {
        let lines = (0..<200).map { _ in ("Château Margaux", CGFloat(0.05)) }
        var reading = LabelReading()
        let seconds = elapsed { reading = parse(lines) }
        #expect(seconds < budget)
        #expect(reading.producer == "Château Margaux")
        #expect(reading.name == "Château Margaux")
    }
}
