import AinkradAppKit
import SwiftUI

/// One diagnosis card (`.wsk`): the owner's orb with a severity badge, key + title and the age chip, the reason
/// (bold) and the detail, the evidence trail, then the fixes — the recommended one first, tinted, with its one-line
/// reason. Nudge opens inline in the card. Red for stuck, amber for slowing or a live run about to stall.
struct StuckCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let stuck: StuckInfo
    @State private var hovering = false
    @State private var busy: String?
    @State private var nudging = false
    @State private var nudge = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var issue: IssueInfo? { model.issue(stuck.issueID) }
    private var agent: AgentInfo? { model.agent(stuck.agentID) }
    /// The issue's live run, when there is one: its silence is the reason, a message is the fix.
    private var liveRun: RunInfo? {
        guard let id = stuck.issueID else { return nil }
        return model.runs.values.filter { $0.issueID == id && $0.isLive }.max { $0.id < $1.id }
    }
    private var isWarn: Bool { stuck.isSlowing || liveRun != nil }
    private var tint: Color { isWarn ? skin.color(skin.palette.warning) : skin.color(skin.palette.danger) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        HStack(alignment: .top, spacing: skin.size.s14) {
            avatar
            VStack(alignment: .leading, spacing: skin.size.s6) {
                titleRow
                (Text(sentence(stuck.reason)).foregroundStyle(skin.color(skin.text.primary)).bold()
                    + Text(" \(sentence(stuck.action, capitalized: false))").foregroundStyle(
                        skin.color(skin.text.muted)))
                    .citadelFont("t12_5").lineSpacing(skin.size.s3).fixedSize(horizontal: false, vertical: true)
                StuckTrail(model: model, stuck: stuck, liveRun: liveRun, isWarn: isWarn)
                    .padding(.vertical, skin.size.s2)
                if nudging, let run = liveRun { inlineNudge(run) } else { fixes.padding(.top, skin.size.s4) }
            }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.size.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o28), lineWidth: 1))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(bottomTrailingRadius: skin.size.s3, topTrailingRadius: skin.size.s3)
                .fill(tint).frame(width: skin.size.s3)
                .shadow(color: tint, radius: skin.size.s6)
                .padding(.vertical, skin.size.s14)
        }
        .shadow(
            color: skin.color(skin.palette.black).opacity(hovering ? skin.opacity.o30 : 0), radius: skin.size.s18,
            y: skin.size.s14
        )
        .overlay(shape.strokeBorder(tint.opacity(hovering ? skin.opacity.o35 : 0), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: nudging)
        .onChange(of: store.actionFailure?.title) { _, failure in if failure != nil { busy = nil } }
    }

    private var fill: some ShapeStyle {
        guard !stuck.isSlowing else {
            return AnyShapeStyle(skin.color(.palette("foreground", skin.opacity.o03)))
        }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(skin.opacity.o08), location: 0),
                    .init(color: skin.color(.palette("background", skin.opacity.o50)), location: 0.45),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: - Head

    private var avatar: some View {
        AinkradTapArea(
            help: agent.map { "Open \($0.name)" }, action: { if let id = stuck.agentID { store.open(.agent(id)) } }
        ) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s48) } else { Color.clear }
                }
                .frame(width: skin.size.s52, height: skin.size.s52)
                SeverityBadge(tint: tint, systemImage: isWarn ? "clock" : "flag.fill", pulses: !isWarn)
                    .offset(x: skin.size.s4, y: skin.size.s4)
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: skin.size.s8) {
            if let issue {
                Text(issue.key).citadelFont("t13", weight: "semibold", mono: true).foregroundStyle(
                    theme.accentSecondary)
            }
            Text(issue?.title ?? stuck.kind.replacingOccurrences(of: "_", with: " "))
                .citadelFont("t14", weight: "semibold").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Spacer(minLength: skin.size.s8)
            if let since = stuck.since {
                Text(ageWord(Date().timeIntervalSince(since))).citadelFont("t11", weight: "semibold", mono: true)
                    .foregroundStyle(tint)
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s3)
                    .background(tint.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s7))
            }
        }
    }

    /// "2h", "in review 5h", "blocked 1d".
    private func ageWord(_ seconds: TimeInterval) -> String {
        let age = Fmt.age(seconds)
        switch issue?.state {
        case "in_review": return "in review \(age)"
        case "blocked": return "blocked \(age)"
        default: return age
        }
    }

    // MARK: - Fixes

    @ViewBuilder private var fixes: some View {
        let lead = model.lead(ofProject: issue?.projectID)
        AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
            if stuck.waitsOnASleepingRunner {
                TintDockButton(title: "Wake my Mac", tint: tint, busyTitle: busy) {
                    busy = "Waking…"
                    store.wakeFix(stuck, when: "now")
                }
                AinkradDockButton("Run when I'm back") { store.wakeFix(stuck, when: "when_back") }
                AinkradDockButton("Allow Power Nap runs") { store.powerNapFix(stuck) }
            } else if let run = liveRun {
                TintDockButton(title: "Nudge \(agent?.name ?? "the agent")", tint: tint) {
                    nudge = "You've been quiet for a while — post what you're stuck on, or carry on."
                    nudging = true
                }
                reassignMenu(title: "Reassign")
                AinkradDockButton("Open run") { store.open(.run(run.id)) }
            } else {
                recommended(lead: lead)
                if stuck.issueID != nil { reassignMenu(title: "Reassign") }
                if stuck.retries, retryRunners.count > (primaryRetry == nil ? 0 : 1) {
                    AinkradMenuButton(
                        items: retryRunners.map { runner in
                            AinkradMenuItem(title: "Retry on \(runner.name)", systemName: nil) {
                                store.retryFix(stuck, on: runner)
                            }
                        }
                    ) { DockLabel(title: "Retry on…") }
                }
                if ["run_queued_no_lease", "checkout_dead", "runner_disk_full"].contains(stuck.kind) {
                    AinkradDockButton("Open runner") { store.screen = .runners }
                }
            }
            if stuck.issueID != nil, stuck.isSlowing {
                AinkradDockButton("Bump priority") { store.engineFix(stuck, "bump") }
            }
            if stuck.issueID != nil, !stuck.isSlowing, liveRun == nil, !stuck.waitsOnASleepingRunner {
                AinkradDockButton("Move to backlog") { store.engineFix(stuck, "backlog") }
            }
            let why = why(lead: lead)
            if !why.isEmpty {
                HStack(spacing: skin.size.s6) {
                    Image(systemName: "sparkle").citadelFont("t11").foregroundStyle(
                        skin.color(skin.palette.accentViolet))
                    Text(why).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                .frame(height: skin.size.s34)
                .padding(.leading, skin.size.s6)
            }
        }
    }

    private func reassignMenu(title: String) -> some View {
        AinkradMenuButton(
            items: model.agents.values.filter { $0.status == "active" && $0.id != stuck.agentID }
                .sorted { $0.name < $1.name }
                .map { agent in
                    AinkradMenuItem(title: agent.nameDotRole, systemName: nil) { store.reassignFix(stuck, to: agent) }
                }
        ) { DockLabel(title: title) }
    }

    /// The online runners that hold every tag the waiting agent needs.
    private var retryRunners: [RunnerInfo] {
        let tags = Set(agent?.runnerTags ?? [])
        return model.runnersPage.runners.filter { $0.status == "online" && tags.isSubset(of: $0.tags) }
    }

    /// A requeue that a healthy runner can take now: "Retry on hetzner-1" leads.
    private var primaryRetry: RunnerInfo? {
        guard stuck.retries, ["requeue", "rewake"].contains(stuck.repair ?? "") else { return nil }
        return retryRunners.first
    }

    /// The engine's recommendation as the tinted fix, when the server takes it; otherwise disabled with why.
    @ViewBuilder private func recommended(lead: AgentInfo?) -> some View {
        if let runner = primaryRetry {
            TintDockButton(title: "Retry on \(runner.name)", tint: tint, busyTitle: busy) {
                busy = "Retrying…"
                store.retryFix(stuck, on: runner)
            }.fixedSize()
        } else {
            switch stuck.repair {
            case "unblock" where stuck.issueID != nil:
                TintDockButton(title: "Unblock", tint: tint) { store.engineFix(stuck, "unblock") }
            case "reassign_to_lead", "escalate":
                if let lead, stuck.issueID != nil {
                    TintDockButton(title: "Reassign to \(lead.name)", tint: tint) { store.reassignFix(stuck, to: lead) }
                }
            case "rewake" where stuck.issueID != nil, "requeue" where stuck.issueID != nil:
                TintDockButton(title: "Wake \(agent?.name ?? "the agent") again", tint: tint) {
                    store.engineFix(stuck, "rewake")
                }
            case "release_checkout" where stuck.issueID != nil:
                TintDockButton(title: "Release checkout", tint: tint) { store.engineFix(stuck, "release_checkout") }
            case let repair?:
                // drop_wake / notify have no manual endpoint; the engine runs them by itself.
                AinkradDockButton(repair.replacingOccurrences(of: "_", with: " ").capitalized, isEnabled: false) {}
                    .ainkradTooltip("The engine does this by itself")
            case nil: EmptyView()
            }
        }
    }

    private func why(lead: AgentInfo?) -> String {
        if stuck.waitsOnASleepingRunner { return "Wake sends a push to the sleeping runner" }
        if liveRun != nil { return "a message resets the watchdog" }
        if let runner = primaryRetry { return "\(runner.name) is online with the tags \(agent?.name ?? "it") needs" }
        return switch stuck.repair {
        case "rewake", "requeue": "the engine recommends waking its next actor again"
        case "reassign_to_lead", "escalate": lead.map { "the engine recommends \($0.name), the team lead" } ?? ""
        case "unblock": "its blockers are closed"
        case "release_checkout": "its run ended without letting go of it"
        case let repair?: "the engine will \(repair.replacingOccurrences(of: "_", with: " ")) on its own"
        case nil: ""
        }
    }

    // MARK: - Inline nudge

    private func inlineNudge(_ run: RunInfo) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s8) {
            AinkradTextArea(
                text: $nudge, placeholder: "Your message", minHeight: skin.size.s40, maxHeight: skin.size.s120)
            HStack(spacing: skin.size.s6) {
                Text("Delivered at \(agent?.name ?? "the agent")'s next turn · resets the watchdog")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s8)
                AinkradDockButton("Cancel") { nudging = false }
                AinkradDockButton("Send nudge", tone: .primary) {
                    store.nudgeFix(stuck, run: run.id, text: nudge)
                    nudging = false
                }
            }
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o90))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o09)), lineWidth: 1))
        .padding(.top, skin.size.s6)
        .riseIn(distance: skin.size.s14)
    }

    private func sentence(_ text: String, capitalized: Bool = true) -> String {
        guard let first = text.first else { return text }
        let capped = capitalized ? first.uppercased() + text.dropFirst() : text
        return capped.hasSuffix(".") ? capped : capped + "."
    }
}
