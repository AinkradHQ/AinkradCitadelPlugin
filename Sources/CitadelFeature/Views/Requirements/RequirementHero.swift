import AinkradAppKit
import SwiftUI

/// The requirement's hero (`.rq-hero`): a 58 pt ring, its key and title, the state pill, project, owner, ETA and
/// who is working on it now, and the action dock — Approve plan / Ask for changes while the plan waits, Plan and
/// Artifacts (the drawer), Threads. Rename and Cancel (plugin-only) sit behind ⋯. Pause and Mark done wait for
/// the server (no endpoint yet), so they are not drawn.
struct RequirementHero: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @Binding var renaming: Bool
    @Binding var cancelling: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var page: RequirementsPage { model.requirementsPage }
    private var plan: PlanTree? { page.plans[requirement.id] }
    private var owner: AgentInfo? { model.agent(requirement.ownerAgentID) ?? model.ceo }

    var body: some View {
        let tint = RequirementLook.tint(requirement.state, skin: skin)
        let ring = RequirementLook.ring(requirement)
        let project = model.project(of: requirement)
        let (ca, cb) = RequirementLook.colors(project: project?.id, model: model)
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        let base = skin.color(.palette("background", skin.opacity.o88))
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .center, spacing: skin.size.s16) {
                AinkradRingGauge(
                    value: ring.value, tint: tint, diameter: skin.size.s56 + skin.size.s2, lineWidth: skin.size.s5
                ) {
                    Text(ring.label).citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                        Text(requirement.key).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
                        Text(requirement.title).citadelFont("t20", weight: "bold").lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                    AinkradFlowLayout(spacing: skin.size.s6) {
                        GlowStatePill(text: RequirementLook.label(requirement.state), tint: tint)
                        if let project {
                            ThreadHeroChip {
                                Image(systemName: "folder").citadelFont("t10")
                                Text(project.name)
                            }
                        }
                        if let owner {
                            ThreadHeroChip(action: { store.open(.agent(owner.id)) }) {
                                AgentFigure(agent: owner, model: model, size: skin.size.s16)
                                Text("with \(owner.name) · \(owner.roleLabel)")
                            }
                        }
                        if let eta = requirement.eta ?? plan?.eta, requirement.state != "done" {
                            ThreadHeroChip { Text("ETA \(Fmt.eta(eta))") }
                        }
                        busy
                    }
                }
            }
            AinkradFlowLayout(spacing: skin.size.s6) { dock }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.size.s16)
        .background(
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: ca.opacity(skin.opacity.o14), location: 0),
                        .init(color: .clear, location: 0.6),
                        .init(color: cb.opacity(skin.opacity.o12), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .background(shape.fill(base))
        )
        .overlay(shape.strokeBorder(ca.opacity(skin.opacity.o25), lineWidth: 1))
        .padding(.horizontal, skin.size.s14)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s6)
    }

    /// "●● 2 working": the plan's assignees with a live run, while it is in progress.
    @ViewBuilder private var busy: some View {
        let ids = Set(plan?.allTasks.compactMap(\.assigneeAgentID) ?? [])
        let working = model.agents.values.filter { ids.contains($0.id) && [.working, .thinking].contains($0.figure) }
            .sorted { $0.id < $1.id }
        if requirement.state == "in_progress", !working.isEmpty {
            HStack(spacing: -skin.size.s5) {
                ForEach(working) { AgentFigure(agent: $0, model: model, size: skin.size.s20) }
            }
            .padding(.leading, skin.size.s4)
            Text("\(working.count) working").citadelFont("t11").foregroundStyle(theme.accentSecondary)
                .padding(.leading, skin.size.s6)
        }
    }

    /// The pending plan approval of this requirement.
    private var pendingPlan: ApprovalInfo? {
        model.approvals.first { $0.kind == "plan_approval" && $0.fields["requirement"] == String(requirement.id) }
            ?? planInThread
    }

    private var planInThread: ApprovalInfo? {
        for item in page.threads[requirement.id]?.items ?? [] {
            if case .approval(let a, _) = item, a.kind == "plan_approval", a.status == "pending" { return a }
        }
        return nil
    }

    @ViewBuilder private var dock: some View {
        if requirement.state == "plan_review", let approval = pendingPlan {
            AinkradDockButton("Approve plan", systemImage: "checkmark", tone: .primary) {
                store.approvePlan(approval, requirement: requirement)
            }
            AinkradDockButton("Ask for changes", systemImage: "pencil") { page.askingChanges.toggle() }
        }
        if plan != nil {
            AinkradDockButton("Plan", systemImage: "text.alignleft") { page.drawer = [.plan] }
        }
        AinkradDockButton("Artifacts", systemImage: "square.3.layers.3d") { page.drawer = [.artifacts] }
        AinkradDockButton("Threads", systemImage: "bubble.left") { store.screen = .threads }
        if !["done", "cancelled"].contains(requirement.state) {
            AinkradMenuButton(items: [
                AinkradMenuItem(title: "Rename…", systemName: "pencil") { renaming = true },
                AinkradMenuItem(title: "Cancel requirement…", systemName: "xmark.circle", isDestructive: true) {
                    cancelling = true
                },
            ]) {
                Image(systemName: "ellipsis").citadelFont("t14", weight: "medium")
                    .foregroundStyle(skin.color(skin.text.primary))
                    .frame(width: skin.size.s34, height: skin.size.s34)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o07)),
                        in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
            }
            .help("Rename or cancel \(requirement.key)")
        }
    }
}

/// "Ask for changes to the R-11 plan" (`.rq-changes`): your reason goes back with the plan, which the PO revises.
struct AskForChangesPanel: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @State private var reason = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var owner: String { model.agent(requirement.ownerAgentID)?.name ?? "the PO" }
    /// "Mira and Toma revise it — you get a v2 with a diff to approve."
    private var reviseLine: String {
        let lead = model.lead(ofProject: model.project(of: requirement)?.id)?.name
        let who = lead.map { "\(owner) and \($0)" } ?? owner
        return "\(who) revise it — you get a v2 with a diff to approve."
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("Ask for changes to the \(requirement.key) plan").citadelFont("t13", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                Text(reviseLine).citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.muted))
            }
            AinkradTextArea(
                text: $reason, placeholder: "e.g. export can wait — drop CIT-73, keep it under 12 pts",
                minHeight: skin.size.s64, maxHeight: skin.size.s120)
            HStack(spacing: skin.size.s8) {
                Spacer(minLength: 0)
                AinkradButton(title: "Cancel", style: .secondary) { model.requirementsPage.askingChanges = false }
                    .compact().fixedSize()
                AinkradButton(title: "Send to \(owner)") {
                    store.askForChanges(requirement: requirement, reason: reason)
                    reason = ""
                }
                .compact().fixedSize()
            }
        }
        .padding(skin.size.s14)
        .background(shape.fill(status.warning.opacity(skin.opacity.o06)))
        .overlay(shape.strokeBorder(status.warning.opacity(skin.opacity.o35), lineWidth: 1))
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s6)
    }
}
