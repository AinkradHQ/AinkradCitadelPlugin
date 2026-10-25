import Foundation

/// What a budget cap is counted in (API minor 18): the priced dollars, or tokens as before.
enum BudgetUnit: String, CaseIterable, Hashable, Sendable {
    case dollars, tokens

    var title: String { self == .dollars ? "$" : "tokens" }

    /// A typed dollar amount (`900`, `$1,250.50`, `1.5k`, `2M`) as millionths of a dollar, or `nil` when it is
    /// not a number of 0 or more.
    static func parseDollars(_ text: String) -> Int64? {
        let raw = text.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        let scale: Double = raw.hasSuffix("m") ? 1e6 : raw.hasSuffix("k") ? 1e3 : 1
        guard let number = Double(scale == 1 ? raw : String(raw.dropLast())), number.isFinite, number >= 0 else {
            return nil
        }
        return Int64((number * scale * 1_000_000).rounded())
    }
}

extension BudgetUnit {
    /// A typed budget cap that must be above zero: tokens as `cap`, or dollars as `usdCap` (a dollars-only budget
    /// keeps no token cap).
    static func parseCap(_ text: String, unit: BudgetUnit) -> (cap: Int64, usdCap: Int64?)? {
        switch unit {
        case .tokens: TokenAmount.parse(text).flatMap { $0 > 0 ? ($0, nil) : nil }
        case .dollars: parseDollars(text).flatMap { $0 > 0 ? (0, $0) : nil }
        }
    }
}

extension Fmt {
    /// A budget's dollars: `$412` from $100 up, cents below (`$8.40`), `$1.2k` from a thousand.
    static func budgetDollars(micros: Int64) -> String {
        let value = Double(micros) / 1_000_000
        if value >= 10_000 { return "$\((value / 1_000).formatted(.number.precision(.fractionLength(0...1))))k" }
        let digits = value >= 100 || value == value.rounded() ? 0 : 2
        return value.formatted(.currency(code: "USD").precision(.fractionLength(digits)))
    }
}

extension BudgetInfo {
    /// The cap is in dollars (it has a dollar cap), else tokens.
    var isDollars: Bool { usdCap != nil }
    var unit: BudgetUnit { isDollars ? .dollars : .tokens }

    /// What the budget has used and may use, in its own unit (micro-dollars or tokens).
    var shownSpent: Int64 { isDollars ? usdSpent : spent }
    var shownCap: Int64 { isDollars ? (usdCap ?? 0) : cap }
    var shownFraction: Double { shownCap > 0 ? Double(shownSpent) / Double(shownCap) : 0 }

    func word(_ amount: Int64) -> String { isDollars ? Fmt.budgetDollars(micros: amount) : Fmt.tokens(amount) }
    var spentWord: String { word(shownSpent) }
    var capWord: String { word(shownCap) }
    /// `$412 / $900`, or `1.2M / 5M tok`.
    var pairWord: String { "\(spentWord) / \(capWord)" + (isDollars ? "" : " tok") }
    /// What "tokens" or "dollars" the budget counts, for a sentence.
    var unitNoun: String { isDollars ? "dollars" : "tokens" }
}
