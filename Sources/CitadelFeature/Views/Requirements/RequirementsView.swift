import AinkradAppKit
import SwiftUI

/// Screen 12: one thread per requirement with the CEO (decision #39), beside the list of requirements and the
/// requirement's live plan. Every agent question on the requirement lands in the thread; answers go back to the
/// agent that asked. Plan and artifacts open in a floating drawer with a back stack.
struct RequirementsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RequirementsPage { model.requirementsPage }
    private var list: [RequirementInfo] { model.requirementList(page.filter) }

    /// The selection, or the first of the list.
    private var selected: RequirementInfo? {
        model.requirements.first { $0.id == page.selectedID } ?? list.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: skin.size.s320 + skin.size.s10)
                .background(skin.color(.palette("foreground", skin.opacity.o03)).opacity(skin.opacity.o60))
            Group {
                if let selected {
                    RequirementThreadView(store: store, model: model, requirement: selected).id(selected.id)
                    PlanRail(store: store, model: model, requirement: selected)
                        .frame(width: skin.size.s320)
                } else {
                    AinkradEmptyState(
                        icon: "rhombus", title: "No requirements yet",
                        message: "Ask the CEO for something with ＋ New. It plans the work before any agent starts it."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: selected?.id)
        }
        .ainkradFloatingDrawer(
            isPresented: Binding(
                get: { selected != nil && !page.drawer.isEmpty }, set: { if !$0 { page.drawer = [] } }),
            top: skin.size.s110, inset: skin.size.s34
        ) {
            AinkradDrawerPanel(
                onClose: { page.drawer = [] },
                header: { if let selected { RequirementDrawerHeader(model: model, requirement: selected) } },
                content: {
                    if let selected { RequirementDrawerBody(store: store, model: model, requirement: selected) }
                },
                footer: {
                    if let selected { RequirementDrawerFooter(store: store, model: model, requirement: selected) }
                }
            )
        }
        .offlineDimmed()
        .onChange(of: selected?.id, initial: true) { old, id in
            if let id { store.openRequirement(id) }
            if old != nil, old != id {
                page.drawer = []
                page.askingChanges = false
            }
        }
        // A question asked or answered anywhere (an agent thread, screen 07) shows here too.
        .onChange(of: model.questions) { _, _ in if let id = selected?.id { store.openRequirement(id) } }
        // A requirement that arrives while the list is open glows amber once (`.arrive`).
        .onChange(of: model.requirements.map(\.id), initial: true) { _, ids in page.noteArrivals(ids) }
    }

    private var openCount: Int { model.requirementList(.open).count }
    private var asksCount: Int { model.requirementList(.open).reduce(0) { $0 + model.waitingCount($1) } }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s10) {
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text("Requirements").citadelFont("t17", weight: "bold")
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text("\(openCount) open · \(asksCount) ask you").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                Spacer(minLength: skin.size.s8)
                AinkradDockButton("New", systemImage: "plus", tone: .primary, height: skin.size.s30) {
                    store.isComposingRequirement = true
                }
                .help("New requirement (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, skin.size.s4)
            AinkradGlideTabs(
                RequirementFilter.allCases.map {
                    AinkradGlideTab($0, title: $0.title, count: "\(model.requirementList($0).count)")
                },
                selection: Binding(get: { page.filter }, set: { page.filter = $0 }), height: skin.size.s32)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, requirement in
                        RequirementCard(
                            requirement: requirement, model: model, isSelected: requirement.id == selected?.id,
                            isFresh: page.fresh.contains(requirement.id), index: index
                        ) { page.selectedID = requirement.id }
                    }
                    if shown.isEmpty {
                        AinkradEmptyState(icon: "checkmark", title: "Nothing here", message: "")
                            .padding(.top, skin.size.s40)
                    }
                }
                .padding(skin.size.s2)
                .padding(.bottom, skin.size.s14)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: shown.map(\.id))
            }
        }
        .padding(.top, skin.size.s14)
        .padding(.horizontal, skin.size.s12)
    }

    /// The Open tab lists the done ones after the open ones (`reqs-view.js`).
    private var shown: [RequirementInfo] {
        page.filter == .open ? list + model.requirementList(.done) : list
    }
}
