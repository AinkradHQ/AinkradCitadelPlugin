import AinkradAppKit
import AppKit
import SwiftUI

/// The account drawers' hero: solid harness tag, id, plan line, health pill.
struct AccountHero: View {
    let account: PoolAccount
    let health: PoolAccount.Health
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        OpsDrawerHero(
            tint: AgentLook.harness(account.harness)?.color ?? skin.color(skin.palette.accentPrimary),
            title: account.label,
            subtitle: "\(AgentLook.harnessName(account.harness)) · "
                + (account.isSubscription
                    ? "subscription" + (account.planTier.map { " · \($0)" } ?? "") : "API key · priced")
        ) {
            SolidHarnessTag(harness: account.harness, size: skin.size.s52)
        } trailing: {
            HealthPill(health: health)
        }
    }
}

/// Accounts › <id> · limits (`acctLimits`): window rings with their caps, the warn slider over a preview of the first
/// window, the drop stepper, and what new runs do at the limit.
struct AccountLimitsDrawer: View {
    let store: CitadelStore
    let page: AccountsPage
    let account: PoolAccount
    let close: () -> Void
    @State private var warn: Double = 80
    @State private var addingWindow = false
    @Environment(\.ainkradSkin) private var skin

    private var scope: String { "account:\(account.id)" }

