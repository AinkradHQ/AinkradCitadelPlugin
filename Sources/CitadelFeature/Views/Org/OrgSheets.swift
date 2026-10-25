import AinkradAppKit
import SwiftUI

extension View {
    /// Every sheet the org and agent screens open (`OrgPage.sheet`), and the pause / stop confirmations.
    func orgSheets(_ store: CitadelStore, _ model: CompanyModel) -> some View {
        modifier(OrgSheets(store: store, model: model))
    }
}

private struct OrgSheets: ViewModifier {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        let page = model.orgPage
        content
            .ainkradPanelModal(isPresented: presented, contentWidth: width(page.sheet) - skin.size.s48) {
                sheet(page.sheet)
            }
            .ainkradConfirmDialog(
                isPresented: confirm { if case .pause = $0 { true } else { false } },
                title: "Pause \(pausing?.name ?? "")?",
                message:
                    "\(pausing.flatMap { model.currentRun(of: $0.id) }?.isLive == true ? "Its run finishes the current tool call, then parks (ends cancelled: paused_by_user). " : "")New wakes queue until you resume. Pause is not a kill — ⋯ › Stop run now is the hard stop.",
                confirmTitle: "Pause"
            ) { if let pausing { store.pause(pausing) } }
            .ainkradConfirmDialog(
                isPresented: confirm { if case .stopRun = $0 { true } else { false } },
                title: "Stop \(stopping.flatMap { model.agent($0.agentID) }?.name ?? "the")'s run now?",
                message: "Kills the harness mid-tool. The run ends cancelled; the worktree is kept.",
                confirmTitle: "Stop now", isDestructive: true
            ) {
                if let run = stopping, let agent = model.agent(run.agentID) { store.stopRun(of: agent, run: run.id) }
            }
    }

    private var pausing: AgentInfo? {
        if case .pause(let id) = model.orgPage.openSheet { return model.agents[id] }
        return nil
    }

    private var stopping: RunInfo? {
        if case .stopRun(let id) = model.orgPage.openSheet { return model.runs[id] }
        return nil
    }

    private var presented: Binding<Bool> {
        let page = model.orgPage
        return Binding(
            get: {
                switch page.openSheet {
                case nil, .pause, .stopRun: false
                default: true
                }
            }, set: { if !$0 { page.close() } })
    }

    private func confirm(_ matches: @escaping (OrgPage.Sheet) -> Bool) -> Binding<Bool> {
        let page = model.orgPage
        return Binding(get: { page.sheet.map(matches) ?? false }, set: { if !$0 { page.sheet = nil } })
    }

    private func width(_ sheet: OrgPage.Sheet?) -> CGFloat {
        switch sheet {
        case .pendingHires: skin.size.s620 + skin.size.s96
        case .structure: skin.size.s860 + skin.size.s60
        case .hire: skin.size.s860 + skin.size.s120
        case .team: skin.size.s560 + skin.size.s40
        case .department, .appearance: skin.size.s620
        case .role: skin.size.s640
        case .changeModel, .reassign: skin.size.s520
        default: skin.size.s440
        }
    }

    @ViewBuilder private func sheet(_ sheet: OrgPage.Sheet?) -> some View {
        switch sheet {
        case .pendingHires: PendingHiresSheet(store: store, model: model)
        case .structure: StructureSheet(store: store, model: model)
        case .hire(let team, let step): HireWizard(store: store, model: model, team: team, step: step)
        case .team(let id): TeamSheet(store: store, model: model, team: id)
        case .department(let id): DepartmentSheet(store: store, model: model, department: id)
        case .role(let name): RoleSheet(store: store, model: model, role: name)
        case .editBudget(let id):
            if let agent = model.agents[id] { EditBudgetSheet(store: store, model: model, agent: agent) }
        case .changeModel(let id):
            if let agent = model.agents[id] { ChangeModelSheet(store: store, model: model, agent: agent) }
        case .appearance(let id):
            if let agent = model.agents[id] { AppearanceSheet(store: store, model: model, agent: agent) }
        case .reassign(let id):
            if let agent = model.agents[id] { ReassignSheet(store: store, model: model, agent: agent) }
        case .terminate(let id):
            if let agent = model.agents[id] { TerminateSheet(store: store, model: model, agent: agent) }
        case .pause, .stopRun, nil: EmptyView()
        }
    }
}

