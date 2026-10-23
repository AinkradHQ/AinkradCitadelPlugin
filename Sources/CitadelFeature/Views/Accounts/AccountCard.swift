import AinkradAppKit
import SwiftUI

/// One account: provider, label, billing, health, the companies it serves with their share, runs and drops, and
/// a bar per window with its warn mark, use and reset — plus why it is skipped or flaky.
struct AccountCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let account: PoolAccount
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        AinkradCard(onTap: { page.pickedAccount = account.id }) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(alignment: .top, spacing: skin.size.s14) {
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    windows.frame(width: skin.size.s280)
                }
                if let reason { reason.transition(.move(edge: .top).combined(with: .opacity)) }
            }
        }
        .rim(rim)
    }

    private var rim: AinkradChartTone? {
        switch account.health {
        case .atLimit: .warning
        case .flaky, .unhealthy: .danger
        default: nil
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack(spacing: skin.size.s8) {
                AinkradBadge(
                    text: AgentLook.harnessName(account.harness),
                    tint: AgentLook.harness(account.harness)?.color ?? theme.foreground
                )
                .fixedSize()
                Text(account.label).citadelFont("t13", weight: "semibold", mono: true)
                    .foregroundStyle(account.health == .atLimit ? status.warning : skin.color(skin.text.primary))
                    .lineLimit(1).layoutPriority(1)
                healthBadge.fixedSize()
            }
            HStack(spacing: skin.size.s6) {
                // Billing leads the second line so the label never truncates beside the windows column.
                AinkradBadge(
                    text: account.isSubscription ? "subscription" : "API key · priced",
                    tint: account.isSubscription ? skin.color(skin.palette.accentPrimary) : theme.accentSecondary
                )
                .fixedSize()
                companies
            }
            Text(meta).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }

    private var healthBadge: some View {
        switch account.health {
        case .healthy: AinkradBadge(text: "● healthy", status: .success)
        case .atLimit: AinkradBadge(text: "◐ at limit", status: .warning)
        case .flaky: AinkradBadge(text: "● flaky", status: .danger)
        case .unhealthy: AinkradBadge(text: "● unhealthy", status: .danger)
        case .disabled: AinkradBadge(text: "○ disabled")
        }
    }

    /// "Ainkrad 82%" per company it is assigned to.
    private var companies: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(account.companyIDs, id: \.self) { id in
                let name = store.companies.first { $0.id == id }?.name ?? "Company \(id)"
                AinkradChip(label: account.share(of: id).map { "\(name) \($0)%" } ?? name)
            }
        }
    }

    /// "2 runs now · 0 drops / 10 min · config ~/.citadel/acct/claude-personal".
    private var meta: String {
        let runs = model.liveRuns.filter { $0.accountID == account.id }.count
        let window = page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
        var parts = ["\(runs) run\(runs == 1 ? "" : "s") now", "\(account.drops) drops / \(window)"]
        if !account.configDir.isEmpty { parts.append("config \(account.configDir)") }
        return parts.joined(separator: " · ")
    }

    private var windows: some View {
        let warn = page.warnPercent(account.id)
        let bars = account.windows(warnPercent: warn)
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            if bars.isEmpty {
                Text(account.isSubscription ? "No window reported yet" : "billed per token · no limit set")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            ForEach(bars) { bar in
                HStack(spacing: skin.size.s10) {
                    Text(bar.label).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                        .lineLimit(1).frame(width: skin.size.s50, alignment: .leading)
                    AinkradBudgetBar(
                        label: "\(account.label) · \(bar.label)", value: bar.fraction, limit: 1,
                        warnFraction: bar.warnFraction, showsHardLimit: false, tone: bar.tone)
                    Text(
                        [["\(bar.percent)%"], [bar.resetText(now: Date())].compactMap { $0 }].joined().joined(
                            separator: " · ")
                    )
                    .citadelFont("t11", mono: true)
                    .foregroundStyle(bar.isPastWarn ? status.warning : skin.color(skin.text.muted))
                    .lineLimit(1).fixedSize()
                }
            }
            if !bars.isEmpty { source(bars, warn: warn) }
        }
    }

    /// "limits from harness signal · warn 80% ↳ server" / "limit configured · 5 h ≤ 3.0M tok".
    private func source(_ bars: [UsageWindow], warn: Int) -> some View {
        let counted = bars.compactMap(\.limit)
        let text =
            counted.isEmpty
            ? "harness signal" : "configured · \(counted.map(\.text).joined(separator: " · "))"
        let setting = page.settings[account.id]?["account.warn_percent"]
        let overridden = setting?.isSet(at: "account:\(account.id)") ?? false
        return HStack(spacing: skin.size.s6) {
            Text(text).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            Text(overridden ? "warn \(warn)% ● account" : "warn \(warn)% ↳ \(setting?.sourceKind ?? "server")")
                .foregroundStyle(overridden ? theme.accentSecondary : skin.color(skin.text.faint))
                .lineLimit(1).fixedSize()
        }
        .citadelFont("t10_5", mono: true)
        .padding(.leading, skin.size.s60)
    }

    /// Why it is skipped (amber) or flaky / unhealthy (red).
    private var reason: ReasonBlock? {
        switch account.health {
        case .atLimit:
            let until = account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            let others = page.accounts.filter {
                $0.id != account.id && $0.harness == account.harness && $0.health == .healthy
            }
            let moved = others.isEmpty ? "" : " New runs go to \(others.map(\.label).joined(separator: " and "))."
            return ReasonBlock(
                title: "Skipped\(until).",
                detail: (account.statusReason.map { "\($0.capitalizedFirst)." } ?? "") + moved,
                tone: .warning)
        case .flaky:
            let threshold = page.settings[account.id]?["account.drop_threshold"]?.value ?? 3
            let left = max(1, threshold - account.drops)
            let window = page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
            return ReasonBlock(
                title: "\(account.drops) provider drop\(account.drops == 1 ? "" : "s") in \(window).",
                detail:
                    "Each run resumed its session with backoff; \(left) more in the window marks it unhealthy and stops new work.",
                tone: .danger)
        case .unhealthy:
            return ReasonBlock(
                title: "Unhealthy.", detail: account.statusReason.map { "\($0.capitalizedFirst)." } ?? "", tone: .danger
            )
        default: return nil
        }
    }
}

