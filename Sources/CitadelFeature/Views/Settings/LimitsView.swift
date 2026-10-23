import AinkradAppKit
import SwiftUI

/// Screen 16: every limit as a setting (decision #52) — its bounds, the server default (read-only here, #58), this
/// company's value and where it comes from, and every value set below (projects, runners, accounts). Runner and
/// account limits are server-wide / pool-wide, so the company column says so instead of offering a field (#56,
/// #57). Out-of-bounds input is refused inline, never clamped. Recent changes and the CLI under the table.
struct LimitsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: LimitsPage { model.limitsPage }
    private var companyScope: String { "company:\(model.companyID)" }

    var body: some View {
        @Bindable var page = page
        let sections = page.sections(model.companyID)
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Limits · \(store.company?.name ?? "Company")", crumb: crumb) {
                AinkradSearchField(text: $page.search, placeholder: "Find a setting").frame(width: skin.size.s200)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) {
                    chain
                    filters
                    AinkradCard {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            ForEach(sections.groups, id: \.0) { title, rows in
                                Text(skin.labelCased(title)).citadelFont("t10", weight: "semibold")
                                    .foregroundStyle(skin.color(skin.text.muted))
                                    .padding(.top, skin.size.s10).padding(.bottom, skin.size.s2)
                                    .padding(.horizontal, skin.size.s10)
                                ForEach(rows) { LimitTableRow(store: store, model: model, row: $0) }
                            }
                            more(sections.more)
                        }
                        .animation(
                            reduceMotion ? nil : skin.animation(skin.motion.present),
                            value: sections.groups.flatMap { $0.1.map(\.id) })
                    }
                    HStack(alignment: .top, spacing: skin.size.s12) {
                        changes.frame(maxWidth: .infinity)
                        cli.frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
            }
            .offlineDimmed()
        }
        .task { if !page.isLoaded { store.loadLimitsPage() } }
    }

    /// "22 settings · 6 set for this company · 9 overridden below".
    private var crumb: Text {
        let muted = skin.color(skin.text.muted)
        return Text("\(page.server.count) settings · ").foregroundStyle(muted)
            + Text("\(page.setHere(model.companyID)) set for this company").foregroundStyle(theme.accentSecondary)
            + Text(" · \(page.overriddenBelow) overridden below").foregroundStyle(muted)
    }

    /// "Resolution · most specific wins  Server default → Company → Project / Runner / Account", and the filters.
    private var chain: some View {
        HStack(spacing: skin.size.s6) {
            Text("Resolution · most specific wins").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            step("Server default")
            arrow("→")
            step("Company", isHere: true)
            arrow("→")
            step("Project")
            arrow("/")
            step("Runner")
            arrow("/")
            step("Account")
        }
    }

    private var filters: some View {
        HStack(spacing: skin.size.s6) {
            filter(.all, "All")
            filter(.setHere, "Set here · \(page.setHere(model.companyID))")
            filter(.overridden, "Overridden below · \(page.overriddenBelow)")
        }
    }

    private func step(_ title: String, isHere: Bool = false) -> some View {
        Text(title).citadelFont("t11")
            .foregroundStyle(isHere ? theme.accentSecondary : skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s3)
            .background(
                (isHere
                    ? theme.accentSecondary.opacity(skin.opacity.o12)
                    : skin.color(skin.palette.white).opacity(skin.opacity.o05)),
                in: RoundedRectangle(cornerRadius: skin.size.s6))
    }

    private func arrow(_ glyph: String) -> some View {
        Text(glyph).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
    }

    private func filter(_ value: LimitsPage.Filter, _ title: String) -> some View {
        AinkradToggleButton(
            isOn: Binding(get: { page.filter == value }, set: { if $0 { page.filter = value } }), title: title)
    }

    private var header: some View {
        HStack(spacing: skin.size.s12) {
            Text("Setting · bounds").frame(width: skin.size.s120, alignment: .leading)
            Text("\(store.company?.name ?? "Company") (this company)").frame(maxWidth: .infinity, alignment: .leading)
            Text("Server").frame(width: skin.size.s80, alignment: .leading)
            Text("Overridden below").frame(width: skin.size.s240, alignment: .leading)
        }
        .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
        .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s6)
    }

    /// "+ 7 more" — the rest, opened in place.
    @ViewBuilder private func more(_ rest: [LimitRow]) -> some View {
        if page.showsMore || !rest.isEmpty {
            if page.showsMore {
                ForEach(rest) { LimitTableRow(store: store, model: model, row: $0) }
            }
            HStack(spacing: skin.size.s12) {
                AinkradButton(title: page.showsMore ? "Fewer" : "+ \(rest.count) more", style: .ghost) {
                    page.showsMore.toggle()
                }
                .borderless().compact().fixedSize()
                if !page.showsMore {
                    Text(rest.prefix(4).map { $0.name.lowercased() }.joined(separator: ", ") + "…")
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
                }
            }
            .padding(.horizontal, skin.size.s4).padding(.vertical, skin.size.s6)
        }
    }

    // MARK: - Under the table

    private var changes: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "Recent changes", action: "Audit log →") { page.section = .audit }
                ForEach(page.changes, id: \.seq) { change in
                    VStack(alignment: .leading, spacing: skin.size.s2) {
                        changeLine(change).citadelFont("t11").lineLimit(2)
                        Text(change.at.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s8)
                    .background(
                        skin.color(skin.palette.white).opacity(skin.opacity.o05),
                        in: RoundedRectangle(cornerRadius: skin.size.s8))
                }
                if page.changes.isEmpty {
                    Text("Nothing changed yet.").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "**You** · stall timeout · CIT 15 min → **10 min**".
    private func changeLine(_ change: SettingChangeInfo) -> Text {
        let who = model.agent(change.agentID).map { "\($0.name) (\($0.role))" } ?? "You"
        let unit = page.server.first { $0.key == change.key }?.unit ?? "count"
        let old = change.old.map { ScopedSetting.format($0, unit: unit) } ?? "inherited"
        let new = change.new.map { ScopedSetting.format($0, unit: unit) } ?? "inherited"
        let primary = skin.color(skin.text.primary)
        return Text(who).bold().foregroundStyle(primary)
            + Text(" · \(LimitNames.name(change.key).lowercased()) · ").foregroundStyle(primary)
            + Text(scopeName(change.scope)).foregroundStyle(theme.accentSecondary)
            + Text(" \(old) → ").foregroundStyle(primary) + Text(new).bold().foregroundStyle(primary)
    }

    private func scopeName(_ scope: String) -> String {
        let parts = scope.split(separator: ":")
        guard parts.count == 2, let id = Int64(parts[1]) else { return scope }
        switch parts[0] {
        case "project": return model.projects.first { $0.id == id }?.key ?? scope
        case "runner": return model.runners[id] ?? scope
        case "account": return model.accounts[id]?.label ?? scope
        default: return "company"
        }
    }

    /// The same, from the server's CLI (`citadel-server setting …`), for the first value set here.
    private var cli: some View {
        let key = page.company.first { $0.isSet(at: companyScope) }?.key ?? "run.stall_after_secs"
        let commands = [
            "k=\(key) s=\(companyScope)",
            "c=\"citadel-server setting\"",
            "$c get $db $k --scope $s",
            "$c set $db $k <value> --scope $s",
            "$c reset $db $k --scope $s",
            "$c history $db $k",
        ]
        return AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "Same from the CLI · API")
                AinkradCodeBlock(commands.joined(separator: "\n"))
                Text(
                    "Every set / reset is audited (who, when, old → new) and validated against the bounds — out-of-range values are refused, never clamped."
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize(
                    horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One setting: name and bounds with this company's value and its chip (or why there is none), the server value,
/// and the values set below as chips that open their screen.
private struct LimitTableRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let row: LimitRow
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let page = model.limitsPage
        let scope = "company:\(model.companyID)"
        let refused = page.refused[row.id]
        HStack(spacing: skin.size.s12) {
            if let company = row.company {
                AinkradScopedValue(
                    label: row.name, bounds: row.setting.bounds,
                    value: Binding(get: { company.text }, set: { store.setLimit(company, scope: scope, text: $0) }),
                    suffix: refused,
                    scope: company.chip(at: scope),
                    validate: { page.check(company, $0) },
                    onReset: company.isSet(at: scope) ? { store.resetLimit(company, scope: scope) } : nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(row.name).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                    Text(row.setting.bounds).citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
                }
                .frame(width: skin.size.s120, alignment: .leading)
                Text(row.companyNote ?? "").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(row.setting.text).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s80, alignment: .leading)
                .help("The server default — edited on the server settings page")
            overrides.frame(width: skin.size.s240, alignment: .leading)
        }
        .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s6)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous).fill(
                refused != nil
                    ? status.danger.opacity(skin.opacity.o07)
                    : skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .animation(skin.animation(skin.motion.hover), value: refused)
    }

    @ViewBuilder private var overrides: some View {
        if row.overrides.isEmpty {
            Text("—").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else {
            HStack(spacing: skin.size.s6) {
                ForEach(row.overrides, id: \.scope) { item in
                    OverrideChip(item: item) { store.openOverride(item) }
                }
            }
        }
    }
}

/// "CIT **10 min**": a value set below the company; opens its screen.
private struct OverrideChip: View {
    let item: LimitOverride
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        (Text(item.owner).foregroundStyle(skin.color(skin.text.muted)) + Text(" ")
            + Text(item.value).bold().foregroundStyle(skin.color(skin.text.primary)))
            .citadelFont("t10_5", mono: true).lineLimit(1)
            .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s1)
            .background(
                theme.accentSecondary.opacity(hovering ? skin.opacity.o16 : skin.opacity.o08),
                in: skin.usesNativeGlass
                    ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: skin.size.s4))
            )
            .fixedSize()
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: open)
            .help("Open \(item.owner)")
            .accessibilityAddTraits(.isButton)
    }
}