/// "N hires pending ›" (prototype `org.js` orgHires, 720): each proposed agent with who proposed it and its setup;
/// Approve / Reject / Details, as in Approvals.
struct PendingHiresSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var rejecting: ApprovalInfo?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let hires = model.agents.values.filter(\.isHirePending).sorted { $0.id < $1.id }
        AinkradSheetFrame(
            tile: "\(hires.count)", title: "Pending hires",
            line: "Proposed agents wait here — nothing runs until you approve. Rejecting tells the proposer why."
        ) {
            if hires.isEmpty {
                Text("No hires waiting.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    .frame(maxWidth: .infinity).padding(.vertical, skin.size.s20)
            }
            ForEach(hires) { agent in card(agent) }
        } foot: {
            Spacer()
            AinkradButton(title: "Close", style: .secondary) { model.orgPage.sheet = nil }.frame(
                minWidth: skin.size.s96
            )
            .fixedSize()
        }
        .overlay {
            if let approval = rejecting {
                PromptSheet(
                    title: "Reject \(model.agent(approval.agentID)?.name ?? "the hire")?",
                    message: "The proposer is told why; nothing is hired.", placeholder: "Why not (optional)",
                    confirmTitle: "Reject", isDestructive: true, allowsEmpty: true, text: "",
                    isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })
                ) { store.decideHire(approval, approve: false, reply: $0) }
                .background(
                    skin.color(.palette("background", skin.opacity.o97)),
                    in: RoundedRectangle(cornerRadius: skin.size.s14))
            }
        }
    }

    private func card(_ agent: AgentInfo) -> some View {
        let approval = model.hireApproval(of: agent.id)
        let team = model.team(of: agent.id)?.1
        let proposer = approval.flatMap { model.agent($0.requestedBy) }
        let chips =
            ["\(agent.harnessName) · \(agent.model)"]
            + (model.monthBudget(of: agent.id).map { ["\($0.capWord)\($0.isDollars ? "" : " tok") / month"] } ?? [])
            + ["reports to \(model.agent(agent.reportsTo)?.name ?? "—")"]
            + (agent.runnerTags.isEmpty ? [] : [agent.runnerTags.joined(separator: ", ")])
        return HStack(alignment: .center, spacing: skin.size.s14) {
            AgentFigure(agent: agent, model: model, size: skin.size.s48)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                    Text(agent.name).citadelFont("t14", weight: "semibold")
                    Text(agent.role.uppercased()).citadelFont("t9_5", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.faint))
                    if let team {
                        Text("· \(team.name)").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                Text("proposed by \(proposer?.name ?? "—")").citadelFont("t11").foregroundStyle(
                    skin.color(skin.text.muted))
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                            .padding(.horizontal, skin.size.s8).frame(height: skin.size.s22)
                            .background(
                                skin.color(.palette("foreground", skin.opacity.o06)),
                                in: RoundedRectangle(cornerRadius: skin.size.s6))
                    }
                }
                .padding(.top, skin.size.s6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: skin.size.s6) {
                if let approval {
                    AinkradButton(title: "Approve") { store.decideHire(approval, approve: true) }
                    AinkradDockButton("Reject", tone: .danger, height: skin.size.s34, fillsWidth: true) {
                        rejecting = approval
                    }
                    AinkradButton(title: "Details", style: .ghost) {
                        store.selectedApproval = approval.id
                        store.screen = .approvals
                        store.detail = nil
                        model.orgPage.sheet = nil
                    }
                    .borderless()
                }
            }
            .frame(width: skin.size.s96)
        }
        .padding(skin.size.s14)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }
}
