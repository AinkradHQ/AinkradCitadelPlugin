import AinkradAppKit
import SwiftUI

/// New requirement (`ACT.newReq`, 760 wide): the CEO it goes to, a big title and the details, "Done when" criteria,
/// the project and the priority as cards, and what happens next. ⌘↵ sends. From API minor 18 the request carries
/// the project, priority and criteria as fields; an older server takes a title and a body only, so they are written
/// into the body for the CEO to route by.
struct NewRequirementSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var title = ""
    @State private var details = ""
    @State private var criterion = ""
    @State private var criteria: [String] = []
    /// `nil` lets the CEO decide.
    @State private var projectID: Int64?
    @State private var choseProject = false
    @State private var priority = "normal"
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var ceoName: String { model.ceo?.name ?? "the CEO" }
    private var canSend: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s16) {
            head
            ident
            section("Done when", note: "· optional acceptance criteria the plan must cover") { acceptance }
            section("Project") { projects }
            section("Priority") { priorities }
            flow
            foot
        }
        .onAppear {
            if !choseProject { projectID = model.projects.sorted { $0.id < $1.id }.first?.id }
        }
    }

    private var head: some View {
        HStack(spacing: skin.size.s14) {
            if let ceo = model.ceo { AgentFigure(agent: ceo, model: model, size: skin.size.s52) }
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("New requirement").citadelFont("t18", weight: "bold").foregroundStyle(
                    skin.color(skin.text.primary))
                (Text("Goes to ") + Text("\(ceoName) (CEO)").foregroundStyle(skin.color(skin.text.primary)).bold()
                    + Text(" — it routes it, the PO plans it, you approve the plan before any work starts."))
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
        }
    }

    private var ident: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            AinkradBareEditor(text: $title, placeholder: "What do you want?", sizeKey: "t20", weight: "semibold")
            AinkradBareEditor(
                text: $details,
                placeholder:
                    "Details — the problem, who it's for, constraints. e.g. “A weekly cost report in my inbox, per project, every Monday 9:00.”",
                sizeKey: "t13")
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s8)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }

    private func section<Content: View>(
        _ title: String, note: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            (Text(title).fontWeight(.semibold).foregroundStyle(skin.color(skin.text.muted))
                + Text(note.map { " \($0)" } ?? "").foregroundStyle(skin.color(skin.text.faint)))
                .citadelFont("t11")
            content()
        }
    }

    private var acceptance: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            ForEach(Array(criteria.enumerated()), id: \.offset) { index, text in
                HStack(spacing: skin.size.s10) {
                    Text("✓").citadelFont("t11").foregroundStyle(status.success)
                    Text(text).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                    Spacer(minLength: skin.size.s8)
                    AinkradTapArea(help: "Remove", action: { criteria.remove(at: index) }) {
                        Image(systemName: "xmark").citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                .padding(.horizontal, skin.size.s12)
                .frame(height: skin.size.s38)
                .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
            }
            HStack(spacing: skin.size.s6) {
                AinkradBareEditor(
                    text: $criterion, placeholder: "e.g. arrives every Monday 9:00", sizeKey: "t12", onReturn: add)
                AinkradTapArea(help: "Add", action: add) {
                    Image(systemName: "plus").citadelFont("t12", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.muted)).frame(width: skin.size.s30, height: skin.size.s30)
                }
            }
            .padding(.horizontal, skin.size.s8)
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
            .overlay(
                shape.strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o12)),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3])))
        }
    }

    private func add() {
        let text = criterion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        criteria.append(text)
        criterion = ""
    }

    private var projects: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: skin.size.s10), count: 4)
        return LazyVGrid(columns: grid, spacing: skin.size.s10) {
            ForEach(model.projects.sorted { $0.id < $1.id }) { project in
                let (ca, cb) = RequirementLook.colors(project: project.id, model: model)
                OptionCard(isOn: projectID == project.id, tint: skin.color(skin.palette.accentPrimary)) {
                    projectID = project.id
                    choseProject = true
                } label: {
                    HStack(spacing: skin.size.s10) {
                        projectTile(Text(String(project.key.prefix(1))), ca, cb)
                        VStack(alignment: .leading, spacing: skin.size.s1) {
                            Text(project.name).citadelFont("t13", weight: "semibold")
                            Text(
                                "\(project.key) · \(model.departments.flatMap(\.teams).first { $0.id == project.teamID }?.name ?? project.mode)"
                            ).citadelFont("t11")
                                .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                        }
                    }
                }
            }
            OptionCard(isOn: projectID == nil, tint: skin.color(skin.palette.accentPrimary)) {
                projectID = nil
                choseProject = true
            } label: {
                HStack(spacing: skin.size.s10) {
                    projectTile(
                        Text("✦"), skin.color(skin.palette.accentViolet), AinkradFigurePalette.ultraviolet.deepColor)
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text("Let the CEO decide").citadelFont("t13", weight: "semibold")
                        Text("routes to the right team").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func projectTile(_ glyph: Text, _ ca: Color, _ cb: Color) -> some View {
        glyph.font(skin.font(AinkradFontToken(sizeKey: "t14", weight: "semibold")))
            .foregroundStyle(skin.color(skin.palette.white))
            .frame(width: skin.size.s32, height: skin.size.s32)
            .background(
                LinearGradient(colors: [ca, cb], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
    }

    private var priorities: some View {
        let options: [(String, String, String, String)] = [
            ("low", "Low", "after current work", "▮"), ("normal", "Normal", "planned into the next sprint", "▮▮"),
            ("urgent", "Urgent", "the CEO pulls it in now", "▮▮▮▮"),
        ]
        return HStack(spacing: skin.size.s10) {
            ForEach(options, id: \.0) { value, title, detail, bars in
                let tint =
                    value == "urgent"
                    ? status.danger
                    : value == "low" ? skin.color(skin.text.muted) : skin.color(skin.palette.accentPrimary)
                OptionCard(
                    isOn: priority == value,
                    tint: value == "urgent" ? status.danger : skin.color(skin.palette.accentPrimary)
                ) {
                    priority = value
                } label: {
                    VStack(alignment: .leading, spacing: skin.size.s4) {
                        Text(bars).citadelFont("t10").foregroundStyle(tint)
                        Text(title).citadelFont("t13", weight: "semibold")
                        Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
        }
    }

    private var flow: some View {
        let steps = [
            ("✦", "\(ceoName) routes it", "to a department and team"),
            ("≡", "The PO plans it", "epics, tasks, estimate, cost"),
            ("✓", "You approve the plan", "nothing starts before that"),
        ]
        return HStack(alignment: .center, spacing: skin.size.s8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Text("→").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)) }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(step.0).citadelFont("t12").foregroundStyle(skin.color(skin.palette.accentViolet))
                        .frame(width: skin.size.s26, height: skin.size.s26)
                        .background(
                            skin.color(skin.palette.accentViolet).opacity(skin.opacity.o14),
                            in: RoundedRectangle(cornerRadius: skin.size.s8)
                        )
                        .padding(.bottom, skin.size.s4)
                    Text(step.1).citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    Text(step.2).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(skin.size.s12)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14))
    }

    private var foot: some View {
        HStack(spacing: skin.size.s10) {
            Text("⌘↵ sends").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            Spacer(minLength: skin.size.s8)
            AinkradButton(title: "Cancel", style: .ghost) { store.isComposingRequirement = false }
                .borderless().compact().fixedSize()
            AinkradButton(title: "Send to \(ceoName)", action: send)
                .compact().fixedSize().disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    /// The body the CEO reads: your details, then the criteria, project and priority.
    var composedBody: String {
        var parts = [details.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !criteria.isEmpty { parts.append("Done when: " + criteria.joined(separator: "; ")) }
        parts.append("Project: " + (model.projects.first { $0.id == projectID }?.name ?? "let the CEO decide"))
        if priority != "normal" { parts.append("Priority: \(priority)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func send() {
        guard canSend else { return }
        store.sendNewRequirement(
            title: title,
            body: store.hasTrancheB ? details.trimmingCharacters(in: .whitespacesAndNewlines) : composedBody,
            extras: RequestExtras(project: projectID, priority: priority, criteria: criteria))
    }
}

/// A selectable card (`.h-card`): soft glass, tinted rim and fill when on, a lift on hover.
private struct OptionCard<Label: View>: View {
    let isOn: Bool
    let tint: Color
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: action) {
            label()
                .foregroundStyle(skin.color(skin.text.primary))
                .padding(skin.size.s14)
                .frame(maxWidth: .infinity, minHeight: skin.size.s64, maxHeight: .infinity, alignment: .leading)
                .background(
                    shape.fill(
                        isOn
                            ? tint.opacity(skin.opacity.o12)
                            : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03)))
                )
                .overlay(
                    shape.strokeBorder(
                        isOn ? tint.opacity(skin.opacity.o55) : skin.color(.palette("foreground", skin.opacity.o08)),
                        lineWidth: 1)
                )
                .contentShape(shape)
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
