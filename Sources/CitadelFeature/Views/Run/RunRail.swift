import AinkradAppKit
import SwiftUI

/// The run's rail: tokens against its cap (with where the cap was set), the issue so far, liveness against the
/// stall limit, its repos' worktrees, stage timings, account and model, the run itself, and every redaction.
struct RunRail: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var project: Int64? { model.issue(run.issueID)?.projectID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                meter
                issueSoFar
                live
                repos
                stages
                account
                runFacts
                redactions
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s14)
        }
        .frame(width: skin.size.s300)
        .frame(maxHeight: .infinity)
        .background(theme.surface.opacity(skin.opacity.o35))
    }

    // MARK: - Tokens vs run cap

    private var meter: some View {
        let cap = model.limit("run.token_cap", project: project)
        let meter = RunMeter(run: run, cap: cap?.value, warnFraction: model.warnFraction)
        return VStack(alignment: .leading, spacing: skin.size.s8) {
            RailLabel(title: "Tokens vs run cap")
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                Text(Fmt.tokens(run.tokens)).citadelFont("t24", weight: "semibold")
                    .foregroundStyle(meter.level == .ok ? skin.color(skin.text.primary) : status.warning)
                Text("/ \(Fmt.tokens(cap?.value ?? 0))").citadelFont("t13").foregroundStyle(skin.color(skin.text.muted))
                Spacer(minLength: skin.size.s4)
                if let cap { SourceChip(source: cap.source) }
            }
            AinkradBudgetBar(
                label: "Run tokens", value: Double(run.tokens), limit: Double(cap?.value ?? 0),
                warnFraction: model.warnFraction)
            VStack(spacing: skin.size.s4) {
                AinkradStatRow(
                    label: "Input", value: "\(Fmt.tokens(run.inputTokens)) · \(Fmt.tokens(run.cacheTokens)) cached"
                ).sentenceCaseLabel()
                AinkradStatRow(label: "Output", value: Fmt.tokens(run.outputTokens)).sentenceCaseLabel()
                AinkradStatRow(
                    label: "Cost", value: run.costMicros.map { "\(Fmt.dollars(micros: $0)) priced" } ?? "unpriced"
                ).sentenceCaseLabel()
                if let rate = meter.perMinute {
                    AinkradStatRow(label: "Rate", value: "~\(Fmt.tokens(Int64(rate))) / min").sentenceCaseLabel()
                }
                if let left = meter.minutesLeft {
                    AinkradStatRow(label: "Cap at this rate", value: "~\(Int(left.rounded(.up))) min", status: .warning)
                        .sentenceCaseLabel()
                }
            }
        }
    }

    @ViewBuilder private var issueSoFar: some View {
        if let issue = model.issue(run.issueID), let cost = model.issueCosts[issue.id] {
            RailLabel(title: "Issue \(issue.key) so far").padding(.top, skin.size.s6)
            AinkradStatRow(
                label: "All runs", value: "\(Fmt.tokens(cost.tokens)) tok · \(Wording.count(cost.runs, "run"))"
            )
            .sentenceCaseLabel()
            AinkradStatRow(label: "Spend", value: Fmt.dollars(micros: cost.costMicros)).sentenceCaseLabel()
        }
    }

    // MARK: - Liveness

    @ViewBuilder private var live: some View {
        if run.isLive {
            let stall = model.limit("run.stall_after_secs", project: project)
            RailLabel(title: "Liveness").padding(.top, skin.size.s6)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let silent = context.date.timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
                let state = liveness(silentFor: silent, limit: stall.map { TimeInterval($0.value) })
                HStack(spacing: skin.size.s6) {
                    Circle().fill(state == .fine ? theme.accentSecondary : status.danger)
                        .frame(width: skin.size.s7, height: skin.size.s7)
                    Text("last progress \(Fmt.age(silent)) ago").citadelFont("t12")
                        .foregroundStyle(state == .fine ? skin.color(skin.text.primary) : status.danger)
                    Spacer(minLength: skin.size.s4)
                    if let stall {
                        Text("stall \(stall.value / 60)m").citadelFont("t10_5", mono: true)
                            .foregroundStyle(theme.accentSecondary)
                        SourceChip(source: stall.source)
                    }
                }
            }
        }
    }

    // MARK: - Repos

    @ViewBuilder private var repos: some View {
        if let repos = run.issueID.flatMap({ model.issueRepos[$0] }), !repos.isEmpty {
            RailLabel(title: "Repos · \(repos.count) worktree\(repos.count == 1 ? "" : "s")").padding(
                .top, skin.size.s6)
            ForEach(repos, id: \.self) { repo in
                HStack(spacing: skin.size.s6) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(theme.accentSecondary)
                    Text(repo).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.primary))
                        .lineLimit(1).truncationMode(.middle)
                    if let diff = run.diffRepos.first(where: { $0.repo == repo }) {
                        (Text("+\(diff.insertions)").foregroundStyle(status.success) + Text(" ")
                            + Text("−\(diff.deletions)").foregroundStyle(status.danger))
                            .citadelFont("t11", mono: true).fixedSize()
                            .ainkradTooltip("\(diff.files) file\(diff.files == 1 ? "" : "s") changed against its base")
                    }
                    Spacer(minLength: skin.size.s4)
                    Text("PR on finish").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            if repos.count > 1 {
                Text("QA + merge cover every PR · done waits for all").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    // MARK: - Stage timings

    @ViewBuilder private var stages: some View {
        let stages = StageTimings(run: run)
        if !stages.rows.isEmpty {
            RailLabel(
                title: stages.total.map { "Stage timings · \(String(format: "%.1f", $0)) s to first token" }
                    ?? "Stage timings"
            )
            .padding(.top, skin.size.s6)
            AinkradStackedStatusBar(
                toneRuns: stages.rows.enumerated().map {
                    AinkradToneRun(
                        value: $0.element.seconds, tone: StageTimings.tones[$0.offset % StageTimings.tones.count])
                })
            ForEach(stages.rows, id: \.name) { row in
                AinkradStatRow(label: row.name, value: String(format: "%.1f s", row.seconds)).sentenceCaseLabel()
            }
        }
    }

    // MARK: - Account and model

    private var account: some View {
        VStack(alignment: .leading, spacing: skin.size.s4) {
            RailLabel(title: "Account & model").padding(.top, skin.size.s6)
            if let account = run.accountID.flatMap({ model.accounts[$0] }) {
                let window = account.windowUse.map { " · \(Int($0 * 100))%" } ?? ""
                AinkradStatRow(label: "Account", value: "\(account.label)\(window)").sentenceCaseLabel()
            }
            AinkradStatRow(label: "Model", value: run.model ?? "—").sentenceCaseLabel()
            AinkradStatRow(label: "Chain", value: run.fallbackReason == nil ? "primary" : "fallback")
                .sentenceCaseLabel()
            if let reason = run.fallbackReason {
                AinkradStatRow(label: "Fallback", value: reason, status: .warning).sentenceCaseLabel()
            }
        }
    }

    private var runFacts: some View {
        VStack(alignment: .leading, spacing: skin.size.s4) {
            RailLabel(title: "Run").padding(.top, skin.size.s6)
            AinkradStatRow(label: "State", value: run.endWord).sentenceCaseLabel()
            if let runner = run.runnerID.flatMap({ model.runners[$0] }) {
                AinkradStatRow(label: "Runner", value: runner).sentenceCaseLabel()
            }
            if let tier = run.harnessVersion { AinkradStatRow(label: "Harness", value: tier).sentenceCaseLabel() }
            if let requirement = model.issue(run.issueID)?.requirementID.flatMap({ id in
                model.requirements.first { $0.id == id }
            }) {
                AinkradStatRow(label: "Requirement", value: requirement.key).sentenceCaseLabel()
            }
            if let reason = run.terminalReason {
                AinkradStatRow(label: "Ended", value: reason, status: .danger).sentenceCaseLabel()
            }
        }
    }

    @ViewBuilder private var redactions: some View {
        let names = Set((model.transcripts[run.id] ?? []).flatMap { $0.fields.values.flatMap(Redaction.names) })
        if !names.isEmpty {
            RailLabel(title: "Redacted in this run").padding(.top, skin.size.s6)
            HStack(spacing: skin.size.s6) {
                ForEach(names.sorted(), id: \.self) {
                    AinkradRedactedChip($0, reason: "Redacted by the server before it was written to the log")
                }
            }
        }
    }
}

/// Where a limit was set (decision #52): `↳ company` inherited, `● project` set on the project.
private struct SourceChip: View {
    let source: String?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let scope = source?.split(separator: ":").first.map(String.init)
        if scope == "project" {
            AinkradBadge(text: "● project", tint: theme.accentSecondary)
        } else {
            AinkradBadge(text: "↳ \(scope ?? "default")")
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
            ("Wake → claimed", run.claimedAt), ("Setup · worktrees", run.startedAt),
            ("Harness up", run.harnessStartedAt), ("First token", run.firstTokenAt),
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
