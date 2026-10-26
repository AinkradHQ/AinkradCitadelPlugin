import AinkradAppKit
import SwiftUI

/// Company settings › Limits (screen 16, prototype `settings-limits.js`): every limit as a setting (decision #52) —
/// how resolution works and the filters, then one card per group with a draggable gauge per row, this company's
/// value and where it comes from, and the values set below; recent changes and the CLI for the selected row under
/// them. Runner and account limits are server-wide / pool-wide (#56, #57): their gauge is read-only. Out-of-bounds
/// input is refused, never clamped.
struct LimitsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: LimitsPage { model.limitsPage }
    private var companyScope: String { "company:\(model.companyID)" }

    var body: some View {
        @Bindable var page = page
        let sections = page.sections(model.companyID, expandAll: true)
        let groups = sections.groups + (sections.more.isEmpty ? [] : [("Other", sections.more)])
        SettingsScroll {
            SettingsHero(
                section: .limits, title: "Limits · \(store.company?.name ?? "Company")",
                subtitle:
                    "\(page.server.count) settings · \(page.setHere(model.companyID)) set for this company · \(page.overriddenBelow) overridden below"
            ) {
                AinkradSearchField(text: $page.search, placeholder: "Find a setting").frame(width: skin.size.s220)
            }
            resolution
            ForEach(Array(groups.enumerated()), id: \.element.0) { index, group in
                let (title, rows) = group
                SettingsCard(delay: 0.06 * Double(index)) {
                    HStack(spacing: skin.size.s8) {
                        SectionGlyph(
                            icon: Self.groupIcon(title), tint: Self.groupTint(title, skin), size: skin.size.s24)
                        Text(title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    }
                    .padding(.top, skin.size.s10)
                    .padding(.bottom, skin.size.s6)
                    VStack(spacing: skin.size.s1) {
                        ForEach(rows) { row in
                            LimitRowView(store: store, model: model, row: row, tint: Self.groupTint(title, skin))
                        }
                    }
                    .padding(.bottom, skin.size.s4)
                }
            }
            if groups.isEmpty {
                SettingsCard {
                    Text("Nothing in this filter").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                        .frame(maxWidth: .infinity).padding(skin.size.s18)
                }
            }
            HStack(alignment: .top, spacing: skin.size.s14) {
                changes.frame(maxWidth: .infinity)
                cli.frame(maxWidth: .infinity)
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: groups.flatMap { $0.1.map(\.id) })
        .task { if !page.isLoaded { store.loadLimitsPage() } }
    }

    static func groupTint(_ title: String, _ skin: AinkradSkin) -> Color {
        switch title {
        case "Runs": skin.color(skin.palette.accentPrimary)
        case "Disk & storage": skin.color(skin.palette.accentViolet)
        case "Cost & usage": skin.color(skin.palette.success)
        case "Approvals & knowledge": skin.color(skin.palette.warning)
        default: skin.color(skin.text.muted)
        }
    }

    static func groupIcon(_ title: String) -> String {
        switch title {
        case "Runs": "play.fill"
        case "Disk & storage": "cylinder"
        case "Cost & usage": "dollarsign"
        case "Approvals & knowledge": "checkmark"
        default: "slider.horizontal.3"
        }
    }

    // MARK: Resolution and filters

    private var resolution: some View {
        SettingsCard {
            HStack(spacing: skin.size.s10) {
                node("gearshape", "Server default", "everyone starts here", isHere: false)
                arrow
                node("square", store.company?.name ?? "Company", "this company", isHere: true)
                arrow
                node("list.bullet", "Project · runner · account", "most specific wins", isHere: false)
            }
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s10)
            HStack(spacing: skin.size.s8) {
                FilterChip(title: "All", isOn: page.filter == .all) { page.filter = .all }
                FilterChip(title: "Set here · \(page.setHere(model.companyID))", isOn: page.filter == .setHere) {
                    page.filter = .setHere
                }
                FilterChip(title: "Overridden below · \(page.overriddenBelow)", isOn: page.filter == .overridden) {
                    page.filter = .overridden
                }
            }
            .padding(.top, skin.size.s4)
            .padding(.bottom, skin.size.s12)
        }
    }

    private func node(_ icon: String, _ title: String, _ detail: String, isHere: Bool) -> some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        return HStack(spacing: skin.size.s10) {
            Image(systemName: icon).citadelFont("t13").foregroundStyle(cyan)
                .frame(width: skin.size.s30, height: skin.size.s30)
                .background(cyan.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s9))
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                Text(detail).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .frame(maxWidth: .infinity)
        .background(
            isHere ? cyan.opacity(skin.opacity.o08) : skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
            in: shape
        )
        .overlay(
            shape.strokeBorder(
                isHere ? cyan.opacity(skin.opacity.o40) : skin.color(.palette("foreground", skin.opacity.o06)),
                lineWidth: 1))
    }

    private var arrow: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        return HStack(spacing: 0) {
            LinearGradient(
                colors: [skin.color(.palette("foreground", skin.opacity.o08)), cyan.opacity(skin.opacity.o50)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: skin.size.s2)
            Image(systemName: "arrowtriangle.right.fill").citadelFont("t8").foregroundStyle(
                cyan.opacity(skin.opacity.o60))
        }
        .frame(maxWidth: skin.size.s60)
    }

    // MARK: Under the groups

    private var changes: some View {
        SettingsCard(title: "Recent changes") {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                ForEach(page.changes, id: \.seq) { change in changeRow(change) }
                if page.changes.isEmpty {
                    Text("Nothing changed yet.").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
                AinkradTapArea {
                    page.section = .audit
                } label: {
                    Text("Audit log ›").citadelFont("t11").foregroundStyle(skin.color(skin.palette.accentSecondary))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, skin.size.s10)
        }
    }

    /// "**You** · stall timeout · CIT ~~15 min~~ → **10 min**" over its time.
    private func changeRow(_ change: SettingChangeInfo) -> some View {
        let unit = page.server.first { $0.key == change.key }?.unit ?? "count"
        let old = change.old.map { ScopedSetting.format($0, unit: unit) } ?? "inherited"
        let new = change.new.map { ScopedSetting.format($0, unit: unit) } ?? "inherited"
        let who = model.agent(change.agentID).map(\.nameAndRole) ?? "You"
        return VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s6) {
                (Text(who).bold() + Text(" · \(LimitNames.name(change.key).lowercased()) · ")
                    + Text(scopeName(change.scope)).monospaced())
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                DiffChips(old: old, new: new)
            }
            Text(change.at.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s9)
        .background(
            skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
            in: RoundedRectangle(cornerRadius: skin.size.s12))
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

    /// The same, from the server's CLI (`citadel-server setting …`; no client `citadel setting` command yet), for the selected row.
    private var cli: some View {
        let key = page.selected ?? page.company.first { $0.isSet(at: companyScope) }?.key ?? "run.stall_after_secs"
        let value = page.company.first { $0.key == key }?.text.replacingOccurrences(of: " ", with: "") ?? "<value>"
        let below = page.below[key]?.first { $0.scope.hasPrefix("project:") }
        let lines = [
            "citadel-server setting get $DB \(key)\(below.map { " --scope \($0.scope)" } ?? "")",
            "citadel-server setting set $DB \(key) \(value) --scope \(companyScope)",
            "citadel-server setting reset $DB \(key) --scope \(companyScope)",
            "citadel-server setting history $DB \(key)",
        ]
        return SettingsCard(title: "On the server (citadel-server, needs the database)", hint: LimitNames.name(key)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) { line in
                    (Text(verbatim: "$ ").foregroundStyle(skin.color(skin.text.faint))
                        + Text(verbatim: line).foregroundStyle(skin.color(skin.palette.accentSecondary)))
                        .citadelFont("t11", mono: true).lineSpacing(skin.size.s6).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, skin.size.s14)
            .padding(.vertical, skin.size.s12)
            .background(
                skin.color(.palette("background", 1)).opacity(skin.opacity.o70),
                in: RoundedRectangle(cornerRadius: skin.size.s12))
            Text(
                "Every set / reset is audited and validated against the bounds — out-of-range values are refused, never clamped."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize(
                horizontal: false, vertical: true
            )
            .padding(.top, skin.size.s8).padding(.bottom, skin.size.s10)
        }
    }
}

/// ~~old~~ → **new** as red / green mono chips.
struct DiffChips: View {
    let old: String
    let new: String
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        HStack(spacing: skin.size.s6) {
            Text(old).citadelFont("t11", mono: true).foregroundStyle(status.danger)
                .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                .background(status.danger.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s6))
            Text(verbatim: "→").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            Text(new).citadelFont("t11", weight: "semibold", mono: true).foregroundStyle(status.success)
                .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                .background(status.success.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s6))
        }
        .fixedSize()
    }
}
