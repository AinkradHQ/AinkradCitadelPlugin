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
                foot(rows.count)
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
        .onAppear { focused = true }
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
                        switch arrow {
                        case .down: selected = min(selected + 1, max(rows.count - 1, 0))
                        case .up: selected = max(selected - 1, 0)
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
                highlighted(item.title).citadelFont("t13", weight: "medium").lineLimit(1)
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

    private func highlighted(_ title: String) -> Text {
        guard let range = searchHighlight(query, in: title) else {
            return Text(title).foregroundStyle(skin.color(skin.text.primary))
        }
        return Text(title[..<range.lowerBound]).foregroundStyle(skin.color(skin.text.primary))
            + Text(title[range]).foregroundStyle(skin.color(skin.palette.accentPrimary)).bold()
            + Text(title[range.upperBound...]).foregroundStyle(skin.color(skin.text.primary))
    }

    @ViewBuilder private func icon(_ item: SearchItem, size: CGFloat) -> some View {
        switch item.kind {
        case .agent(let id):
            if let agent = model.agent(id) { AgentFigure(agent: agent, model: model, size: size) }
        case .run(let id):
            if let agent = model.agent(model.runs[id]?.agentID ?? model.companyRuns?.first { $0.id == id }?.agentID) {
                AgentFigure(agent: agent, model: model, size: size)
            } else {
                KindTile(glyph: item.glyph, tint: skin.color(skin.palette.accentSecondary), size: size)
            }
        case .approval, .stuck:
            KindTile(glyph: item.glyph, tint: skin.color(skin.palette.warning), size: size)
        case .requirement, .issue:
            KindTile(glyph: item.glyph, tint: skin.color(skin.palette.accentSecondary), size: size)
        case .project:
            KindTile(glyph: item.glyph, tint: skin.color(skin.palette.accentViolet), size: size)
        case .screen(let screen):
            GlyphTile(icon: screen.icon, size: size, tint: skin.color(skin.palette.accentPrimary))
        case .action:
            KindTile(glyph: item.glyph, tint: skin.color(skin.text.muted), size: size)
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

    private func foot(_ count: Int) -> some View {
        HStack(spacing: skin.size.s14) {
            Text("↑↓ move").foregroundStyle(skin.color(skin.text.faint))
            Text("↵ open").foregroundStyle(skin.color(skin.text.faint))
            Text("⌘↵ alt").foregroundStyle(skin.color(skin.text.faint))
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
            if alt {
                store.go(to: .threads)
            } else {
                store.open(.agent(id))
            }
        case .run(let id):
            let agent = model.runs[id]?.agentID ?? model.companyRuns?.first { $0.id == id }?.agentID
            if alt, let agent { store.open(.agent(agent)) } else { store.open(.run(id)) }
        case .requirement(let id):
            model.requirementsPage.selectedID = id
            store.go(to: .requirements)
        case .issue, .stuck: store.go(to: .stuck)
        case .project: store.go(to: .projects)
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
            case "shortcuts": store.isShowingShortcuts = true
            default: store.isShowingSettings = true
            }
        }
    }
}
