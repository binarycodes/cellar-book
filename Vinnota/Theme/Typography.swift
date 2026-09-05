import SwiftUI
import CoreText
import UIKit

/// The design system ships Instrument Sans as a single *variable* font
/// (`wght` 400–700, `wdth` 75–100). iOS will not interpolate a variable
/// axis for you — `UIFont(name:size:)` always yields the default instance —
/// so weights are produced by setting the `wght` axis through CoreText.
enum Typo {
    private static let sansFamily = "Instrument Sans"
    private static let serifRegular = "InstrumentSerif-Regular"
    private static let serifItalic  = "InstrumentSerif-Italic"

    /// Four-character axis codes as CoreText expects them.
    private static let wghtAxis: Int = 0x77676874  // 'wght'

    private static var cache: [String: UIFont] = [:]

    /// Instrument Sans at an explicit variable weight.
    static func sans(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        Font(uiSans(size, weight))
    }

    static func uiSans(_ size: CGFloat, _ weight: CGFloat = 400) -> UIFont {
        let key = "sans-\(size)-\(weight)"
        if let hit = cache[key] { return hit }

        let base = UIFontDescriptor(fontAttributes: [.family: sansFamily])
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let varied = base.addingAttributes([variationKey: [wghtAxis: weight]])
        let font = UIFont(descriptor: varied, size: size)
        cache[key] = font
        return font
    }

    /// Instrument Serif — the display face used for headlines and numerals.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? serifItalic : serifRegular, size: size)
    }

    /// Registers the bundled faces. Info.plist `UIAppFonts` covers this for
    /// the app target, but registering explicitly also makes the faces
    /// available to previews and to unit tests.
    static func registerFonts() {
        for name in ["InstrumentSans", "InstrumentSerif-Regular", "InstrumentSerif-Italic"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension View {
    /// The design's recurring eyebrow: 11px, uppercase, wide tracking.
    func eyebrow(_ opacity: Double = 0.5) -> some View {
        self.font(Typo.sans(11, 500))
            .tracking(11 * 0.14)
            .textCase(.uppercase)
            .foregroundStyle(Palette.rose(opacity))
    }

    /// Section label: 11px uppercase, 0.1em tracking, 45% rose.
    func sectionLabel() -> some View {
        self.font(Typo.sans(11))
            .tracking(11 * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textMuted)
    }
}
