import AinkradAppKit
import SwiftUI

/// Screen 02 (prototype `home.js`): the hero, the account strip, then a two-column bento — what needs you beside
/// the account limits with the live runs under them, and requirements, team, recent activity and spend on the
/// right. Everything is pushed by the event stream.
struct HomeView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @State private var confirmsPause = false
    @State private var dismissedStrip: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                HomeHero(store: store, model: model) { confirmsPause = true }
                if let alert = accountAlert, alert.plain != dismissedStrip {
                    AccountStrip(text: alert.text, open: { store.screen = .accounts }) {
                        withAnimation(skin.animation(skin.motion.dismiss)) { dismissedStrip = alert.plain }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                HStack(alignment: .top, spacing: skin.size.s14) {
                    VStack(alignment: .leading, spacing: skin.size.s14) {
                        HStack(alignment: .top, spacing: skin.size.s14) {
                            NeedsYouTile(store: store, model: model, limit: max(4, accountRows))
                            HomeAccountsTile(store: store, model: model)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        LiveRunsSection(store: store, model: model)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: skin.size.s14) {
                        RequirementsTile(store: store, model: model)
                        TeamTile(store: store, model: model)
                        ActivityTile(store: store, model: model)
                        SpendTile(store: store, model: model)
                    }
                    .frame(width: skin.size.s340)
                }
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s20)
        }
        .scrollIndicators(.never)
        .offlineDimmed()
        .ainkradConfirmDialog(
            isPresented: $confirmsPause, title: "Pause every run?",
            message:
                "Every agent finishes its current tool call, then parks; new wakes queue until you resume. Nothing is killed.",
            confirmTitle: "Pause all"
        ) { store.setCompanyPaused(true) }
    }

    private var accountRows: Int { model.accounts.count }

    /// "**claude-work** is at its 5 h limit until 13:05 — skipped, runs move on. **codex-pro** at 86% of its 5 h window."
    private var accountAlert: (text: Text, plain: String)? {
        var text = Text("")
        var plain = ""
        for account in model.accounts.values.sorted(by: { $0.id < $1.id }) {
            let window = account.windowSecs.map { " \($0 / 3600) h" } ?? ""
            var rest: String?
            if account.status == "limited" {
                let until = account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                rest = " is at its\(window) limit\(until) — skipped, runs move to the next account. "
            } else if let use = account.windowUse, use * 100 >= Double(account.warnPercent ?? 80) {
                rest = " at \(Int(use * 100))% of its\(window) window. "
            }
            guard let rest else { continue }
            text = text + Text(account.label).bold().foregroundStyle(skin.color(skin.text.primary)) + Text(rest)
            plain += account.label + rest
        }
        return plain.isEmpty ? nil : (text, plain)
    }
}

/// The amber account strip: key glyph, the accounts at or near a limit, Accounts, dismiss until it changes.
private struct AccountStrip: View {
    let text: Text
    let open: () -> Void
    let dismiss: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let amber = skin.color(skin.palette.warning)
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        HStack(spacing: skin.size.s12) {
            KindTile(glyph: "⚿", tint: amber)
            text.citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            AinkradDockButton("Accounts", action: open)
            AinkradTapArea(action: dismiss) {
                Image(systemName: "xmark").citadelFont("t11", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.faint)).frame(width: skin.size.s26, height: skin.size.s26)
            }
            .buttonStyle(.plain)
            .help("Dismiss until it changes")
        }
        .padding(.vertical, skin.size.s10)
        .padding(.horizontal, skin.size.s14)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [amber.opacity(skin.opacity.o12), amber.opacity(skin.opacity.o03)], startPoint: .leading,
                    endPoint: .trailing))
        )
        .overlay(shape.strokeBorder(amber.opacity(skin.opacity.o25), lineWidth: 1))
    }
}

