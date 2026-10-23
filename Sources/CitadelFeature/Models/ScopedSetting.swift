import AinkradAppKit
import CitadelClient
import Foundation

extension Schemas.SettingScope: OpenWord {}
extension Schemas.SettingUnit: OpenWord {}

/// One tunable as the server resolves it at a scope (decision #52: server → company → project / runner / account,
/// the most specific wins). Shared by screens 10, 14, 15 and 16.
struct ScopedSetting: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    var description: String
    /// The effective value at the scope it was read at.
    var value: Int64
    var defaultValue: Int64
    var min: Int64
    var max: Int64
    /// `seconds`, `milliseconds`, `percent`, `count`, `tokens`, `bytes`, `per_minute`.
    var unit: String
    /// The kinds of scope it may be set at: `server`, `company`, `project`, `runner`, `account`.
    var scopes: [String]
    /// Where the value was set: `server`, `company:1`, `project:2`; `nil` is the built-in default.
    var source: String?

    /// Whether the value was set at exactly `scope` (`company:1`), so ↺ resets it there.
    func isSet(at scope: String) -> Bool { source == scope }

    /// The kind of scope the value comes from: `server` for a server value or the default.
    var sourceKind: String { source.map { String($0.split(separator: ":").first ?? "server") } ?? "server" }

    /// The scope chip (`AinkradScopedValue`): "↳ company" when inherited at `scope`, "● project · company 15 min"
    /// when set there, naming what ↺ would go back to (`inherited`, the parent scope's value, when known).
    func chip(at scope: String, inherited: ScopedSetting? = nil) -> AinkradValueScope {
        let kind = String(scope.split(separator: ":").first ?? "")
        guard isSet(at: scope) else { return .inherited(from: sourceKind) }
        return .overridden(at: kind, inheritedValue: inherited.map { "\($0.sourceKind) \($0.text)" })
    }

    /// The value as the screens print it: `15 min`, `50 GB`, `80%`, `200k`, `3`.
    var text: String { Self.format(value, unit: unit) }

    /// The bounds under the name: `1–120 min`, `5 GB – 1000 TB`.
    var bounds: String {
        let low = Self.format(min, unit: unit)
        let high = Self.format(max, unit: unit)
        return "\(low)–\(high)"
    }

    /// Whether a typed value parses and lies inside the bounds.
    func accepts(_ text: String) -> Bool { parse(text).map { (min...max).contains($0) } ?? false }

    /// A typed value in the setting's unit: `10 min`, `10m`, `2 h`, `50 GB`, `80%`, `200k`, `3`.
    func parse(_ text: String) -> Int64? { Self.parse(text, unit: unit) }

    static func format(_ value: Int64, unit: String) -> String {
        switch unit {
        case "seconds":
            if value != 0, value % 86_400 == 0 { return "\(value / 86_400) d" }
            if value != 0, value % 3600 == 0 { return "\(value / 3600) h" }
            if value != 0, value % 60 == 0 { return "\(value / 60) min" }
            return "\(value) s"
        case "milliseconds": return "\(value) ms"
        case "percent": return "\(value)%"
        case "tokens": return Fmt.tokens(value)
        case "bytes": return bytes(value)
        case "per_minute": return "\(value)/min"
        default: return "\(value)"
        }
    }

    /// `50 GB`, `2.1 KB`, `12.4 MB` (decimal, as the server counts).
    static func bytes(_ value: Int64) -> String {
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let double = Double(value)
        for (size, name) in units where double >= size {
            return "\((double / size).formatted(.number.precision(.fractionLength(0...1)))) \(name)"
        }
        return "\(value) B"
    }

    static func parse(_ text: String, unit: String) -> Int64? {
        let raw = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: "")
        let digits = raw.prefix { $0.isNumber || $0 == "." }
        guard let number = Double(digits) else { return nil }
        let suffix = raw.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let scale: Double? =
            switch unit {
            case "seconds":
                ["", "s", "sec", "secs"].contains(suffix)
                    ? 1
                    : ["m", "min", "mins"].contains(suffix)
                        ? 60
                        : ["h", "hr", "hrs"].contains(suffix)
                            ? 3600 : ["d", "day", "days"].contains(suffix) ? 86_400 : nil
            case "bytes":
                ["", "b"].contains(suffix)
                    ? 1
                    : ["k", "kb"].contains(suffix)
                        ? 1e3
                        : ["m", "mb"].contains(suffix)
                            ? 1e6 : ["g", "gb"].contains(suffix) ? 1e9 : ["t", "tb"].contains(suffix) ? 1e12 : nil
            case "tokens":
                ["", "tok"].contains(suffix) ? 1 : ["k"].contains(suffix) ? 1e3 : ["m"].contains(suffix) ? 1e6 : nil
            case "percent": ["", "%"].contains(suffix) ? 1 : nil
            case "milliseconds": ["", "ms"].contains(suffix) ? 1 : nil
            default: suffix.isEmpty || suffix == "/min" ? 1 : nil
            }
        guard let scale else { return nil }
        return Int64((number * scale).rounded())
    }
}

