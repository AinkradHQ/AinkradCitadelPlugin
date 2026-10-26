import AinkradAppKit
import SwiftUI

/// The run's rail (`runRail`), a column of cards: tokens against the cap (ring, rate, the mix), liveness, the issue
/// so far, the worktrees and their diffs, startup, a grid of where it ran, and every redaction.
struct RunRail: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var project: Int64? { model.issue(run.issueID)?.projectID }
    private var colors: (Color, Color) {
        model.agent(run.agentID)?.washColors(skin)
            ?? (skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentPrimary))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                tokens
                RunPanel(padding: skin.size.s12) {
                    RunCardHead(title: "Liveness")
                    livenessPill
                }
                issueSoFar
                worktrees
                startup
                RunRailContext(store: store, model: model, run: run, tint: colors.0)
                RunPanel(padding: skin.size.s12) {
                    RunCardHead(title: "Redacted in this run")
                    redactions
                }
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s16)
        }
        .frame(width: skin.size.s300)
        .frame(maxHeight: .infinity)
        .background(skin.color(.palette("foreground", skin.opacity.o03)))
    }

    // MARK: - Tokens vs run cap

    private var tokens: some View {
        let cap = model.cap(of: run)
        let meter = RunMeter(run: run, cap: cap, warnFraction: model.warnFraction)
        let fraction = cap.map { Double(run.tokens) / Double(max($0, 1)) }
        return RunPanel(padding: skin.size.s12) {
            HStack(spacing: skin.size.s12) {
                AinkradRingGauge(
                    value: fraction ?? 0, tint: ringTint(fraction ?? 0), diameter: skin.size.s64,
                    lineWidth: skin.size.s7
                ) {
                    Text(fraction.map { "\(Int(min($0, 1) * 100))%" } ?? "—").citadelFont(
                        "t13", weight: "semibold", mono: true
                    )
                    .foregroundStyle(skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text("\(Fmt.tokens(run.tokens)) / \(cap.map(Fmt.tokens) ?? "—")")
                        .citadelFont("t17", weight: "semibold")
                        .foregroundStyle(meter.level == .ok ? skin.color(skin.text.primary) : status.warning)
                    Text("tokens vs run cap").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    if cap != nil {
                        let own = model.limits["run.token_cap.agent.\(run.agentID)"] != nil
                        let source = model.limit("run.token_cap", project: project)?.source
                        CrumbLink(text: "↳ \(own ? "agent" : Self.scopeWord(source)) limit") { store.goLimits() }
                            .citadelFont("t11")
                    }
                }
            }
            if run.isLive {
                AinkradFlowLayout(spacing: skin.size.s5, lineSpacing: skin.size.s5) {
                    rateChip(meter.perMinute.map { "~\(Fmt.tokens(Int64($0))) / min" } ?? "paused")
                    rateChip(
                        meter.minutesLeft.map { "cap in ~\(max(1, Int($0.rounded(.up)))) min" } ?? "cap in —",
                        warn: meter.minutesLeft != nil)
                    rateChip(model.cost(run).word)
                }
            }
            AinkradLegendBar(segments: RunMix.tokens(run, skin: skin))
        }
    }

    /// `company`, `project`, `default`: where the cap was set (decision #52).
    static func scopeWord(_ source: String?) -> String {
        source?.split(separator: ":").first.map(String.init) ?? "default"
    }

    private func ringTint(_ fraction: Double) -> Color {
        fraction >= 1 ? status.danger : fraction >= model.warnFraction ? status.warning : colors.0
    }

    private func rateChip(_ text: String, warn: Bool = false) -> some View {
        Text(text).citadelFont("t10_5", mono: true)
            .foregroundStyle(warn ? status.warning : skin.color(skin.text.muted))
            .padding(.horizontal, skin.size.s8)
            .frame(height: skin.size.s22)
            .background(
                skin.color(.palette("foreground", skin.opacity.o06)), in: RoundedRectangle(cornerRadius: skin.size.s6))
    }

    // MARK: - Liveness

    /// `.alive`: running green, waiting amber, stalled red (ticking), ended idle.
    @ViewBuilder private var livenessPill: some View {
        let look = model.look(run)
        let stall = model.limit("run.stall_after_secs", project: project)
        if !run.isLive {
            if look.key == "runner_lost" {
                alive(tint: status.danger) {
                    Text("⚑")
                    Text("runner stopped heartbeating · lease expired after 30 s")
                }
            } else {
                alive(tint: nil) {
                    Text("ended \((run.endedAt ?? run.queuedAt).formatted(date: .omitted, time: .shortened))")
                }
            }
        } else if look.key == "waiting" {
            alive(tint: status.warning) {
                Circle().fill(status.warning).frame(width: skin.size.s7, height: skin.size.s7)
                Text("waiting on you · watchdog paused")
            }
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let silent = context.date.timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
                let fine = liveness(silentFor: silent, limit: stall.map { TimeInterval($0.value) }) == .fine
                let dog = stall.map { " · watchdog at \($0.value / 60)m" } ?? ""
                alive(tint: fine ? status.success : status.danger) {
                    Circle().fill(fine ? status.success : status.danger)
                        .frame(width: skin.size.s7, height: skin.size.s7)
                    Text(fine ? "last tool call \(Fmt.age(silent)) ago\(dog)" : "silent \(Fmt.duration(silent))\(dog)")
                }
            }
        }
    }

    private func alive(tint: Color?, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: skin.size.s8) { content() }
            .citadelFont("t11")
            .foregroundStyle(tint ?? skin.color(skin.text.muted))
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (tint?.opacity(skin.opacity.o08)) ?? skin.color(.palette("foreground", skin.opacity.o05)),
                in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
    }

    // MARK: - Issue, worktrees, startup

    @ViewBuilder private var issueSoFar: some View {
        if let issue = model.issue(run.issueID), let cost = model.issueCosts[issue.id] {
            let cap = model.limit("issue.token_cap", project: project)?.value
            RunPanel(padding: skin.size.s12) {
                RunCardHead(
                    title: "Issue \(issue.key) so far",
                    value: "\(Fmt.tokens(cost.tokens))\(cap.map { " / \(Fmt.tokens($0))" } ?? "")")
                if let cap {
                    AinkradBudgetBar(
                        label: "Issue tokens", value: Double(cost.tokens), limit: Double(cap),
                        warnFraction: model.warnFraction)
                }
                HStack(spacing: skin.size.s12) {
                    legend("Runs", "\(cost.runs)")
                }
            }
        }
    }

    private func legend(_ label: String, _ value: String) -> some View {
        HStack(spacing: skin.size.s5) {
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            Text(value).citadelFont("t10_5", weight: "medium", mono: true).foregroundStyle(
                skin.color(skin.text.primary))
        }
    }

    @ViewBuilder private var worktrees: some View {
        if let repos = run.issueID.flatMap({ model.issueRepos[$0] }), !repos.isEmpty {
            let prs = run.issueID.flatMap { model.issuePRs[$0] } ?? []
            RunPanel(padding: skin.size.s12) {
                RunCardHead(title: "Worktrees", value: prs.first?.head)
                ForEach(repos, id: \.self) { repo in
                    let diff = run.diffRepos.first { $0.repo == repo }
                    DiffRow(
                        name: repo, detail: prs.first { $0.repo == repo }.map { "→ \($0.base)" },
                        insertions: diff?.insertions ?? 0, deletions: diff?.deletions ?? 0, barWidth: skin.size.s46,
                        stacked: true)
                }
            }
        }
    }

    @ViewBuilder private var startup: some View {
        let stages = StageTimings(run: run)
        if !stages.rows.isEmpty {
            RunPanel(padding: skin.size.s12) {
                RunCardHead(title: "Startup", value: stages.total.map { String(format: "%.1f s to first token", $0) })
                AinkradLegendBar(segments: RunMix.stages(stages, skin: skin))
            }
        }
    }

    @ViewBuilder private var redactions: some View {
        let names = Set((model.transcripts[run.id] ?? []).flatMap { $0.fields.values.flatMap(Redaction.names) })
        if names.isEmpty {
            Text("nothing caught").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else {
            SecretChips(names: Array(names))
        }
    }
}

