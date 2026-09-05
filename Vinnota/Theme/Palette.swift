import SwiftUI

/// Colours transcribed verbatim from `Vinnota - Cellar Book.dc.html`.
/// The screen overrides the Aura light theme with its own wine palette,
/// so these are literal values from the design rather than Aura tokens.
enum Palette {
    /// Page ground — `rgb(24,8,13)`
    static let ground      = Color(red: 24/255,  green: 8/255,   blue: 13/255)
    /// Outside the device frame — `rgb(16,5,9)`
    static let deepGround  = Color(red: 16/255,  green: 5/255,   blue: 9/255)
    /// Scanner ground — `rgb(14,5,8)`
    static let scanGround  = Color(red: 14/255,  green: 5/255,   blue: 8/255)
    /// Sheets, cards, empty photo wells — `rgb(43,14,22)`
    static let surface     = Color(red: 43/255,  green: 14/255,  blue: 22/255)
    /// Primary action — `rgb(162,5,25)`
    static let burgundy    = Color(red: 162/255, green: 5/255,   blue: 25/255)
    /// Text on burgundy, and toast ground — `rgb(255,244,243)`
    static let ink         = Color(red: 255/255, green: 244/255, blue: 243/255)
    /// Links and accents — `rgb(255,180,186)`
    static let rosePink    = Color(red: 255/255, green: 180/255, blue: 186/255)
    /// Scan line — `rgb(230,90,95)`
    static let scanLine    = Color(red: 230/255, green: 90/255,  blue: 95/255)

    // Semantic, from Aura
    static let green  = Color(red: 0/255,   green: 159/255, blue: 52/255)
    static let yellow = Color(red: 255/255, green: 220/255, blue: 0/255)
    static let red    = Color(red: 219/255, green: 55/255,  blue: 58/255)

    /// Every muted foreground in the design is `rgba(255,228,230, α)`.
    static func rose(_ opacity: Double) -> Color {
        Color(red: 255/255, green: 228/255, blue: 230/255).opacity(opacity)
    }

    // Named opacities, so call sites read as intent rather than magic numbers.
    static let textPrimary   = Color.white
    static let textSecondary = rose(0.65)
    static let textTertiary  = rose(0.5)
    static let textMuted     = rose(0.45)
    static let textFaint     = rose(0.42)

    static let border       = rose(0.22)
    static let borderSoft   = rose(0.18)
    static let borderHair   = rose(0.14)
    static let borderFaint  = rose(0.09)

    static let fieldFill    = rose(0.06)
}
