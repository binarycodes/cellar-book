import UIKit
import Vision

/// What the OCR pass managed to read off a bottle. Every field is a guess the
/// user then corrects — the Review screen exists precisely because the design
/// says "the year is the usual culprit".
struct LabelReading {
    var producer = ""
    var name = ""
    var vintage = ""
    var region = ""
    var grape = ""
    /// False when nothing legible was found, which switches the Review screen
    /// out of its "Read off the label" confirmation state.
    var recognized = false
}

/// Reads a wine label with Vision, then applies wine-specific heuristics to
/// sort the recognised lines into fields.
///
/// The ranking assumption — the producer is the most prominent text on a wine
/// label — holds for the large majority of bottles and is cheap to correct
/// when it doesn't.
enum LabelScanner {

    static func read(_ image: UIImage) async -> LabelReading {
        guard let cgImage = image.cgImage else { return LabelReading() }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // proper nouns, not prose
        request.recognitionLanguages = ["en-US", "fr-FR", "it-IT", "es-ES", "de-DE"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image), options: [:])
        do { try handler.perform([request]) } catch { return LabelReading() }

        let observations = request.results ?? []
        // (text, glyph height) — height is the prominence signal.
        let lines: [(text: String, height: CGFloat)] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 1 else { return nil }
            return (text, obs.boundingBox.height)
        }
        guard !lines.isEmpty else { return LabelReading() }

        return parse(lines)
    }

    // MARK: - Heuristics

    static func parse(_ lines: [(text: String, height: CGFloat)]) -> LabelReading {
        var reading = LabelReading()
        var remaining = lines
        reading.recognized = true

        // 1. Vintage — a bare four-digit year in a plausible range.
        if let idx = remaining.firstIndex(where: { year(in: $0.text) != nil }) {
            reading.vintage = year(in: remaining[idx].text) ?? ""
            // Only consume the line if the year is essentially all of it.
            if remaining[idx].text.count <= 6 { remaining.remove(at: idx) }
        }

        // 2. Grape — match a known variety anywhere in the text.
        if let idx = remaining.firstIndex(where: { grape(in: $0.text) != nil }) {
            reading.grape = grape(in: remaining[idx].text) ?? ""
            if remaining[idx].text.count <= reading.grape.count + 4 { remaining.remove(at: idx) }
        }

        // 3. Region — a known appellation, or a "Place, XX" shape.
        if let idx = remaining.firstIndex(where: { region(in: $0.text) != nil }) {
            reading.region = region(in: remaining[idx].text) ?? ""
            remaining.remove(at: idx)
        }

        // 4. Producer — the tallest remaining line that isn't boilerplate.
        let candidates = remaining
            .filter { !isBoilerplate($0.text) }
            .sorted { $0.height > $1.height }
        if let top = candidates.first {
            reading.producer = tidy(top.text)
            // 5. Cuvée — the next tallest line becomes the cuvée or grape name.
            if let second = candidates.dropFirst().first { reading.name = tidy(second.text) }
        }

        if reading.producer.isEmpty && reading.vintage.isEmpty { reading.recognized = false }
        return reading
    }

    private static func year(in text: String) -> String? {
        if let match = text.range(of: #"\b(19[5-9]\d|20[0-4]\d)\b"#, options: .regularExpression) {
            return String(text[match])
        }
        // Serif numerals on wine labels routinely come back with letter
        // look-alikes — "202I" for 2021, "2OI9" for 2019. Correct a four-glyph
        // token only when it already holds at least two real digits and the
        // corrected value lands in a plausible vintage range, which keeps
        // ordinary words from being read as years.
        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            guard token.count == 4, token.filter(\.isNumber).count >= 2 else { continue }
            let corrected = String(token.map { confusables[$0] ?? $0 })
            guard corrected.allSatisfy(\.isNumber),
                  let value = Int(corrected),
                  (1950...2049).contains(value) else { continue }
            return corrected
        }
        return nil
    }

    /// Glyphs Vision commonly substitutes for digits in display serif faces.
    private static let confusables: [Character: Character] = [
        "I": "1", "l": "1", "|": "1", "i": "1",
        "O": "0", "o": "0", "Q": "0", "D": "0",
        "S": "5", "s": "5", "B": "8", "Z": "2", "z": "2",
        "g": "9", "q": "9", "G": "6", "T": "7",
    ]

    /// Case- and diacritic-insensitive Levenshtein distance.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        let y = Array(b.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    /// Snaps a misread place name onto a known one — "Rieiniessen" for
    /// "Rheinhessen". The budget is tiered rather than proportional: short
    /// names get no leeway at all, because one edit can carry you between two
    /// genuinely different places, while a long name can absorb two misread
    /// glyphs and still be unambiguous against the list. A wrong snap is
    /// visible and editable on the Review screen, which is what that screen
    /// is for.
    private static func snapToKnownRegion(_ place: String) -> String {
        let budget: Int
        switch place.count {
        case ..<6:  return place
        case 6...8: budget = 1
        default:    budget = 2
        }
        var best: (name: String, distance: Int)?
        for candidate in regions where abs(candidate.count - place.count) <= budget {
            let d = editDistance(place, candidate)
            if d <= budget, d < (best?.distance ?? Int.max) { best = (candidate, d) }
        }
        return best?.name ?? place
    }

    /// The varieties common enough to be worth matching by name.
    private static let grapes = [
        "Nebbiolo", "Sangiovese", "Barbera", "Dolcetto", "Corvina", "Aglianico",
        "Pinot Noir", "Pinot Nero", "Pinot Grigio", "Pinot Gris", "Pinot Blanc",
        "Chardonnay", "Sauvignon Blanc", "Cabernet Sauvignon", "Cabernet Franc",
        "Merlot", "Malbec", "Syrah", "Shiraz", "Grenache", "Garnacha", "Mourvèdre",
        "Tempranillo", "Bobal", "Monastrell", "Mencía", "Albariño", "Verdejo",
        "Riesling", "Grüner Veltliner", "Gewürztraminer", "Silvaner",
        "Chenin Blanc", "Gamay", "Trousseau", "Poulsard", "Savagnin",
        "Carignan", "Cinsault", "Zinfandel", "Primitivo", "Nerello Mascalese",
        "Listán Prieto", "Turbiana", "Vermentino", "Fiano", "Falanghina",
        "Viognier", "Marsanne", "Roussanne", "Assyrtiko", "Xinomavro", "Furmint",
    ]

    private static func grape(in text: String) -> String? {
        grapes.first { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static let regions = [
        "Barolo", "Barbaresco", "Chianti", "Brunello", "Montalcino", "Bolgheri",
        "Etna", "Piemonte", "Toscana", "Lombardia", "Veneto", "Friuli", "Lugana",
        "Bourgogne", "Burgundy", "Beaujolais", "Champagne", "Bordeaux", "Sancerre",
        "Chablis", "Côtes du Rhône", "Châteauneuf-du-Pape", "Jura", "Alsace", "Loire",
        "Rioja", "Ribera del Duero", "Priorat", "Rías Baixas", "Manchuela", "Jerez",
        "Douro", "Dão", "Vinho Verde", "Mosel", "Rheinhessen", "Pfalz", "Nahe",
        "Wachau", "Kamptal", "Tokaj", "Santorini", "Bekaa Valley",
        "Napa Valley", "Sonoma", "Willamette", "Sta. Rita Hills", "North Coast",
        "Barossa", "Margaret River", "Marlborough", "Central Otago", "Swartland",
        "Tenerife", "Canary Islands", "Sicilia", "Puglia", "Campania",
    ]

    private static func region(in text: String) -> String? {
        // "PIEMONTE, IT" — a place plus a country code. Checked first, because
        // it carries more than the bare appellation name does; the place is
        // tidied but the code stays upper-case.
        if text.range(of: #"^[\p{L}\s.'-]{3,30},\s*[A-Za-z]{2}$"#, options: .regularExpression) != nil {
            let parts = text.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 {
                return "\(snapToKnownRegion(tidy(parts[0]))), \(parts[1].uppercased())"
            }
            return tidy(text)
        }
        if let hit = regions.first(where: { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
            return hit
        }
        return nil
    }

    /// Legal and volumetric text that appears on every bottle and identifies none.
    private static let boilerplate = [
        "product of", "produce of", "contains sulfites", "contains sulphites",
        "mis en bouteille", "estate bottled", "imbottigliato", "alc", "vol",
        "ml", "cl", "75cl", "750", "appellation", "contrôlée", "controlee",
        "denominazione", "origine", "protetta", "controllata", "garantita",
        "doc", "docg", "igt", "aoc", "aop", "igp", "dop", "red wine", "white wine",
        "vin de france", "wine of", "government warning", "sulfites",
    ]

    private static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        if boilerplate.contains(where: { lower.contains($0) }) { return true }
        // Mostly digits or punctuation carries no name.
        let letters = text.filter { $0.isLetter }.count
        return letters < max(2, text.count / 3)
    }

    /// Labels are often set in full caps; title-case reads better in the app.
    private static func tidy(_ text: String) -> String {
        let stripped = text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'’-&.")))
        guard stripped == stripped.uppercased(), stripped.count > 3 else { return stripped }
        return stripped.capitalized(with: Locale.current)
    }

    private static func cgOrientation(_ image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
