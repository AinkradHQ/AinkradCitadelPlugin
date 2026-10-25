import AinkradAppKit
import SwiftUI

/// Company settings › Audit log (`settings.js` Audit): who changed what, before → after, as a timeline. The type and
/// actor chips filter on the server (action prefix and `actor`, paged with Load more); an older server gets the actor
/// chips filtering the rows loaded so far. The search filters those rows. Click a row for its before → after.
struct AuditLogSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var open: Set<Int64> = []
    @Environment(\.ainkradSkin) private var skin

    private var page: LimitsPage { model.limitsPage }

    /// The type chips: the prototype's four, then the plugin's other action families.
    static let kinds: [(prefix: String, title: String)] = [
        ("", "All types"), ("setting.", "Settings"), ("approval.", "Approvals"), ("device.", "Keys"),
        ("account.", "Accounts"), ("issue.", "Issues"), ("agent.", "Agents"), ("project.", "Projects"),
        ("knowledge.", "Knowledge"),
    ]

    var body: some View {
        @Bindable var page = page
        let rows = shown
        SettingsScroll {
            SettingsHero(
                section: .audit,
                subtitle:
                    "\(page.auditLog?.count ?? 0)\(page.auditNext == nil ? "" : "+") entries · who, what, before → after, and how"
            ) {
                AinkradDockButton("Refresh", systemImage: "arrow.clockwise") { store.loadAuditLog() }
            }
            HStack(alignment: .top, spacing: skin.size.s8) {
                AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s8) {
                    ForEach([("all", "Everyone"), ("you", "You"), ("agents", "Agents"), ("system", "System")], id: \.0)
                    { id, title in
                        FilterChip(title: title, isOn: page.auditActor == id) {
                            page.auditActor = id
                            if store.serverSupports(minor: CitadelStore.structureMinor) { store.loadAuditLog() }
                        }
                    }
                    Color.clear.frame(width: skin.size.s2, height: skin.size.s2)
                    ForEach(Self.kinds, id: \.prefix) { kind in
                        FilterChip(title: kind.title, isOn: page.auditKind == kind.prefix) {
                            page.auditKind = kind.prefix
                            store.loadAuditLog()
                        }
                    }
                }
                AinkradSearchField(text: $page.auditSearch, placeholder: "Search the log").frame(width: skin.size.s220)
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    if rows.isEmpty {
                        Text(page.auditLog == nil ? "Loading…" : "Nothing matches these filters")
                            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                            .frame(maxWidth: .infinity).padding(skin.size.s20)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                        AuditRow(
                            line: line, model: model, you: store.userName, isOpen: open.contains(line.seq),
                            isLast: index == rows.count - 1
                        ) {
                            if open.contains(line.seq) { open.remove(line.seq) } else { open.insert(line.seq) }
                        }
                    }
                    if page.auditNext != nil {
                        AinkradDockButton("Load more", height: skin.size.s30) { store.loadMoreAudit() }
                            .padding(.top, skin.size.s6)
                    }
                }
                .padding(.vertical, skin.size.s8)
            }
        }
        .onAppear { store.loadAuditLog() }
    }

    /// The loaded rows the search leaves, and on an older server the actor chip too (the server filters it from 17).
    private var shown: [AuditLine] {
        let query = page.auditSearch.trimmingCharacters(in: .whitespaces)
        let filtersActors = !store.serverSupports(minor: CitadelStore.structureMinor)
        return (page.auditLog ?? []).filter { line in
            guard !filtersActors || actorShown(line) else { return false }
            guard !query.isEmpty else { return true }
            let text = ([line.action, line.actor, line.entity ?? ""] + line.details.values).joined(separator: " ")
            return text.localizedCaseInsensitiveContains(query)
        }
    }

    private func actorShown(_ line: AuditLine) -> Bool {
        switch page.auditActor {
        case "you": line.actor == "you"
        case "agents": line.actor.hasPrefix("agent:")
        case "system": line.actor != "you" && !line.actor.hasPrefix("agent:")
        default: true
        }
    }
}