/// The rail's context grid: account, model, runner, sandbox, chain, requirement (or project).
private struct RunRailContext: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    /// "fallback" once the run left its first entry; else its position in the agent's resolved preset.
    private var chainWord: String {
        if run.fallbackReason != nil { return "fallback" }
        let agent = model.agent(run.agentID)
        guard let preset = model.chainPreset(agent?.chainPresetID) ?? model.defaultChainPreset else { return "entry 1" }
        return "entry 1 of \(preset.entries.count)"
    }

    var body: some View {
        let issue = model.issue(run.issueID)
        let policy = issue.flatMap { model.projectsPage.policies[$0.projectID] }
        let requirement = model.requirements.first { $0.id == issue?.requirementID }
        let project = model.projects.first { $0.id == issue?.projectID }
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: skin.size.s6), GridItem(.flexible())], spacing: skin.size.s6
        ) {
            if let account = run.accountID.flatMap({ model.accounts[$0] }) {
                ContextTile(
                    icon: "key", tint: tint, label: "Account", value: Text(account.label).monospaced(), compact: true,
                    action: { store.go(.accounts) })
            }
            let baseModel = run.model ?? model.agent(run.agentID)?.model ?? "—"
            let effort =
                model.agent(run.agentID)?.effort
                ?? (baseModel.contains("5.5") || baseModel.contains("Opus") ? "high" : "medium")
            ContextTile(
                icon: "scope", tint: tint, label: "Model",
                value: Text("\(baseModel) · \(effort)"),
                compact: true)
            if let runner = run.runnerID.flatMap({ model.runners[$0] }) {
                ContextTile(
                    icon: "server.rack", tint: tint, label: "Runner", value: Text(runner).monospaced(), compact: true,
                    action: { store.go(.runners) })
            }
            if let policy {
                ContextTile(
                    icon: "shield", tint: tint, label: "Sandbox",
                    value: Text(
                        policy.sandboxed ? "workspace-write" : policy.mode.replacingOccurrences(of: "_", with: " ")),
                    compact: true)
            }
            ContextTile(
                icon: "list.bullet", tint: tint, label: "Chain",
                value: Text(chainWord),
                compact: true)
            if let requirement {
                ContextTile(
                    icon: "square.split.2x1", tint: tint, label: "Requirement",
                    value: Text(requirement.key).foregroundStyle(skin.color(skin.palette.accentSecondary)),
                    compact: true,
                    action: { store.goRequirement(requirement.id) })
            } else if let project {
                ContextTile(
                    icon: "square.split.2x1", tint: tint, label: "Project", value: Text(project.name), compact: true,
                    action: { store.go(.projects) })
            }
        }
    }
}

