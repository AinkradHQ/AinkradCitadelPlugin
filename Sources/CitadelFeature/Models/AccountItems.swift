import AinkradAppKit
import CitadelClient
import Foundation
import Observation

extension Schemas.LimitUnit: OpenWord {}

/// Screen 15 Accounts: the provider account pool, usage windows and fallback chains.
@MainActor
@Observable
final class AccountsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
    /// Every account read: the whole pool when this device may read it (the admin's), else the company's own.
    var accounts: [PoolAccount] = []
    /// "Whole pool" (decision #46): admin-only, off by default.
    var showsWholePool = false
    /// The pool report answered: this device is the admin's, so "Whole pool" may be shown.
    var canSeeWholePool = false
    /// The account the Limits tile edits.
    var pickedAccount: Int64?
    /// Each account's limits at `account:<id>` (decision #56: windows and caps per account only).
    var settings: [Int64: [String: ScopedSetting]] = [:]
    /// The server's values, what an account's ↺ goes back to.
    var serverSettings: [String: ScopedSetting] = [:]
    /// The agent whose fallback chain is shown, and that chain with its own entry first.
    var chainAgent: Int64?
    var chain: [FallbackEntry] = []

    /// The accounts on screen: the company's, or the whole pool.
    func visible(company: Int64) -> [PoolAccount] {
        showsWholePool ? accounts : accounts.filter { $0.companyIDs.contains(company) }
    }

    /// The account's warn line: its own setting, else the server's, else 80 %.
    func warnPercent(_ account: Int64) -> Int {
        Int(settings[account]?["account.warn_percent"]?.value ?? serverSettings["account.warn_percent"]?.value ?? 80)
    }
}

/// One account of the pool (decision #41) with what it used.
struct PoolAccount: Identifiable, Equatable, Sendable {
    enum Health: String, Sendable {
        case healthy
        case atLimit = "at limit"
        case flaky, unhealthy, disabled
    }

    let id: Int64
    var label: String
    var harness: String
    /// `metered` (API key, dollars) or `subscription` (tokens).
    var billing: String
    var status: String
    var statusReason: String?
    var statusUntil: Date?
    var configDir: String
    var companyIDs: [Int64]
    /// Provider drops in the account's drop window (`account.drop_window_secs`).
    var drops: Int64
    /// What each company used of it, all time.
    var companyTokens: [Int64: Int64]
    /// The harness's own plan windows (Claude's `rate_limit` signal).
    var signalWindows: [SignalWindow]
    /// Counted limits configured on the account.
    var limits: [AccountLimitInfo]

    var health: Health {
        switch status {
        case "limited": .atLimit
        case "unhealthy": .unhealthy
        case "disabled": .disabled
        default: drops > 0 ? .flaky : .healthy
        }
    }

    var isSubscription: Bool { billing == "subscription" }

    /// A company's share of the account's tokens, in percent; nil when nothing was used.
    func share(of company: Int64) -> Int? {
        let total = companyTokens.values.reduce(0, +)
        guard total > 0 else { return nil }
        return Int((Double(companyTokens[company] ?? 0) / Double(total) * 100).rounded())
    }

    /// The bars: the harness's windows first, then counted limits, each with the warn line.
    func windows(warnPercent: Int) -> [UsageWindow] {
        signalWindows.map {
            UsageWindow(
                id: "signal|\($0.name)", label: $0.label, fraction: $0.utilization,
                warnFraction: Double(warnPercent) / 100, resetsAt: $0.resetsAt, limit: nil)
        }
            + limits.map {
                UsageWindow(
                    id: "limit|\($0.unit)|\($0.windowSecs)", label: $0.windowLabel,
                    fraction: $0.max > 0 ? Double($0.used) / Double($0.max) : 0,
                    warnFraction: Double($0.warnPercent) / 100, resetsAt: nil, limit: $0)
            }
    }
}

/// One plan window as the harness reported it.
struct SignalWindow: Equatable, Sendable {
    var name: String
    var utilization: Double
    var resetsAt: Date?

    /// `five_hour` → "5 h", `seven_day` → "Weekly", `seven_day_opus` → "Weekly · opus".
    var label: String {
        let known = [("five_hour", "5 h"), ("seven_day", "Weekly"), ("one_hour", "1 h")]
        for (prefix, label) in known where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            return rest.isEmpty ? label : "\(label) · \(rest.replacingOccurrences(of: "_", with: " "))"
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }
}

/// A counted limit on an account: `max` of `unit` per rolling `windowSecs`.
struct AccountLimitInfo: Equatable, Sendable {
    var windowSecs: Int64
    /// `tokens` or `messages`.
    var unit: String
    var max: Int64
    var warnPercent: Int64
    var used: Int64

    /// "5 h", "7 d".
    var windowLabel: String { ScopedSetting.format(windowSecs, unit: "seconds") }
    /// "5 h ≤ 3.0M tok", "5 h ≤ 200 msg".
    var text: String { "\(windowLabel) ≤ \(Self.amount(max, unit: unit))" }