/// One audited change: who (figure, avatar or a system disc) with its type badge, what and where, the time; open, the
/// before → after.
private struct AuditRow: View {
    let line: AuditLine
    let model: CompanyModel
    let you: String?
    let isOpen: Bool
    let isLast: Bool
    let toggle: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        AinkradTapArea(action: toggle) {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s12) {
                    who.frame(width: skin.size.s36, height: skin.size.s36)
                        .overlay(alignment: .bottomTrailing) { badge.offset(x: skin.size.s4, y: skin.size.s4) }
                    summary.citadelFont("t12_5").lineLimit(1)
                    Spacer(minLength: skin.size.s8)
                    Text(line.at.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                }
                if isOpen {
                    change.padding(.leading, skin.size.s48).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, skin.size.s8)
            .padding(.trailing, skin.size.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if !isLast {
                    Capsule().fill(skin.color(skin.text.muted).opacity(skin.opacity.o22))
                        .frame(width: skin.size.s2)
                        .padding(.leading, skin.size.s16 + skin.size.s1)
                        .padding(.top, skin.size.s48)
                        .padding(.bottom, -skin.size.s8)
                }
            }
            .background(
                skin.color(.palette("foreground", hovering ? skin.opacity.o03 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.present), value: isOpen)
    }

    private var agent: AgentInfo? {
        line.actor.hasPrefix("agent:") ? Int64(line.actor.dropFirst(6)).flatMap { model.agent($0) } : nil
    }

    private var actorName: String {
        if let agent { return agent.nameAndRole }
        if line.actor == "you" { return "You" }
        if line.actor.hasPrefix("runner:") {
            return Int64(line.actor.dropFirst(7)).flatMap { model.runners[$0] } ?? line.actor
        }
        return "System"
    }

    @ViewBuilder private var who: some View {
        if let agent {
            AgentFigure(agent: agent, model: model, size: skin.size.s32)
        } else if line.actor == "you" {
            Text(String((you ?? "You").split(separator: " ").prefix(2).compactMap(\.first)).uppercased())
                .citadelFont("t11", weight: "bold").foregroundStyle(skin.color(.palette("foreground", 1)))
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(
                    LinearGradient(
                        colors: [skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
        } else {
            Image(systemName: line.actor.hasPrefix("runner:") ? "server.rack" : "gearshape").citadelFont("t13")
                .foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s36, height: skin.size.s36)
                .background(skin.color(skin.text.muted).opacity(skin.opacity.o18), in: Circle())
        }
    }

    private var typeTint: (Color, String) {
        switch line.action.split(separator: ".").first.map(String.init) ?? "" {
        case "setting": (skin.color(skin.palette.accentSecondary), "gauge.with.needle")
        case "approval": (status.success, "checkmark")
        case "device": (skin.color(skin.palette.accentViolet), "key")
        case "account": (status.warning, "clock")
        default: (skin.color(skin.text.muted), "circle.fill")
        }
    }

    private var badge: some View {
        let (tint, icon) = typeTint
        return Image(systemName: icon).citadelFont("t8_5", weight: "bold").foregroundStyle(
            skin.color(.palette("foreground", 1))
        )
        .frame(width: skin.size.s18, height: skin.size.s18)
        .background(tint, in: RoundedRectangle(cornerRadius: skin.size.s6))
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s6).strokeBorder(
                skin.color(.palette("background", 1)), lineWidth: skin.size.s2))
    }

    /// "**You** · stall timeout · `CIT`".
    private var summary: Text {
        let primary = skin.color(skin.text.primary)
        var text = Text(actorName).bold().foregroundStyle(primary) + Text(" · \(what)").foregroundStyle(primary)
        if let scope = whereText {
            text =
                text + Text(" · ").foregroundStyle(primary)
                + Text(scope).monospaced().foregroundStyle(skin.color(skin.text.faint))
        }
        return text
    }

    /// The setting's name for a setting change, else the action in words ("issue in review").
    private var what: String {
        if line.action.hasPrefix("setting."), let key = line.details["key"] {
            let name = LimitNames.name(key).lowercased()
            return line.action == "setting.reset" ? "reset \(name)" : name
        }
        return line.action.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    private var whereText: String? {
        if let scope = line.details["scope"] {
            let parts = scope.split(separator: ":")
            if parts.count == 2, let id = Int64(parts[1]) {
                switch parts[0] {
                case "project": return model.projects.first { $0.id == id }?.key ?? scope
                case "runner": return model.runners[id] ?? scope
                case "account": return model.accounts[id]?.label ?? scope
                default: return "company"
                }
            }
            return scope
        }
        return line.entity
    }

    /// ~~before~~ → **after** for a change that carries them, else its details.
    @ViewBuilder private var change: some View {
        let old = line.details["old"]
        let new = line.details["new"]
        HStack(spacing: skin.size.s8) {
            if old != nil || new != nil {
                Text(format(old) ?? "inherited").citadelFont("t11", mono: true).foregroundStyle(status.danger)
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                    .background(
                        status.danger.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s6))
                Text(verbatim: "→").foregroundStyle(skin.color(skin.text.faint))
                Text(format(new) ?? "inherited").citadelFont("t11", weight: "semibold", mono: true).foregroundStyle(
                    status.success
                )
                .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                .background(status.success.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s6))
            } else {
                let fields = line.details.sorted { $0.key < $1.key }.prefix(4).map { "\($0.key) \($0.value)" }
                Text(fields.isEmpty ? "no details" : fields.joined(separator: " · "))
                    .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
            }
        }
        .citadelFont("t11")
    }

    /// A setting's raw value in its unit ("900" → "15 min").
    private func format(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let key = line.details["key"], let value = Int64(raw),
            let unit = model.limitsPage.server.first(where: { $0.key == key })?.unit
        else { return raw }
        return ScopedSetting.format(value, unit: unit)
    }
}