/// The Limits tile for the picked account (decision #56: windows and caps per account, pool-wide): its counted
/// windows, the warn line and how many drops make it unhealthy, each with where it comes from.
struct AccountLimitsTile: View {
    let store: CitadelStore
    let model: CompanyModel
    let accounts: [PoolAccount]
    @State private var addingWindow = false
    @Environment(\.ainkradSkin) private var skin

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        let picked = accounts.first { $0.id == page.pickedAccount } ?? accounts[0]
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s8) {
                    TileHead(title: "Limits")
                    Text("server → account · most specific wins").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint)).fixedSize()
                    Spacer(minLength: skin.size.s8)
                    AinkradSelect(
                        items: accounts.map(\.id),
                        selection: Binding(get: { picked.id }, set: { page.pickedAccount = $0 }),
                        label: { id in accounts.first { $0.id == id }?.label ?? "Account" }
                    )
                    .fixedSize()
                }
                HStack(alignment: .top, spacing: skin.size.s20) {
                    windows(picked).frame(maxWidth: .infinity)
                    settings(picked).frame(maxWidth: .infinity)
                }
                Text("Account values are pool-wide (the account is shared). ↺ resets to inherited.")
                    .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    private func windows(_ account: PoolAccount) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            ForEach(Array(account.limits.enumerated()), id: \.offset) { index, limit in
                AinkradScopedValue(
                    label: "Window \(index + 1)",
                    value: Binding(
                        get: { limit.text },
                        set: { store.setAccountWindow(account.id, replacing: limit, text: $0) }),
                    scope: .overridden(at: "account", inheritedValue: nil),
                    validate: { AccountLimitInfo.parse($0) != nil },
                    onReset: { store.clearAccountWindow(account.id, limit) })
            }
            ForEach(account.signalWindows, id: \.name) { window in
                AinkradScopedValue(
                    label: window.label,
                    value: Binding(
                        get: { "\(window.label) ≤ signal" },
                        set: { store.setAccountWindow(account.id, replacing: nil, text: $0) }),
                    scope: .inherited(from: "provider"), validate: { AccountLimitInfo.parse($0) != nil })
            }
            if addingWindow {
                AinkradScopedValue(
                    label: "New window", bounds: "e.g. 5 h ≤ 3M tok",
                    value: Binding(
                        get: { "" },
                        set: {
                            store.setAccountWindow(account.id, replacing: nil, text: $0)
                            addingWindow = false
                        }),
                    scope: .overridden(at: "account", inheritedValue: nil),
                    validate: { AccountLimitInfo.parse($0) != nil })
            }
            AinkradButton(title: "+ Add window", style: .ghost) { addingWindow = true }
                .borderless().secondaryAccent().compact().fixedSize()
        }
    }

    @ViewBuilder private func settings(_ account: PoolAccount) -> some View {
        let window = page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
        let rows: [(String, String, (ScopedSetting) -> String)] = [
            ("account.warn_percent", "Warn at", { "\($0.bounds) of a window" }),
            ("account.drop_threshold", "Unhealthy at", { "\($0.bounds) drops in \(window)" }),
            ("account.unhealthy_secs", "Unhealthy for", { $0.bounds }),
        ]
        VStack(alignment: .leading, spacing: skin.size.s6) {
            ForEach(rows, id: \.0) { key, title, suffix in
                if let setting = page.settings[account.id]?[key] {
                    let scope = "account:\(account.id)"
                    AinkradScopedValue(
                        label: title, bounds: suffix(setting),
                        value: Binding(
                            get: { setting.text },
                            set: { store.setAccountSetting(account.id, key: key, text: $0) }),
                        scope: setting.chip(at: scope, inherited: page.serverSettings[key]),
                        validate: setting.accepts,
                        onReset: setting.isSet(at: scope) ? { store.resetAccountSetting(account.id, key: key) } : nil)
                }
            }
        }
    }
}

extension String {
    /// "the harness reports…" → "The harness reports…".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
