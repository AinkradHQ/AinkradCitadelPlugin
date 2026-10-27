import AinkradAppKit
import SwiftUI

/// One account (`.acx`): harness tag, id, plan, health pill; its windows as rings; the companies' shares; runs and
/// drops; why it is skipped / flaky / logged out; and Pause, Re-login, Limits.
struct AccountCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let account: PoolAccount
    var index = 0
    let open: (AccountDrawer) -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var editingPlan = false
    @State private var planDraft = ""
    @State private var confirmingRemove = false

    private var page: AccountsPage { model.accountsPage }
    private var health: PoolAccount.Health { page.health(of: account) }
    private var harnessTint: Color {
        AgentLook.harness(account.harness)?.color ?? skin.color(skin.palette.accentPrimary)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let state = health.tone.tint(skin)
        VStack(alignment: .leading, spacing: skin.size.s12) {
            head
            windows
            if account.companyTokens.values.contains(where: { $0 > 0 }) { share }
            meta
            if let why { why }
            if confirmingRemove { removeConfirm } else { actions }
        }
        .padding(skin.size.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [
                        harnessTint.opacity(skin.opacity.o10), skin.color(.palette("background", skin.opacity.o85)),
                    ],
                    startPoint: .top, endPoint: .center))
        )
        .overlay(alignment: .top) {
            LinearGradient(colors: [harnessTint, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: skin.size.s3)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(state.opacity(skin.opacity.o22), lineWidth: 1))
        .shadow(
            color: hovering ? skin.color(.palette("black", skin.opacity.o32)) : .clear, radius: skin.size.s20,
            y: skin.size.s16
        )
        .opacity(health == .disabled ? skin.opacity.o55 : 1)
        .offset(y: hovering && !reduceMotion ? -skin.size.s3 : 0)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
        .ainkradContextMenu([
            AinkradMenuItem(title: "Set plan tier…", systemName: "tag") {
                planDraft = account.planTier ?? ""
                editingPlan = true
            }
        ])
        .ainkradRiseIn(delay: 0.05 * Double(index))
        .ainkradPanelModal(isPresented: $editingPlan, contentWidth: skin.size.s440) { planForm }
    }

    /// Live runs on this account; the pool refuses to remove it while any use it.
    private var runCount: Int { model.liveRuns.filter { $0.accountID == account.id }.count }

    private var head: some View {
        HStack(spacing: skin.size.s10) {
            SolidHarnessTag(harness: account.harness, size: skin.size.s36)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(account.label).citadelFont("t13", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Text(planLine).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s6)
            HealthPill(health: health)
            // The prototype's trash: revealed on hover in the head, never a row button.
            if hovering && store.serverSupports(minor: CitadelStore.structureMinor) {
                AinkradIconButton(
                    systemName: "trash", size: skin.size.s26,
                    tooltip: runCount > 0 ? "Pause it first" : "Remove it from the pool"
                ) {
                    confirmingRemove = true
                }
                .disabled(runCount > 0)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    /// "Claude · subscription · Max 20×", "Claude · API key · priced".
    private var planLine: String {
        let kind =
            account.isSubscription ? "subscription" + (account.planTier.map { " · \($0)" } ?? "") : "API key · priced"
        return "\(AgentLook.harnessName(account.harness)) · \(kind)"
    }

    private var windows: some View {
        let warn = page.warnPercent(account.id)
        let bars = account.windows(warnPercent: warn)
        return HStack(spacing: skin.size.s14) {
            if bars.isEmpty {
                Text(account.isSubscription ? "No window reported yet" : "billed per token · no window")
                    .citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.muted))
                    .padding(.horizontal, skin.size.s12)
                    .padding(.vertical, skin.size.s8)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
            }
            ForEach(bars.prefix(2)) { bar in
                HStack(spacing: skin.size.s10) {
                    WindowRing(bar: bar, harness: harnessTint, diameter: skin.size.s50, labelSize: "t11")
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(bar.label).citadelFont("t12", weight: "semibold").foregroundStyle(
                            skin.color(skin.text.primary))
                        Text(
                            bar.resetText(now: Date())
                                ?? (bar.limit.map { "≤ \($0.text.split(separator: "≤").last ?? "")" } ?? "")
                        )
                        .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                }
            }
        }
    }

    private var share: some View {
        let ids = account.companyIDs.filter { (account.companyTokens[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: skin.size.s5) {
            AinkradShareBar(parts: ids.map { (Double(account.companyTokens[$0] ?? 0), companyColor($0)) })
            HStack(spacing: skin.size.s10) {
                ForEach(account.companyIDs, id: \.self) { id in
                    HStack(spacing: skin.size.s5) {
                        RoundedRectangle(cornerRadius: skin.size.s2).fill(companyColor(id))
                            .frame(width: skin.size.s8, height: skin.size.s8)
                        Text(store.companies.first { $0.id == id }?.name ?? "Company \(id)")
                        if let share = account.share(of: id), share > 0 {
                            Text("\(share)%").bold().foregroundStyle(skin.color(skin.text.primary))
                        }
                    }
                }
            }
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
        }
    }

    /// The company's swatch: a fixed palette by its place in the list (the server stores no company colour yet).
    private func companyColor(_ id: Int64) -> Color {
        let palette: [Color] = [
            skin.color(skin.palette.accentPrimary), skin.color(skin.palette.success),
            skin.color(skin.palette.accentViolet), skin.color(skin.palette.accentSecondary),
            skin.color(skin.palette.warning), skin.color(skin.palette.accentTertiary),
        ]
        let index = store.companies.firstIndex { $0.id == id } ?? Int(id)
        return palette[index % palette.count]
    }

    private var meta: some View {
        let runs = runCount
        let drops = account.recentDropsWindowSecs > 0 ? account.recentDrops : account.drops
        let window =
            account.recentDropsWindowSecs > 0
            ? ScopedSetting.format(account.recentDropsWindowSecs, unit: "seconds")
            : page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
        return HStack(spacing: skin.size.s10) {
            if runs > 0 { LiveDots(count: min(3, runs)) }
            Text("\(Wording.count(runs, "run")) now")
            Text("\(drops) drops / \(window.replacingOccurrences(of: "1 d", with: "24 h"))")
                .foregroundStyle(drops > 2 ? skin.color(skin.palette.danger) : skin.color(skin.text.faint))
        }
        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
    }

    /// Why it is skipped (amber), logged out somewhere (amber) or flaky / unhealthy (red).
    private var why: AnyView? {
        let primary = skin.color(skin.text.primary)
        let text: Text
        var link: (String, () -> Void)?
        switch health {
        case .atLimit:
            let until = account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            let others = page.visible(company: model.companyID).filter {
                $0.id != account.id && $0.harness == account.harness && page.health(of: $0) == .healthy
            }
            let moved = others.isEmpty ? "" : " New runs go to \(others.map(\.label).joined(separator: " and "))."
            text =
                Text("Skipped\(until).").bold().foregroundStyle(primary)
                + Text(moved + (account.statusReason.map { " \($0.capitalizedFirst)." } ?? ""))
        case .flaky:
            let threshold = page.settings[account.id]?["account.drop_threshold"]?.value ?? 3
            let window = page.settings[account.id]?["account.drop_window_secs"]?.text ?? "10 min"
            text =
                Text("\(Wording.count(account.drops, "provider drop")) in \(window).").bold().foregroundStyle(primary)
                + Text(
                    " Each run resumed its session with backoff; \(max(1, threshold - account.drops)) more in the window marks it unhealthy and stops new work."
                )
        case .partial:
            let names = page.loggedOutRunners(account).map(\.name).joined(separator: ", ")
            text =
                Text("Logged out on \(names)").bold().foregroundStyle(primary)
                + Text(
                    " · the runner's harness check failed (same as Runners). Runs that need \(AgentLook.harnessName(account.harness)) skip \(names) until you log in again there. "
                )
            link = ("Re-login on server…", { open(.relogin(account.id)) })
        case .unhealthy:
            text =
                Text("Unhealthy.").bold().foregroundStyle(primary)
                + Text(account.statusReason.map { " \($0.capitalizedFirst)." } ?? "")
        default: return nil
        }
        let tint = health.tone.tint(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        return AnyView(
            VStack(alignment: .leading, spacing: skin.size.s4) {
                text.citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    AinkradTapArea(action: link.1) {
                        Text(link.0).citadelFont("t12", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                    }
                }
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tint.opacity(skin.opacity.o08)))
            .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
        )
    }

    private var actions: some View {
        let height = skin.size.s30
        return AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
            if health == .disabled {
                AinkradDockButton("Resume", systemImage: "play.fill", tone: .primary, height: height) {
                    store.setAccountPaused(account, false)
                }
            } else {
                AinkradDockButton("Pause", systemImage: "pause", height: height) {
                    store.setAccountPaused(account, true)
                }
            }
            if account.isSubscription {
                AinkradDockButton(
                    "Re-login", systemImage: "key", tone: health == .partial ? .primary : .plain, height: height
                ) {
                    open(.relogin(account.id))
                }
            }
            AinkradDockButton("Limits", systemImage: "gauge.with.dots.needle.33percent", height: height) {
                open(.limits(account.id))
            }
        }
    }

    /// "Remove account", confirmed on the card in place of its actions: gone from the pool with its assignments and
    /// limits; the server refuses while runs used it, so the button stays off until they finish.
    private var removeConfirm: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text("Remove \(account.label)?").citadelFont("t13", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            Text("It leaves the pool with its company assignments and limits.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).fixedSize(
                    horizontal: false, vertical: true)
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { confirmingRemove = false }.fixedSize()
                AinkradButton(title: "Remove", style: .danger) {
                    store.removeAccount(account)
                    confirmingRemove = false
                }
                .fixedSize()
                .disabled(runCount > 0)
            }
        }
    }

    /// "Max 20x": what the account's plan is called; empty clears it.
    private var planForm: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Plan tier · \(account.label)").citadelFont("t15", weight: "semibold")
            AinkradFormRow(title: "Tier", help: "As the provider names it; empty clears it.") {
                AinkradTextField(text: $planDraft, placeholder: "Max 20x")
            }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { editingPlan = false }.fixedSize()
                AinkradButton(title: "Save") {
                    store.setPlanTier(account.id, planDraft)
                    editingPlan = false
                }
                .fixedSize()
                .disabled(planDraft.trimmingCharacters(in: .whitespaces).count > 64)
            }
        }
    }
}