/// The meter's arithmetic: level against the warn mark, burn rate, and minutes to the cap at that rate.
struct RunMeter {
    let level: AinkradBudgetLevel
    let perMinute: Double?
    let minutesLeft: Double?

    init(run: RunInfo, cap: Int64?, warnFraction: Double, now: Date = Date()) {
        let limit = Double(cap ?? 0)
        level = budgetBarState(value: Double(run.tokens), limit: limit, warnFraction: warnFraction).level
        let minutes = (run.endedAt ?? now).timeIntervalSince(run.startedAt ?? run.queuedAt) / 60
        let rate = minutes > 0 ? Double(run.tokens) / minutes : nil
        perMinute = rate
        if let rate, rate > 0, limit > 0, run.isLive {
            minutesLeft = max(0, (limit - Double(run.tokens)) / rate)
        } else {
            minutesLeft = nil
        }
    }
}

/// Wake → claim → workspace → harness → first token, from the run's stamps (E15.6).
struct StageTimings {
    /// The mockup's stage colours, in order: violet, accent, cyan, tertiary.
    static let tones: [AinkradChartTone] = [.accentViolet, .accentPrimary, .accentSecondary, .accentTertiary]

    let rows: [(name: String, seconds: Double)]
    let total: Double?

    init(run: RunInfo) {
        let marks: [(String, Date?)] = [
            ("Wake", run.claimedAt), ("Claim", run.startedAt), ("Setup", run.harnessStartedAt),
            ("First token", run.firstTokenAt),
        ]
        var previous = run.wokenAt ?? run.queuedAt
        var rows: [(String, Double)] = []
        for (name, date) in marks {
            guard let date else { break }
            rows.append((name, max(0, date.timeIntervalSince(previous))))
            previous = date
        }
        self.rows = rows
        total = run.firstTokenAt.map { $0.timeIntervalSince(run.wokenAt ?? run.queuedAt) }
    }
}
