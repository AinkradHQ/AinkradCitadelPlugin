import AinkradAppKit
import SwiftUI

/// The docked decision above the composer (`.run-dec`): a permission escalation (Deny… / Allow for CIT-42 /
/// Allow once ↵) or a run about to stall (Stop now / Nudge).
struct RunDecision: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @State private var denying = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let who = model.agent(run.agentID)?.name ?? "the agent"
        if let approval = model.waitingApproval(run: run.id) {
            let key = model.issue(run.issueID)?.key
            card(tint: skin.color(skin.palette.warning), icon: "key", caption: "Permission escalation") {
                (Text("Let \(who) run ")
                    + Text(
                        " \(ToolLine.argument(approval.fields).isEmpty ? ToolLine.line(approval.fields) : ToolLine.argument(approval.fields)) "
                    ).font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"))))
            } actions: {
                AinkradDockButton("Deny…", height: skin.size.s30) { denying = true }
                if let key {
                    AinkradDockButton("Allow for \(key)", height: skin.size.s30) {
                        store.allowForIssue(approval, reply: nil)
                    }
                }
                AinkradDockButton("Allow once ↵", tone: .primary, height: skin.size.s30) {
                    store.decide(approval, approve: true)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .ainkradSheet(isPresented: $denying) {
                PromptSheet(
                    title: "Deny \(who)'s request?", message: "Your reason goes back to \(who) with the denial.",
                    placeholder: "Reason (optional)", confirmTitle: "Deny", isDestructive: true, allowsEmpty: true,
                    text: "", isPresented: $denying
                ) { store.decide(approval, approve: false, reply: $0) }
            }
        } else if model.look(run).key == "stalled" {
            card(tint: skin.color(skin.palette.danger), icon: "pause", caption: "About to stall") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(silentLine(context.date))
                }
            } actions: {
                AinkradDockButton("Stop now", tone: .danger, height: skin.size.s30) { store.stopWithToast(run) }
                AinkradDockButton(
                    "Nudge \(model.agent(run.agentID)?.name ?? "")", tone: .primary, height: skin.size.s30
                ) {
                    store.nudge(run: run)
                }
            }
        }
    }

    /// "silent 9m 20s · watchdog at 10m".
    private func silentLine(_ now: Date) -> String {
        let silent = now.timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
        let limit = model.limit("run.stall_after_secs", project: model.issue(run.issueID)?.projectID)?.value
        return "silent \(Fmt.duration(silent))\(limit.map { " · watchdog at \($0 / 60)m" } ?? "")"
    }

    private func card(
        tint: Color, icon: String, caption: String, @ViewBuilder title: () -> some View,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return HStack(spacing: skin.size.s12) {
            AinkradIconTile(systemName: icon, tint: tint, size: skin.size.s36, radius: skin.size.s11)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(caption.uppercased()).citadelFont("t10_5", weight: "semibold").tracking(skin.size.s1 / 2)
                    .foregroundStyle(tint)
                title().citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(2)
            }
            Spacer(minLength: skin.size.s8)
            actions()
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(shape.fill(skin.color(.palette("surface", skin.opacity.o95))))
        .background(shape.fill(tint.opacity(skin.opacity.o08)))
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o40), lineWidth: 1))
        .shadow(color: tint.opacity(skin.opacity.o10), radius: skin.size.s12)
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s8)
    }
}

/// `.rq-composer`: the agent's orb, the message field, attach (soon) and send; the hint line under it.
struct RunComposer: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    let sent: () -> Void
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let agent = model.agent(run.agentID)
        let name = agent?.name ?? "the agent"
        VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(alignment: .top, spacing: skin.size.s10) {
                if let agent {
                    AgentFigure(agent: agent, model: model, size: skin.size.s28).padding(.top, skin.size.s8)
                }
                AinkradComposer(
                    text: $draft, placeholder: "Message \(name) — delivered at its next turn (it keeps running)",
                    isEditable: true, canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    autoFocus: false, suggestions: { _ in [] }, onPick: { _, _ in }, onDrop: nil,
                    onSend: {
                        store.message(run: run.id, draft) {
                            draft = ""
                            sent()
                        }
                    },
                    chips: { EmptyView() },
                    leading: { EmptyView() },
                    trailing: {
                        AinkradIconButton(systemName: "paperclip", size: skin.size.s34, tooltip: "Attach (soon)") {
                            store.toast(
                                AinkradRichToast(title: "Attachments are coming", body: "Not in this version yet"))
                        }
                    }
                )
            }
            Text("↵ sends to \(name) at its next turn · ⇧↵ new line · the run keeps going").citadelFont("t10_5")
                .foregroundStyle(skin.color(skin.text.faint))
                .padding(.leading, skin.size.s38)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
    }
}

