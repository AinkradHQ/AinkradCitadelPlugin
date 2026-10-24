import AinkradAppKit
import SwiftUI

/// Screen 12: one thread per requirement with the CEO (decision #39), beside the list of requirements and the
/// requirement's live plan. Every agent question on the requirement lands in the thread; answers go back to the
/// agent that asked.
struct RequirementsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var composing = false
    @State private var newTitle = ""
    @State private var newBody = ""
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
                .frame(width: skin.size.s250)
                .background(theme.surface.opacity(skin.opacity.o20))
            Group {
                if let selected {
                    RequirementThreadView(store: store, model: model, requirement: selected).id(selected.id)
                    PlanRail(store: store, model: model, requirement: selected)
                        .frame(width: skin.size.s300)
                        .background(theme.surface.opacity(skin.opacity.o20))
                } else {
                    AinkradEmptyState(
                        icon: "rhombus", title: "No requirements yet",
                        message: "Ask the CEO for something with ＋. It plans the work before any agent starts it."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: selected?.id)
        }
        .offlineDimmed()
        .onChange(of: selected?.id, initial: true) { _, id in if let id { store.openRequirement(id) } }
        // A question asked or answered anywhere (an agent thread, screen 07) shows here too.
        .onChange(of: model.questions) { _, _ in if let id = selected?.id { store.openRequirement(id) } }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Requirements", crumb: nil) {
                AinkradIconButton(systemName: "plus", size: skin.size.s30, tooltip: "New requirement for the CEO") {
                    composing = true
                }
                .outlineBox()
                .ainkradPopover(isPresented: $composing) { newRequirement }
            }
            HStack(spacing: skin.size.s6) {
                ForEach(RequirementFilter.allCases, id: \.self) { filter in
                    AinkradToggleButton(
                        isOn: Binding(get: { page.filter == filter }, set: { if $0 { page.filter = filter } }),
                        title: filter.title)
                }
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.bottom, skin.size.s8)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    ForEach(list) { requirement in
                        RequirementRow(
                            requirement: requirement, model: model, isSelected: requirement.id == selected?.id
                        ) { page.selectedID = requirement.id }
                    }
                    if list.isEmpty {
                        Text(page.filter == .needsYou ? "Nothing waits on you." : "None here.").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint)).padding(skin.size.s10)
                    }
                }
                .padding(.horizontal, skin.size.s8)
                .padding(.bottom, skin.size.s14)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: list.map(\.id))
            }
        }
    }

    /// ＋: what you want, for the CEO to route and plan.
    private var newRequirement: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text("New requirement").citadelFont("t13", weight: "semibold")
            AinkradTextField(text: $newTitle, placeholder: "What you want, in one line")
            AinkradTextArea(text: $newBody, placeholder: "Details for the CEO (optional)", minHeight: skin.size.s80)
            HStack {
                Text("The CEO routes it and the team plans it before any work starts.").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s8)
                AinkradButton(title: "Send to the CEO") {
                    store.submitRequirement(title: newTitle, body: newBody)
                    newTitle = ""
                    newBody = ""
                    composing = false
                }
                .compact().fixedSize()
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(skin.size.s14)
        .frame(width: skin.size.s380)
    }
}

/// A requirement in the list: key and title, the waiting count, its state and owner, progress by points.
private struct RequirementRow: View {
    let requirement: RequirementInfo
    let model: CompanyModel
    let isSelected: Bool
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var isDone: Bool { requirement.state == "done" }

    var body: some View {
        let waiting = model.waitingCount(requirement)
        VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s6) {
                (Text(requirement.key).foregroundStyle(theme.accentSecondary)
                    .font(skin.font(AinkradFontToken(sizeKey: "t10_5", mono: "family")))
                    + Text(" \(requirement.title)").foregroundStyle(skin.color(skin.text.primary)))
                    .citadelFont("t13").lineLimit(1)
                Spacer(minLength: skin.size.s4)
                if isDone {
                    Text("✓").citadelFont("t12").foregroundStyle(status.success)
                } else if waiting > 0 {
                    AinkradBadge(text: "\(waiting)", status: .warning)
                }
            }
            HStack(spacing: skin.size.s6) {
                StateBadge(state: requirement.state)
                Text(model.requirementSubtitle(requirement)).citadelFont("t11").lineLimit(1)
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            AinkradBudgetBar(
                label: requirement.key, value: Double(requirement.donePoints),
                limit: Double(max(requirement.points, 1)), warnFraction: nil, showsHardLimit: false,
                tone: isDone ? .success : .progress(Double(requirement.donePoints), of: Double(requirement.points)))
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s8)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                .fill(
                    isSelected
                        ? theme.accentPrimary.opacity(skin.opacity.o16)
                        : skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .opacity(isDone && !isSelected ? skin.opacity.o60 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A requirement's state: planning → plan to approve → in progress → done.
struct StateBadge: View {
    let state: String
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        switch state {
        case "plan_review": AinkradBadge(text: "plan to approve", status: .warning)
        case "in_progress": AinkradBadge(text: "in progress", tint: theme.accentSecondary)
        case "done": AinkradBadge(text: "done", status: .success)
        default: AinkradBadge(text: state.replacingOccurrences(of: "_", with: " "))
        }
    }
}
