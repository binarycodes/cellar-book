import Foundation

enum Formatters {
    private static let months = ["Jan","Feb","Mar","Apr","May","Jun",
                                 "Jul","Aug","Sep","Oct","Nov","Dec"]

    /// "05 Sep · 14:32" — the design's `now()`.
    static func stamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: date)
        let p = { (n: Int) in String(format: "%02d", n) }
        return "\(p(c.day ?? 1)) \(months[(c.month ?? 1) - 1]) · \(p(c.hour ?? 0)):\(p(c.minute ?? 0))"
    }

    /// "05 Sep 2026" — the design's `today()`.
    static func today(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d", c.day ?? 1) + " " + months[(c.month ?? 1) - 1] + " \(c.year ?? 2026)"
    }
}