/// A window as a ring: the harness colour, amber past the warn mark, red at the limit; its % in the middle.
struct WindowRing: View {
    let bar: UsageWindow
    let harness: Color
    let diameter: CGFloat
    let labelSize: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint =
            bar.isAtLimit
            ? skin.color(skin.palette.danger) : bar.isPastWarn ? skin.color(skin.palette.warning) : harness
        AinkradRingGauge(value: bar.fraction, tint: tint, diameter: diameter, lineWidth: diameter * 0.14) {
            Text("\(bar.percent)%").citadelFont(labelSize, weight: "semibold", mono: true)
                .foregroundStyle(skin.color(skin.text.primary))
        }
    }
}

/// `.ac-tag`: the harness's two letters on its solid colour, with a soft glow.
struct SolidHarnessTag: View {
    let harness: String
    let size: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = AgentLook.harness(harness)?.color ?? skin.color(skin.text.muted)
        Text(HarnessTag.letters(harness))
            .citadelFont(
                size >= skin.size.s44 ? "t18" : size > skin.size.s28 ? "t12" : "t10", weight: "bold", mono: true
            )
            .foregroundStyle(skin.color(.palette("background", 1)))
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: tint.opacity(skin.opacity.o30), radius: size * 0.2, y: size * 0.1)
    }
}