extension ScopedSetting {
    init(_ setting: Schemas.Setting) {
        self.init(
            key: setting.key, description: setting.description, value: setting.value, defaultValue: setting._default,
            min: setting.min, max: setting.max, unit: setting.unit.word, scopes: setting.scopes.map(\.word),
            source: setting.source)
    }
}

/// One audited set or reset of a setting (screen 16's recent changes).
struct SettingChangeInfo: Equatable, Sendable {
    var key: String
    var scope: String
    var old: Int64?
    var new: Int64?
    var at: Date
    var seq: Int64
    /// The agent that made it; `nil` for a person or the system.
    var agentID: Int64?
}

/// The scoped settings API (E15.17): list at a scope, set, reset (↺), history.
extension CitadelServer {
    /// Every setting that may be set at `scope` (`company:1`, `project:2`, `runner:3`, `account:4`; `server` lists
    /// the server values), with its effective value there.
    func settings(scope: String) async -> [ScopedSetting]? {
        await read("listSettings") {
            if scope == "server" {
                guard case .ok(let ok) = try await client.listServerSettings() else { return nil }
                return try ok.body.json.map(ScopedSetting.init)
            }
            guard case .ok(let ok) = try await client.listSettings(path: .init(scope: scope)) else { return nil }
            return try ok.body.json.map(ScopedSetting.init)
        }
    }

    /// Sets `key` at `scope`; the effective value there, or `nil` when refused (out of bounds, wrong scope).
    func setSetting(scope: String, key: String, value: Int64) async -> ScopedSetting? {
        await read("setSetting") {
            guard
                case .ok(let ok) = try await client.setSetting(
                    path: .init(scope: scope, key: key), body: .json(.init(value: value)))
            else { return nil }
            return ScopedSetting(try ok.body.json)
        }
    }

    /// ↺: drops the value set at `scope`; the value it inherits there now.
    func resetSetting(scope: String, key: String) async -> ScopedSetting? {
        await read("resetSetting") {
            guard case .ok(let ok) = try await client.resetSetting(path: .init(scope: scope, key: key)) else {
                return nil
            }
            return ScopedSetting(try ok.body.json)
        }
    }

    /// The sets and resets of `key` at `scope`, newest first.
    func settingHistory(scope: String, key: String) async -> [SettingChangeInfo]? {
        await read("settingHistory") {
            guard case .ok(let ok) = try await client.settingHistory(path: .init(scope: scope, key: key)) else {
                return nil
            }
            return try ok.body.json.map { change in
                var agent: Int64?
                if case .agent(let actor) = change.actor { agent = actor.agentId }
                return SettingChangeInfo(
                    key: key, scope: change.scope, old: change.old, new: change.new, at: change.at, seq: change.seq,
                    agentID: agent)
            }
        }
    }
}
