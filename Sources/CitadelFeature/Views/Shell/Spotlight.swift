import AinkradAppKit
import SwiftUI

/// ⌘K (prototype `search.js`): a Spotlight panel pinned near the top — the query, scope chips with counts, ranked
/// grouped rows with the match highlighted and one gliding highlight, a preview of the selected row, and the keys
/// (↑↓ move · ↵ open · ⌘↵ second action · ⇥ scope · esc close).
struct Spotlight: View {
    @Bindable var store: CitadelStore
    let model: CompanyModel
    @State private var query: String

    init(store: CitadelStore, model: CompanyModel, query: String = "") {
        self.store = store
        self.model = model
        self._query = State(initialValue: query)
    }
    @State private var scope: SearchScope = .all
    @State private var selected = 0
    @FocusState private var focused: Bool
    @Namespace private var glide
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var results: [SearchItem] { model.searchResults(query, scope: scope) }

    var body: some View {
        let rows = results
        let shape = RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
        ZStack(alignment: .top) {
            skin.color(.palette("black", skin.opacity.o25)).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                top(rows)
                HStack(spacing: 0) {
                    list(rows).frame(maxWidth: .infinity)
                    preview(rows.indices.contains(selected) ? rows[selected] : nil)
                        .frame(width: skin.size.s340)
                        .background(skin.color(.palette("foreground", skin.opacity.o03)))
                }
                .frame(height: skin.size.s460)
                .background(skin.color(.palette("black", skin.opacity.o12)))
                foot(rows.count, alt: rows.indices.contains(selected) ? rows[selected].altTitle : nil)
            }
            .frame(maxWidth: skin.size.s860 + skin.size.s40)
            .background(shape.fill(skin.color(.palette("surfaceElevated", skin.opacity.o90))))
            .background(.ultraThinMaterial, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
            .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s40, y: skin.size.s20)
            .padding(.top, skin.size.s60)
            .padding(.horizontal, skin.size.s20)
            .transition(.offset(y: -skin.size.s14).combined(with: .scale(scale: 0.97)).combined(with: .opacity))
        }
        .onAppear {
            focused = true
            // Artifacts load with their screen; ⌘K needs them too, so its Artifacts scope is never empty by accident.
            store.loadArtifacts()
        }
        .onChange(of: query) { selected = 0 }
        .onChange(of: scope) { selected = 0 }
    }

    // MARK: - Top

    private func top(_ rows: [SearchItem]) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s10) {
                AinkradCommandField(
                    "Search agents, runs, requirements, issues, actions…", text: $query, focus: $focused,
                    leading: {
                        Image(systemName: "magnifyingglass").citadelFont("t18").foregroundStyle(
                            skin.color(skin.text.muted))
                    },
                    onArrow: { arrow in
                        // The list wraps at both ends, as the prototype's does.
                        switch arrow {
                        case .down: selected = rows.isEmpty ? 0 : (selected + 1) % rows.count
                        case .up: selected = rows.isEmpty ? 0 : (selected - 1 + rows.count) % rows.count
                        default: return false
                        }
                        return true
                    },
                    onSubmit: { if rows.indices.contains(selected) { open(rows[selected], alt: false) } },
                    onEscape: close
                )
                .onKey { press in
                    if press.key == .tab {
                        cycleScope(back: press.modifiers.contains(.shift))
                        return .handled
                    }
                    if press.key == .return, press.modifiers.contains(.command), rows.indices.contains(selected) {
                        open(rows[selected], alt: true)
                        return .handled
                    }
                    return .ignored
                }
                AinkradKbd("esc").outlined()
            }
            AinkradFlowLayout(spacing: skin.size.s6) {
                ForEach(SearchScope.allCases) { option in chip(option) }
            }
        }
        .padding(.top, skin.size.s16)
        .padding(.horizontal, skin.size.s18)
        .padding(.bottom, skin.size.s10)
    }

    private func chip(_ option: SearchScope) -> some View {
        let isOn = scope == option
        let count = query.isEmpty || option == .all ? nil : model.searchResults(query, scope: option).count
        return AinkradTapArea(action: { scope = option }) {
            HStack(spacing: skin.size.s5) {
                Text(option.title).citadelFont("t12", weight: isOn ? "semibold" : "regular")
                if let count {
                    Text("\(count)").citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .foregroundStyle(skin.color(isOn ? skin.text.primary : skin.text.muted))
            .padding(.horizontal, skin.size.s11)
            .frame(height: skin.size.s28)
            .background(
                RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
                    .fill(
                        isOn
                            ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o18)
                            : skin.color(.palette("foreground", skin.opacity.o05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
                    .strokeBorder(
                        isOn ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45) : .clear, lineWidth: 1))
        }
    }

    private func cycleScope(back: Bool) {
        let all = SearchScope.allCases
        guard let index = all.firstIndex(of: scope) else { return }
        scope = all[(index + (back ? all.count - 1 : 1)) % all.count]
    }

    // MARK: - List

    private func list(_ rows: [SearchItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if rows.isEmpty {
                    VStack(spacing: skin.size.s8) {
                        Image(systemName: "magnifyingglass").citadelFont("t26").foregroundStyle(
                            skin.color(skin.text.faint))
                        Text("Nothing matches “\(query)”").citadelFont("t13", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text("Try another word, or press ⇥ to change scope").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, skin.size.s80)
                }
                LazyVStack(alignment: .leading, spacing: skin.size.s1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || rows[index - 1].group != item.group {
                            Text(item.group.uppercased()).citadelFont("t10_5", weight: "semibold").tracking(
                                skin.size.s1 / 2
                            )
                            .foregroundStyle(skin.color(skin.text.faint))
                            .padding(.top, index == 0 ? skin.size.s6 : skin.size.s12)
                            .padding(.bottom, skin.size.s4)
                            .padding(.horizontal, skin.size.s10)
                        }
                        row(item, isSelected: index == selected)
                            .id(item.id)
                            .onHover { if $0 { selected = index } }
                            .onTapGesture { open(item, alt: false) }
                    }
                }
                .padding(.horizontal, skin.size.s8)
                .padding(.bottom, skin.size.s10)
            }
            .scrollIndicators(.never)
            .onChange(of: selected) { _, new in
                guard rows.indices.contains(new) else { return }
                proxy.scrollTo(rows[new].id)
            }
        }
    }

    private func row(_ item: SearchItem, isSelected: Bool) -> some View {
        HStack(spacing: skin.size.s11) {
            icon(item, size: skin.size.s28)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                highlighted(item).citadelFont("t13", weight: "medium").lineLimit(1)
                Text(item.subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s8)
            if let meta = item.meta, !meta.isEmpty {
                Text(meta).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
                    .padding(.horizontal, skin.size.s6)
                    .padding(.vertical, skin.size.s2)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o07)),
                        in: RoundedRectangle(cornerRadius: skin.size.s6))
            }
        }
        .padding(.vertical, skin.size.s7)
        .padding(.horizontal, skin.size.s10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: skin.size.s11, style: .continuous)
                    .fill(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o22))
                    .matchedGeometryEffect(id: "row", in: glide)
            }
        }
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.18)),
            value: isSelected)
    }

    /// The title with each matched part in the accent: the substring, or each letter of a letters-in-order match.
    private func highlighted(_ item: SearchItem) -> Text {
        let title = item.title
        let fuzzy = searchScore(query, title: title, subtitle: item.subtitle) == 1
        var text = Text("")
        var cursor = title.startIndex
        for range in searchHighlight(query, in: title, fuzzy: fuzzy) {
            text =
                text + Text(title[cursor..<range.lowerBound]).foregroundStyle(skin.color(skin.text.primary))
                + Text(title[range]).foregroundStyle(skin.color(skin.palette.accentPrimary)).bold()
            cursor = range.upperBound
        }
        return text + Text(title[cursor...]).foregroundStyle(skin.color(skin.text.primary))
    }

    @ViewBuilder private func icon(_ item: SearchItem, size: CGFloat) -> some View {
        switch item.kind {
        case .agent(let id):
            if let agent = model.agent(id) { AgentFigure(agent: agent, model: model, size: size) }
        case .run(let id):
            if let agent = model.agent(model.runs[id]?.agentID ?? model.companyRuns?.first { $0.id == id }?.agentID) {
                AgentFigure(agent: agent, model: model, size: size)
            } else {
                AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.accentSecondary), size: size)
            }
        case .approval:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.warning), size: size)
        case .stuck:
            AinkradIconTile(
                glyph: item.glyph, tint: skin.color(item.isFailing ? skin.palette.danger : skin.palette.warning),
                size: size)
        // Requirements are violet and projects cyan, as in the prototype's SP_COL.
        case .requirement:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.accentViolet), size: size)
        case .issue:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.accentSecondary), size: size)
        case .project:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.accentSecondary), size: size)
        case .artifact:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.palette.accentPrimary), size: size)
        case .screen(let screen):
            GlyphTile(icon: screen.icon, size: size, tint: skin.color(skin.palette.accentPrimary))
        case .action:
            AinkradIconTile(glyph: item.glyph, tint: skin.color(skin.text.muted), size: size)
        }
    }

    // MARK: - Preview and foot

    @ViewBuilder private func preview(_ item: SearchItem?) -> some View {
        if let item {
            SpotlightPreview(store: store, model: model, item: item) { open(item, alt: $0) }
                .id(item.id)
                .transition(.offset(x: skin.size.s8).combined(with: .opacity))
        } else {
            Color.clear
        }
    }

    private func foot(_ count: Int, alt: String?) -> some View {
        HStack(spacing: skin.size.s14) {
            Text("↑↓ move").foregroundStyle(skin.color(skin.text.faint))
            Text("↵ open").foregroundStyle(skin.color(skin.text.faint))
            // The selected row's second action, named; hidden when it has none.
            if let alt {
                Text("⌘↵ \(alt.lowercased())").foregroundStyle(skin.color(skin.text.faint))
            }
            Text("⇥ scope").foregroundStyle(skin.color(skin.text.faint))
            Spacer()
            Text(Wording.count(count, "result")).foregroundStyle(skin.color(skin.text.muted))
        }
        .citadelFont("t11")
        .padding(.vertical, skin.size.s9)
        .padding(.horizontal, skin.size.s18)
    }

    // MARK: - Actions

    private func close() { store.isSearching = false }

    func open(_ item: SearchItem, alt: Bool) {
        close()
        switch item.kind {
        case .agent(let id):
            // ⌘↵ opens the agent's chat; ↵ its page.
            if alt { store.chat(with: id) } else { store.open(.agent(id)) }
        case .run(let id):
            let agent = model.runs[id]?.agentID ?? model.companyRuns?.first { $0.id == id }?.agentID
            if alt, let agent { store.open(.agent(agent)) } else { store.open(.run(id)) }
        case .requirement(let id):
            store.goRequirement(id)
        case .issue(let id):
            // An issue opens its requirement, else its agent (the prototype's `go`).
            if let requirement = model.issues[id]?.requirementID {
                store.goRequirement(requirement)
            } else if case .agent(let agent)? = model.issues[id]?.nextActor {
                store.open(.agent(agent))
            }
        case .stuck: store.go(to: .stuck)
        case .project(let id): store.openProject(id)
        case .artifact(let id):
            model.artifactsPage.quickLookID = id
            store.go(to: .artifacts)
        case .approval(let id):
            if alt, let run = model.approvals.first(where: { $0.id == id })?.fields["run"].flatMap(Int64.init) {
                store.open(.run(run))
            } else {
                store.selectedApproval = id
                store.go(to: .approvals)
            }
        case .screen(let screen): store.go(to: screen)
        case .action(let key):
            switch key {
            case "newRequirement": store.isComposingRequirement = true
            case "pauseAll": store.setCompanyPaused(true)
            case "switchCompany": store.isSwitchingCompany = true
            case "newCompany": store.openNewCompany()
            case "shortcuts": store.isShowingShortcuts = true
            case "newProject": store.go(to: .projects); store.pendingSheet = .newProject
            case "addAccount": store.go(to: .accounts); store.pendingSheet = .addAccount
            case "addRunner": store.go(to: .runners); store.pendingSheet = .addRunner
            default: store.isShowingSettings = true
            }
        }
    }
}