    static func amount(_ value: Int64, unit: String) -> String {
        unit == "messages" ? "\(value) msg" : "\(Fmt.tokens(value)) tok"
    }

    /// A typed window, "5 h ≤ 3M tok", "7d <= 200 msg": its length, cap and unit.
    static func parse(_ text: String) -> (windowSecs: Int64, max: Int64, unit: String)? {
        let parts = text.replacingOccurrences(of: "<=", with: "≤").split(separator: "≤")
        guard parts.count == 2, let window = ScopedSetting.parse(String(parts[0]), unit: "seconds"), window > 0
        else { return nil }
        var amount = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        var unit = "tokens"
        for suffix in [" msg", "msg", " messages", "messages"] where amount.hasSuffix(suffix) {
            amount = String(amount.dropLast(suffix.count))
            unit = "messages"
        }
        for suffix in [" tok", "tok", " tokens", "tokens"] where amount.hasSuffix(suffix) {
            amount = String(amount.dropLast(suffix.count))
        }
        guard let max = ScopedSetting.parse(amount, unit: unit == "messages" ? "count" : "tokens"), max > 0 else {
            return nil
        }
        return (window, max, unit)
    }
}

/// One usage bar: how full a window is, its warn line, when it resets.
struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    var label: String
    /// 0…1+, past 1 at the limit.
    var fraction: Double
    var warnFraction: Double
    var resetsAt: Date?
    /// The counted limit behind it; nil for the harness's own window.
    var limit: AccountLimitInfo?

    var percent: Int { Int((fraction * 100).rounded()) }
    var isAtLimit: Bool { fraction >= 1 }
    var isPastWarn: Bool { fraction >= warnFraction }
    /// At the limit the account is skipped, not broken: amber, never red (the mockup's claude-work).
    var tone: AinkradChartTone? { isAtLimit ? .warning : nil }

    /// "↺ 14:20" within a day, "↺ Mon 09:00" after; a counted window rolls, so it has none.
    func resetText(now: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
        guard resetsAt.timeIntervalSince(now) >= 86_400 || !calendar.isDate(resetsAt, inSameDayAs: now) else {
            return "↺ \(time)"
        }
        var style = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated)
        style.calendar = calendar
        return "↺ \(resetsAt.formatted(style)) \(time)"
    }
}

/// One entry of an agent's chain: its own (harness, model) first, then its fallbacks in order (E15.3).
struct FallbackEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(harness)|\(model)" }
    var harness: String
    var model: String
    /// The agent's own entry: always first, never moved or removed.
    var isOwn = false
}

extension FallbackEntry {
    /// The chain after a drag: the agent's own entry stays first whatever was dropped above it.
    static func reordered(_ entries: [FallbackEntry]) -> [FallbackEntry] {
        entries.filter(\.isOwn) + entries.filter { !$0.isOwn }
    }

    /// What `PUT /agents/{id}/fallbacks` takes: the fallbacks only, in order.
    static func body(_ entries: [FallbackEntry]) -> [Schemas.Fallback] {
        entries.filter { !$0.isOwn }.map {
            Schemas.Fallback(harness: .init(value1: .init(rawValue: $0.harness), value2: $0.harness), model: $0.model)
        }
    }
}

extension PoolAccount {
    init(_ account: Schemas.Account, usage: Schemas.AccountUsage?) {
        self.init(
            id: account.id, label: account.label, harness: account.harness.word, billing: account.billing.word,
            status: account.status.word, statusReason: account.statusReason, statusUntil: account.statusUntil,
            configDir: account.configDir, companyIDs: account.companyIds, drops: usage?.drops ?? 0,
            companyTokens: Dictionary(
                (usage?.companies ?? []).map { ($0.companyId, $0.tokens) }, uniquingKeysWith: +),
            signalWindows: usage.map { Self.signalWindows($0.signal?.value) } ?? [],
            limits: (usage?.limits ?? []).map {
                AccountLimitInfo(
                    windowSecs: $0.limit.windowSecs, unit: $0.limit.unit.word, max: $0.limit.max,
                    warnPercent: $0.limit.warnPercent, used: $0.used)
            })
    }

    /// `{"type": "rate_limit", "windows": [{"name", "utilization", "resets_at"}]}`.
    static func signalWindows(_ signal: [String: (any Sendable)?]?) -> [SignalWindow] {
        guard let windows = signal?["windows"] as? [(any Sendable)?] else { return [] }
        return windows.compactMap { item -> SignalWindow? in
            guard let window = item as? [String: (any Sendable)?], let name = window["name"] as? String,
                let used = Self.number(window["utilization"] ?? nil)
            else { return nil }
            let resets = Self.number(window["resets_at"] ?? nil).map { Date(timeIntervalSince1970: $0) }
            return SignalWindow(name: name, utilization: used, resetsAt: resets)
        }
        .sorted { $0.name < $1.name }
    }

    private static func number(_ value: (any Sendable)?) -> Double? {
        switch value {
        case let number as Double: number
        case let number as Int: Double(number)
        case let number as Int64: Double(number)
        default: nil
        }
    }
}