/// `.ac-hb`: the health pill — tinted fill, a glowing dot (pulsing when flaky), the word.
struct HealthPill: View {
    let health: PoolAccount.Health
    @Environment(\.ainkradSkin) private var skin
    @State private var pulse = false

    var body: some View {
        let tint = health.tone.tint(skin)
        HStack(spacing: skin.size.s6) {
            Circle().fill(tint).frame(width: skin.size.s6, height: skin.size.s6)
                .shadow(color: tint, radius: skin.size.s4)
                .opacity(health == .flaky && pulse ? skin.opacity.o30 : 1)
            Text(health.word).citadelFont("t11", weight: "semibold")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s9)
        .frame(height: skin.size.s24)
        .background(
            tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous)
        )
        .onAppear {
            guard health == .flaky else { return }
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeInOut", durationKey: "materialize")).repeatForever()
            ) {
                pulse = true
            }
        }
    }
}

/// Up to three pulsing cyan dots: runs on the account now.
struct LiveDots: View {
    let count: Int
    @Environment(\.ainkradSkin) private var skin
    @State private var pulse = false

    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        HStack(spacing: skin.size.s3) {
            ForEach(0..<count, id: \.self) { index in
                Circle().fill(cyan).frame(width: skin.size.s7, height: skin.size.s7)
                    .shadow(color: cyan, radius: skin.size.s3)
                    .opacity(pulse ? skin.opacity.o35 : 1)
                    .animation(
                        skin.animation(AinkradAnimationToken(curve: "easeInOut", durationKey: "materialize"))
                            .repeatForever()
                            .delay(Double(index) * 0.3),
                        value: pulse
                    )
            }
        }
        .onAppear { pulse = true }
    }
}

extension String {
    /// "the harness reports…" → "The harness reports…".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