    var body: some View {
        let bars = account.windows(warnPercent: page.warnPercent(account.id))
        OpsDrawerPanel(crumb: ["Accounts", "\(account.label) · limits"], close: close) {
            AccountHero(account: account, health: page.health(of: account))
            OpsSection(title: "Usage windows", hint: "click a cap to override") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: skin.size.s10) {
                    ForEach(bars) { bar in window(bar) }
                }
                if addingWindow {
                    HStack(spacing: skin.size.s6) {
                        Text("new window").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        InlineValuePill(text: "5 h ≤ 3M tok") { text in
                            addingWindow = false
                            commitWindow(text, replacing: nil)
                        }
                    }
                } else {
                    AinkradTapArea(action: { addingWindow = true }) {
                        Text("＋ Add window").citadelFont("t11").foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                    }
                }
            }
            warnSection(bars.first)
            dropSection
            atLimitSection
            OpsHint(
                "server → company → account · the most specific wins. Account values are pool-wide. Every change is in the audit log."
            )
        }
        .onAppear { warn = Double(page.warnPercent(account.id)) }
    }

    private func window(_ bar: UsageWindow) -> some View {
        let tint = AgentLook.harness(account.harness)?.color ?? skin.color(skin.palette.accentPrimary)
        return HStack(spacing: skin.size.s12) {
            WindowRing(bar: bar, harness: tint, diameter: skin.size.s64, labelSize: "t13")
            VStack(alignment: .leading, spacing: skin.size.s3) {
                Text("\(bar.label) window").citadelFont("t13", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                Text(
                    bar.resetText(now: Date()).map { "resets \($0.replacingOccurrences(of: "↺ ", with: ""))" }
                        ?? "rolling"
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s4) {
                    Text("cap").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    InlineValuePill(text: bar.limit?.text ?? "\(bar.label) ≤ signal", help: "Edit the cap") {
                        commitWindow($0, replacing: bar.limit)
                    }
                    if let limit = bar.limit {
                        ScopeChip(text: "account", overridden: true) { store.clearAccountWindow(account.id, limit) }
                    } else {
                        ScopeChip(text: "provider")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(skin.size.s12)
        .background(
            skin.color(.palette("black", skin.opacity.o18)),
            in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous))
    }

    private func commitWindow(_ text: String, replacing limit: AccountLimitInfo?) {
        guard AccountLimitInfo.parse(text) != nil else {
            store.toast(
                AinkradRichToast(
                    title: "A window reads “5 h ≤ 3M tok”", body: "“\(text)” was refused", status: .danger))
            return
        }
        store.setAccountWindow(account.id, replacing: limit, text: text)
        store.toast(
            AinkradRichToast(
                title: "\(account.label) · window → \(text)", body: "Pool-wide · audited", status: .success))
    }

    private func warnSection(_ first: UsageWindow?) -> some View {
        let setting = page.settings[account.id]?["account.warn_percent"]
        let overridden = setting?.isSet(at: scope) ?? false
        let inherited = page.serverSettings["account.warn_percent"].map { "\($0.value)%" } ?? "80%"
        return OpsSection(title: "Warn at") {
            if overridden {
                HStack(spacing: skin.size.s4) {
                    Text("set on this account ·")
                    AinkradTapArea(action: { store.resetAccountSetting(account.id, key: "account.warn_percent") }) {
                        Text("reset to \(inherited)").foregroundStyle(skin.color(skin.palette.accentSecondary))
                    }
                }
            } else {
                Text("inherited from \(setting?.sourceKind ?? "server")")
            }
        } content: {
            HStack(spacing: skin.size.s14) {
                WarnSlider(value: $warn, bounds: 50...99) { done in
                    store.setAccountWarn(account, percent: Int(done), was: page.warnPercent(account.id))
                }
                Text("\(Int(warn))%").citadelFont("t18", weight: "bold", mono: true)
                    .foregroundStyle(skin.color(skin.palette.warning))
                    .frame(width: skin.size.s52, alignment: .trailing)
            }
            WarnPreview(fraction: first?.fraction ?? 0, marker: warn / 100)
            OpsHint(
                "The bar is the \(first?.label ?? "first") window now — past the marker, new runs prefer other accounts and you get a notification."
            )
        }
    }

    @ViewBuilder private var dropSection: some View {
        if let setting = page.settings[account.id]?["account.drop_threshold"] {
            let window = page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
            OpsSection(title: "Unhealthy after", hint: "drops per \(window) · \(setting.sourceKind)") {
                HStack(spacing: skin.size.s10) {
                    stepButton("−") { step(setting, by: -1) }
                    Text("\(setting.value)").citadelFont("t20", weight: "bold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary)).frame(minWidth: skin.size.s32)
                    stepButton("＋") { step(setting, by: 1) }
                    Text("drops in \(window) → stop new work on it").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint))
                    Spacer(minLength: 0)
                    if setting.isSet(at: scope) {
                        ScopeChip(text: "account", overridden: true) {
                            store.resetAccountSetting(account.id, key: setting.key)
                        }
                    }
                }
            }
        }
    }

    private func step(_ setting: ScopedSetting, by delta: Int64) {
        let next = min(max(setting.value + delta, max(1, setting.min)), min(20, setting.max))
        guard next != setting.value else { return }
        store.setAccountSetting(account.id, key: setting.key, text: "\(next)")
    }

    private func stepButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        AinkradTapArea(action: action) {
            Text(glyph).citadelFont("t16").foregroundStyle(skin.color(skin.text.primary))
                .frame(width: skin.size.s34, height: skin.size.s34)
                .background(
                    skin.color(.palette("foreground", skin.opacity.o06)),
                    in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                )
                .ainkradHoverLift(0, cornerRadius: skin.size.s10)
        }
    }

    private var atLimitSection: some View {
        let setting = page.companySettings["account.at_limit"]
        let value = setting?.value ?? 0
        return OpsSection(title: "At the limit", hint: "what new runs do · company-wide") {
            OpsChoiceGrid(
                cards: [
                    OpsChoice(
                        id: Int64(-1), title: "Skip it",
                        detail: "New runs go to the next healthy account until the window resets",
                        systemImage: "arrow.right", isEnabled: false,
                        help: "The pool always skips a limited account first; a per-account choice needs the server"),
                    OpsChoice(
                        id: Int64(1), title: "Queue", detail: "Runs that need this account wait for the reset",
                        systemImage: "clock", isEnabled: setting != nil),
                    OpsChoice(
                        id: Int64(0), title: "Fall back", detail: "Use the agent's next chain entry right away",
                        systemImage: "arrow.counterclockwise", isEnabled: setting != nil),
                ], isOn: { $0 == value && setting != nil }, pick: { store.setAtLimit($0) })
        }
    }
}

/// The warn slider: an amber track painted under the pointer (never an invisible native control); the value
/// follows the drag and `commit` runs once, on release.
struct WarnSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let commit: (Double) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            let span = bounds.upperBound - bounds.lowerBound
            let x = geo.size.width * CGFloat((value - bounds.lowerBound) / span)
            let amber = skin.color(skin.palette.warning)
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o85))).frame(height: skin.size.s6)
                Capsule().fill(amber).frame(width: x, height: skin.size.s6)
                Circle().fill(skin.color(.palette("foreground", 1)))
                    .frame(width: skin.size.s18, height: skin.size.s18)
                    .shadow(color: skin.color(.palette("black", skin.opacity.o35)), radius: skin.size.s3)
                    .offset(x: x - skin.size.s9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max(drag.location.x / max(geo.size.width, 1), 0), 1)
                        value = (bounds.lowerBound + Double(fraction) * span).rounded()
                    }
                    .onEnded { _ in commit(value) })
        }
        .frame(height: skin.size.s22)
        .accessibilityElement()
        .accessibilityLabel("Warn at")
        .accessibilityValue("\(Int(value)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 1 : -1), bounds.lowerBound), bounds.upperBound)
            commit(value)
        }
    }
}

