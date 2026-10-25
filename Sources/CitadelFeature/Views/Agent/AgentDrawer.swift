import AinkradAppKit
import SwiftUI

/// The agent drawer (prototype `agent.js` agentDrawer): Instructions / Skills / Settings over a scrim, opened at
/// a section from the dock or a tile; Esc or the scrim closes it.
struct AgentDrawer: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let drawer: OrgPage.Drawer
    @State private var entered = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let page = model.orgPage
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        ZStack(alignment: .topTrailing) {
            skin.color(.palette("black", skin.opacity.o35)).contentShape(Rectangle())
                .onTapGesture { page.drawer = nil }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    HStack(spacing: skin.size.s12) {
                        AinkradGlideTabs(
                            OrgPage.DrawerSection.allCases.map { section in
                                AinkradGlideTab(
                                    section, title: section.rawValue,
                                    systemImage: section == .instructions
                                        ? "doc.text" : section == .skills ? "square.stack.3d.up" : "gearshape",
                                    count: section == .skills ? "\(page.agentSkills[agent.id]?.count ?? 0)" : nil)
                            },
                            selection: Binding(
                                get: { drawer.section }, set: { page.drawer = .init(section: $0) }),
                            tint: (agent.palette.lightColor, agent.palette.deepColor))
                        AinkradIconButton(systemName: "xmark", size: skin.size.s30, tooltip: "Close (Esc)") {
                            page.drawer = nil
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(.horizontal, skin.size.s16).padding(.vertical, skin.size.s14)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: skin.size.s14) {
                                switch drawer.section {
                                case .instructions: DrawerInstructions(agent: agent)
                                case .skills: DrawerSkills(model: model, agent: agent)
                                case .settings: DrawerSettings(store: store, model: model, agent: agent)
                                }
                            }
                            .padding(.horizontal, skin.size.s16).padding(.bottom, skin.size.s16)
                        }
                        .onAppear { scroll(proxy) }
                        .onChange(of: drawer) { _, _ in scroll(proxy) }
                    }
                }
                .frame(width: min(skin.size.s640 + skin.size.s120, geo.size.width * 0.62))
                .frame(maxHeight: .infinity)
                .background(shape.fill(skin.color(.palette("background", skin.opacity.o97))))
                .clipShape(shape)
                .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
                .shadow(
                    color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, x: -skin.size.s20
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, skin.size.s80)
            .padding(.trailing, skin.size.s20)
            .padding(.bottom, skin.size.s20)
            .offset(x: entered || reduceMotion ? 0 : skin.size.s60)
            .opacity(entered || reduceMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(skin.animation(AinkradAnimationToken(curve: "spring", response: 0.35, damping: 0.8))) {
                entered = true
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let anchor = drawer.anchor else { return }
        withAnimation(skin.animation(skin.motion.hover)) { proxy.scrollTo(anchor, anchor: .top) }
    }
}