/// `.run-end`: an ended run's summary in place of the composer — glyph, what happened, duration / tokens / cost,
/// and Retry (or Raise the cap), Artifacts, Open the issue.
struct RunEndSummary: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let look = model.look(run)
        let tint = Hue(look.tone).color(skin)
        let (title, reason) = summary(look)
        let issue = model.issue(run.issueID)
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s14) {
                Text(look.glyph).citadelFont("t18", weight: "bold").foregroundStyle(tint)
                    .frame(width: skin.size.s44, height: skin.size.s44)
                    .background(tint.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s13))
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(title).citadelFont("t14", weight: "semibold").foregroundStyle(tint)
                    Text(reason).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: skin.size.s6) {
                    kpi(RunLook.span(model.elapsed(run)), "duration")
                    kpi(Fmt.tokens(run.tokens), "tokens")
                    kpi(model.cost(run).word, "cost")
                }
            }
            HStack(spacing: skin.size.s6) {
                if look.key == "cap_hit" {
                    AinkradDockButton("Raise the cap", tone: .primary) { store.goLimits() }
                } else if look.key != "succeeded", run.runnerID != nil {
                    AinkradDockButton("Retry run", tone: .primary) { store.retry(run: run) }
                }
                AinkradDockButton("Artifacts") {
                    model.artifactsPage.filter = ArtifactFilter(issueID: run.issueID)
                    store.go(.artifacts)
                }
                if let issue {
                    AinkradDockButton("Open \(issue.key)") {
                        if let requirement = issue.requirementID {
                            store.goRequirement(requirement)
                        } else {
                            store.open(.agent(run.agentID))
                        }
                    }
                }
            }
            .padding(.leading, skin.size.s56 + skin.size.s2)
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s14)
        .background(shape.fill(skin.color(.palette("surface", skin.opacity.o92))))
        .background(
            shape.fill(
                LinearGradient(
                    colors: [tint.opacity(skin.opacity.o12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o32), lineWidth: 1))
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
    }

    private func kpi(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).citadelFont("t13", weight: "semibold", mono: true).foregroundStyle(
                skin.color(skin.text.primary))
            Text(label).citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s6)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s10))
    }

    /// The prototype's end table (`runSummary`), worded from what the server recorded.
    private func summary(_ look: RunLook) -> (String, String) {
        let reason = run.terminalReason.flatMap { $0.isEmpty ? nil : $0 }
        switch look.key {
        case "succeeded":
            let files = run.diffRepos.reduce(0) { $0 + $1.files }
            return (
                "Succeeded",
                files > 0
                    ? "Changed \(Wording.count(files, "file")) across \(Wording.count(run.diffRepos.count, "repo"))."
                    : "The run finished cleanly."
            )
        case "runner_lost":
            let runner = run.runnerID.flatMap { model.runners[$0] } ?? "The runner"
            let at = run.endedAt.map { " at \(ArtifactsWhen.short($0, now: $0.addingTimeInterval(300)))" } ?? ""
            return (
                "Runner lost",
                "\(runner) stopped heartbeating\(at). Retry budget used — the issue waits in Why stuck."
            )
        case "cap_hit":
            return ("Stopped at the token cap", "The runner killed the harness at the cap. Raise the cap to resume.")
        case "cancelled": return ("Stopped", "The worktree and branch are kept; nothing is merged.")
        case "stopped":
            return ("Stopped · stalled", reason ?? "No activity past the stall limit — escalated to the lead.")
        case "timed_out": return ("Timed out", reason ?? "It ran past its time limit.")
        default: return ("Failed", reason ?? "The run ended with an error.")
        }
    }
}