/// `.dl-prev`: the first window now (green → blue) with a glowing amber marker at the warn line.
private struct WarnPreview: View {
    let fraction: Double
    let marker: Double
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            let amber = skin.color(skin.palette.warning)
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o06)))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [skin.color(skin.palette.success), skin.color(skin.palette.accentPrimary)],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                RoundedRectangle(cornerRadius: skin.size.s2).fill(amber)
                    .frame(width: skin.size.s3, height: skin.size.s22)
                    .shadow(color: amber, radius: skin.size.s5)
                    .offset(x: geo.size.width * CGFloat(marker) - skin.size.s1_5)
                    .animation(skin.animation(skin.motion.hover), value: marker)
            }
        }
        .frame(height: skin.size.s12)
        .padding(.vertical, skin.size.s5)
    }
}

/// Accounts › Re-login <id> (`acctRelogin`): copy the command, run it on the runner, recheck every runner.
struct ReloginDrawer: View {
    let store: CitadelStore
    let page: AccountsPage
    let account: PoolAccount
    let close: () -> Void
    @State private var copied = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let logins = page.logins(of: account)
        let target = logins.first { $0.login.state == "logged_out" } ?? logins.first
        let allIn = !logins.isEmpty && logins.allSatisfy { $0.login.state != "logged_out" }
        OpsDrawerPanel(crumb: ["Accounts", "Re-login \(account.label)"], close: close) {
            AccountHero(account: account, health: page.health(of: account))
            if let target {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    step(1, "Copy the login command", done: copied) { command(target) }
                    step(2, "Run it on \(target.runner.name)", done: false) {
                        OpsHint(
                            "Credentials stay on the runner as the runner's user — Citadel never sees them. Finish the browser login it opens."
                        )
                    }
                    step(3, "Recheck every runner", done: allIn) { tiles(logins) }
                }
                .background(alignment: .topLeading) {
                    Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                        .frame(width: skin.size.s2)
                        .padding(.vertical, skin.size.s20)
                        .padding(.leading, skin.size.s15)
                }
            } else {
                OpsHint("No runner reports a login for \(account.label) yet — its runners list it on their next probe.")
            }
        } footer: {
            Spacer()
            AinkradDockButton("Later", action: close)
            AinkradDockButton(allIn ? "Done" : "I've logged in — recheck", tone: .primary) {
                if allIn { close() } else { store.recheckLogins(account) }
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> Content)
        -> some View
    {
        HStack(alignment: .top, spacing: skin.size.s12) {
            Text(done ? "✓" : "\(number)").citadelFont("t13", weight: "bold", mono: true)
                .foregroundStyle(skin.color(done ? .palette("background", 1) : .palette("foreground", 1)))
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background {
                    if done {
                        Circle().fill(skin.color(skin.palette.success))
                    } else {
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            VStack(alignment: .leading, spacing: skin.size.s8) {
                Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                content()
            }
            .padding(.top, skin.size.s5)
        }
    }

    private func command(_ target: (runner: RunnerInfo, login: RunnerLoginInfo)) -> some View {
        let line = "ssh \(target.runner.name) '\(target.login.command)'"
        return HStack(spacing: skin.size.s10) {
            Text(line).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            AinkradDockButton(copied ? "Copied ✓" : "Copy", systemImage: "doc.on.doc", height: skin.size.s28) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1_400))
                    copied = false
                }
            }
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .background(
            skin.color(.palette("black", skin.opacity.o35)),
            in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
    }

    private func tiles(_ logins: [(runner: RunnerInfo, login: RunnerLoginInfo)]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: skin.size.s8), count: 3), spacing: skin.size.s8
        ) {
            ForEach(logins, id: \.runner.id) { item in
                let state = item.login.state
                let tint =
                    state == "logged_in"
                    ? skin.color(skin.palette.success)
                    : state == "logged_out" ? skin.color(skin.palette.danger) : skin.color(skin.palette.accentPrimary)
                let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
                VStack(spacing: skin.size.s6) {
                    Image(systemName: "server.rack").citadelFont("t18").foregroundStyle(tint)
                    Text(item.runner.name).citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(state == "logged_in" ? "✓ logged in" : state == "logged_out" ? "✗ logged out" : "? unknown")
                        .citadelFont("t11").foregroundStyle(tint)
                }
                .padding(.vertical, skin.size.s12)
                .frame(maxWidth: .infinity)
                .background(shape.fill(tint.opacity(skin.opacity.o08)))
                .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o28), lineWidth: 1))
            }
        }
    }
}