/// A drawer section tile (`.tile` with a `sec-h`).
struct DrawerTile<Content: View>: View {
    let title: String
    var link: (String, () -> Void)?
    var danger = false
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            if !title.isEmpty {
                HStack {
                    Text(title).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                    Spacer()
                    if let link {
                        AinkradTapArea(action: link.1) {
                            Text(link.0).citadelFont("t11", weight: "medium").foregroundStyle(
                                skin.color(skin.palette.accentSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            content
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
        .overlay(
            shape.strokeBorder(
                danger
                    ? skin.color(skin.palette.danger).opacity(skin.opacity.o25)
                    : skin.color(.palette("foreground", skin.opacity.o12)),
                lineWidth: 1))
    }
}

/// Instructions: the system prompt editor (from the role's template) and the guideline switches. The server keeps
/// neither on an agent yet.
private struct DrawerInstructions: View {
    let agent: AgentInfo
    @State private var text = ""
    @State private var on: [String] = HireCatalog.guidelines.prefix(5).map(\.text)
    @State private var all: [String] = HireCatalog.guidelines.map(\.text)
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let template = HireCatalog.role(agent.role)?.instructions ?? ""
        DrawerTile(title: "") {
            InstructionsEditor(
                title: "System instructions", pill: "\(agent.role) template", text: $text, template: template,
                minHeight: skin.size.s140)
            HStack {
                Text("Sent at the start of every run · changes apply from the next run").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
                Spacer()
                AinkradButton(title: "Save instructions") {}.compact().disabled(true).fixedSize()
            }
            NeedsServer(text: "Per-agent instructions need an `instructions` field on the agent (PATCH /agents/{id}).")
        }
        DrawerTile(title: "Guidelines · \(on.count) on") {
            GuidelineCards(on: $on, all: $all)
            NeedsServer(text: "Guidelines aren't stored on an agent yet.")
        }
        .onAppear { text = template }
    }
}

/// Skills: what reaches the agent (resolved from company, department, role and project), the selected one, and
/// the library.
private struct DrawerSkills: View {
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.orgPage
        let have = page.agentSkills[agent.id] ?? []
        let names = Set(have.map(\.name))
        let library = Dictionary(grouping: page.skillLibrary, by: \.name).compactMap {
            $0.value.max { $0.version < $1.version }
        }
        .filter { !names.contains($0.name) }.sorted { $0.name < $1.name }
        let selected = have.first { $0.name == page.selectedSkill } ?? have.first
        DrawerTile(
            title:
                "Attached \(have.count) · ≈ \(Fmt.tokens(have.reduce(0) { $0 + $1.bytes } / 4)) tokens of context per run"
        ) {
            if have.isEmpty {
                Text("No skills attached — pick some from the library below.").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            CardGrid(columns: 2) {
                ForEach(have) { skill in
                    ChoiceCard(
                        isOn: skill.id == selected?.id, height: skin.size.s56,
                        action: { page.selectedSkill = skill.name }
                    ) {
                        CardGlyph(glyph: "square.stack.3d.up", isOn: skill.id == selected?.id, size: skin.size.s30)
                        CardText(
                            title: "\(skill.name) v\(skill.version)", caption: "attached to its \(skill.attachedTo)",
                            mono: true)
                    }
                }
            }
        }
        if let selected {
            DrawerTile(title: "") {
                HStack(spacing: skin.size.s8) {
                    Text("❯_").citadelFont("t10", weight: "semibold", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentPrimary))
                    Text("skills/\(selected.name).md").citadelFont("t12", weight: "semibold")
                    Text("v\(selected.version)").citadelFont("t10_5").foregroundStyle(
                        skin.color(skin.palette.accentPrimary))
                    Spacer()
                    Text("≈ \(Fmt.tokens(selected.bytes / 4)) tok").citadelFont("t10_5").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                NeedsServer(text: "The skill's text needs GET /skills/{id}; it is edited in Lore.")
                HStack {
                    Text("Edited in Lore · versioned — agents pick up a new version on their next run").citadelFont(
                        "t11"
                    )
                    .foregroundStyle(skin.color(skin.text.faint))
                    Spacer()
                    AinkradButton(title: "Detach", style: .danger) {}.compact().disabled(true).fixedSize()
                        .help("Needs server: per-agent attach / detach")
                }
            }
        }
        DrawerTile(title: "Library \(library.count)") {
            CardGrid(columns: 2) {
                ForEach(library) { skill in
                    ChoiceCard(height: skin.size.s56) {
                        CardGlyph(glyph: "square.stack.3d.up", size: skin.size.s30)
                        CardText(
                            title: "\(skill.name) v\(skill.version)", caption: "≈ \(Fmt.tokens(skill.bytes / 4)) tok",
                            mono: true)
                        AinkradButton(title: "Attach", style: .secondary) {}.compact().disabled(true).fixedSize()
                    }
                }
            }
            if library.isEmpty {
                Text("Every skill in the library reaches this agent.").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            NeedsServer(text: "Skills attach to the company, a department, a role or a project — not to one agent yet.")
        }
        .id("library")
    }
}
