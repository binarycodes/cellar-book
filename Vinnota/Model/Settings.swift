import Foundation

/// The three props the design exposes in its editor panel, promoted to real
/// preferences so the behaviour they gate is reachable at runtime.
///
/// Plain `UserDefaults` rather than `@AppStorage`: these are read from
/// services and models, not only from views, and `@AppStorage` on a static
/// property does not publish changes anyway.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let currency = "defaultCurrency"
        static let shelfPrice = "showShelfPrice"
        static let recognition = "labelRecognition"
    }

    static var defaultCurrency: CurrencyCode {
        get { (defaults.string(forKey: Key.currency).flatMap(CurrencyCode.init(rawValue:))) ?? .EUR }
        set { defaults.set(newValue.rawValue, forKey: Key.currency) }
    }

    /// Hides the shelf-price field and fact when off.
    static var showShelfPrice: Bool {
        get { defaults.object(forKey: Key.shelfPrice) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.shelfPrice) }
    }

    /// When off, the scanner skips OCR and opens an empty form — the design's
    /// `labelRecognition: false` path.
    static var labelRecognition: Bool {
        get { defaults.object(forKey: Key.recognition) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.recognition) }
    }
}