/// "What needs you now": each row with its one obvious action inline; the row opens the detail.
struct NeedsYouTile: View {
    let store: CitadelStore
    let model: CompanyModel
    let limit: Int
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let items = model.needsItems()
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                SectionHead(
                    title: "What needs you now", count: items.isEmpty ? nil : "\(items.count)", link: "Open inbox →"
                ) {
                    store.screen = .approvals
                }
                if items.isEmpty {
                    zero
                } else {
                    VStack(alignment: .leading, spacing: skin.size.s2) {
                        ForEach(items.prefix(limit)) { item in
                            NeedsRow(item: item, tint: tint(item.tone)) { perform(item.action, open: $0) }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var zero: some View {
        VStack(spacing: skin.size.s8) {
            Image(systemName: "checkmark").citadelFont("t18", weight: "bold").foregroundStyle(status.success)
                .frame(width: skin.size.s40, height: skin.size.s40)
                .background(status.success.opacity(skin.opacity.o16), in: Circle())
            Text("Nothing waits on you").citadelFont("t13", weight: "semibold").foregroundStyle(
                skin.color(skin.text.primary))
            if let last = model.answeredApprovals.first {
                Text("Last decision: \(model.summary(last).title)").citadelFont("t11").foregroundStyle(
                    skin.color(skin.text.faint)
                )
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s24)
    }

    private func perform(_ action: NeedsItem.Action, open: Bool) {
        switch action {
        case .approve(let approval, _):
            if open {
                store.selectedApproval = approval.id
                store.screen = .approvals
            } else {
                store.decide(approval, approve: true)
                store.toast(AinkradRichToast(title: "Approved", body: model.summary(approval).title, status: .success))
            }
        case .openRun(let run): store.open(.run(run))
        case .openScreen(let screen, _): store.screen = screen
        case .review(let id):
            store.selectedApproval = id
            store.screen = .approvals
        }
    }

    private func tint(_ tone: NeedsItem.Tone) -> Color {
        switch tone {
        case .accent: skin.color(skin.palette.accentPrimary)
        case .warning: status.warning
        case .danger: status.danger
        }
    }
}

private struct NeedsRow: View {
    let item: NeedsItem
    let tint: Color
    let perform: (_ open: Bool) -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            KindTile(glyph: item.glyph, tint: tint)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(item.title).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            button.frame(width: skin.size.s104)
        }
        .padding(.vertical, skin.size.s8)
        .padding(.horizontal, skin.size.s10)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
                .fill(skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)))
        )
        .offset(x: hovering ? skin.size.s2 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .onTapGesture { perform(true) }
    }

    @ViewBuilder private var button: some View {
        let height = skin.size.s30
        switch item.action {
        case .approve(_, let title):
            AinkradDockButton(title, tone: .primary, height: height, fillsWidth: true) { perform(false) }
        case .openScreen(_, let title):
            AinkradDockButton(title, height: height, fillsWidth: true) { perform(false) }
        case .openRun:
            AinkradDockButton("Open run", height: height, fillsWidth: true) { perform(false) }
        case .review:
            AinkradDockButton("Review", height: height, fillsWidth: true) { perform(false) }
        }
    }
}

/// "Account limits": each account this company uses, its tightest window as a bar with the warn mark, or its
/// health word.
private struct HomeAccountsTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let accounts = model.accounts.values.sorted { $0.id < $1.id }
        let hot = accounts.filter(isHot).count
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                SectionHead(
                    title: "Account limits",
                    count: hot > 0 ? "\(hot) need a look" : accounts.isEmpty ? nil : "\(accounts.count)",
                    link: "Accounts →"
                ) { store.screen = .accounts }
                if accounts.isEmpty {
                    Text("No accounts assigned to this company yet.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint)).padding(.vertical, skin.size.s10)
                }
                ForEach(accounts) { account in row(account) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func isHot(_ account: AccountInfo) -> Bool {
        account.status != "active" || (account.windowUse ?? 0) * 100 >= Double(account.warnPercent ?? 80)
    }

    private func row(_ account: AccountInfo) -> some View {
        let use = account.windowUse ?? 0
        let warn = Double(account.warnPercent ?? 80) / 100
        let amber = status.warning
        return HStack(spacing: skin.size.s10) {
            HarnessTag(harness: account.label)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(account.label).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                health(account).citadelFont("t11").lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: skin.size.s3) {
                AinkradBudgetBar(
                    label: account.label, value: use, limit: 1, warnFraction: warn, showsHardLimit: false,
                    tone: use >= warn ? .warning : nil
                )
                .frame(width: skin.size.s96)
                Text(account.windowUse == nil ? "no cap" : "\(Int(use * 100))%").citadelFont("t10", mono: true)
                    .foregroundStyle(use >= warn ? amber : skin.color(skin.text.faint))
            }
        }
        .padding(.vertical, skin.size.s6)
        .padding(.horizontal, skin.size.s4)
        .contentShape(Rectangle())
        .onTapGesture { store.screen = .accounts }
    }

    private func health(_ account: AccountInfo) -> Text {
        switch account.status {
        case "limited":
            let until = account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return Text("◐ at limit\(until)").foregroundStyle(status.warning)
        case "unhealthy": return Text("● flaky").foregroundStyle(status.danger)
        case "disabled": return Text("paused").foregroundStyle(skin.color(skin.text.faint))
        default:
            let window = account.windowSecs.map { "\($0 / 3600) h window" } ?? "no window"
            return Text("\(window) · \(account.billing == "subscription" ? "subscription" : "API")")
                .foregroundStyle(skin.color(skin.text.faint))
        }
    }
}
