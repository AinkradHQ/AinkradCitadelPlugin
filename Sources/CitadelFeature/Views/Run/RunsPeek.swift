import AinkradAppKit
import SwiftUI

/// The Runs peek drawer (`runsDrawer`): hero, the numbers, why it ended, token mix and startup, the steps it took,
/// files changed, where it ran; Stop / Retry, the agent, Open transcript.
struct RunsPeek: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Binding var confirmsStop: Bool
    @Environment(\.ainkradSkin) private var skin

    private var agent: AgentInfo? { model.agent(run.agentID) }
    private var look: RunLook { model.look(run) }
    private var tint: Color { Hue(look.tone).color(skin) }
    private var colors: (Color, Color) {
        agent?.washColors(skin) ?? (skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentPrimary))
    }

    var body: some View {
        AinkradDrawerPanel(
            contentID: run.id, onClose: { store.peek(run: nil) },
            header: { AinkradDrawerCrumb(["Runs", "#\(run.id)"]) }
        ) {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                hero
                kpis
                if let why = look.why(run) { whyBlock(why) }
                HStack(alignment: .top, spacing: skin.size.s8) {
                    RunPanel { tokenMix }
                    RunPanel { startup }
                }
                .fixedSize(horizontal: false, vertical: true)
                PeekSteps(model: model, run: run)
                files
                context
            }
        } footer: {
            foot
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let issue = model.issue(run.issueID)
        let cap = model.cap(of: run)
        return HStack(spacing: skin.size.s16) {
            if let agent {
                AgentFigure(agent: agent, model: model, size: skin.size.s64, isActive: look.isLive)
                    .frame(width: skin.size.s80, height: skin.size.s80)
                    .background(
                        skin.color(.palette("black", skin.opacity.o18)),
                        in: RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
                            .strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: skin.size.s6) {
                OutcomeChip(text: look.word, tint: tint, glyph: look.glyph)
                (Text(issue.map { "\($0.key) " } ?? "")
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", weight: "semibold", mono: "family")))
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    + Text(issue?.title ?? model.runTitle(run)).foregroundStyle(skin.color(skin.text.primary)))
                    .citadelFont("t16", weight: "bold").lineLimit(2)
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                    if let agent {
                        RunMetaChip(action: { store.open(.agent(agent.id)) }) {
                            AgentFigure(agent: agent, model: model, size: skin.size.s16)
                            Text("\(agent.name) · \(agent.role)")
                        }
                    }
                    AinkradBadge(
                        text: AgentLook.harnessName(run.harness),
                        tint: AgentLook.harness(run.harness)?.color ?? skin.color(skin.text.primary))
                    if let modelName = run.model ?? agent?.model {
                        RunMetaChip { Text(modelName).citadelFont("t11", mono: true) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let cap, cap > 0 {
                let fraction = Double(run.tokens) / Double(cap)
                VStack(spacing: skin.size.s4) {
                    AinkradRingGauge(
                        value: fraction, tint: ringTint(fraction), diameter: skin.size.s72, lineWidth: skin.size.s7
                    ) {
                        Text("\(Int(min(fraction, 1) * 100))%").citadelFont("t14", weight: "semibold", mono: true)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                    Text("of \(Fmt.tokens(cap)) cap").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
            }
        }
        .padding(skin.size.s18)
        .runWash(colors, radius: skin.size.s20)
    }

    private func ringTint(_ fraction: Double) -> Color {
        fraction >= 1
            ? skin.color(skin.palette.danger)
            : fraction >= model.warnFraction ? skin.color(skin.palette.warning) : colors.0
    }

    // MARK: - Numbers

    private var kpis: some View {
        let cost = model.cost(run)
        let cap = model.cap(of: run)
        return HStack(spacing: skin.size.s8) {
            if look.isLive {
                KpiTile(icon: "clock", tint: Hue.cyan.color(skin), label: "running for") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Fmt.duration(model.elapsed(run, now: context.date)))
                    }
                }
                KpiTile(icon: "text.alignleft", tint: Hue.violet.color(skin), label: "tokens") {
                    Text("\(Fmt.tokens(run.tokens))\(cap.map { " / \(Fmt.tokens($0))" } ?? "")")
                }
                KpiTile(icon: "dollarsign", tint: Hue.green.color(skin), label: "cost so far") { Text(cost.word) }
            } else {
                KpiTile(icon: "clock", tint: Hue.cyan.color(skin), label: "duration") {
                    Text(RunLook.span(model.elapsed(run)))
                }
                KpiTile(icon: "text.alignleft", tint: Hue.violet.color(skin), label: "tokens") {
                    Text(Fmt.tokens(run.tokens))
                }
                KpiTile(icon: "dollarsign", tint: Hue.green.color(skin), label: "cost") { Text(cost.word) }
            }
            KpiTile(icon: "server.rack", tint: Hue.amber.color(skin), label: "runner") {
                Text(run.runnerID.flatMap { model.runners[$0] } ?? "—").citadelFont(
                    "t15", weight: "semibold", mono: true)
            }
        }
    }

    private func whyBlock(_ why: String) -> some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            Text(look.glyph).citadelFont("t12", weight: "bold").foregroundStyle(tint)
                .frame(width: skin.size.s28, height: skin.size.s28)
                .background(tint.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s8))
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(look.word).citadelFont("t12", weight: "bold").foregroundStyle(tint)
                Text(why).citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .background(
            tint.opacity(skin.opacity.o09), in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
                .strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
    }

    @ViewBuilder private var tokenMix: some View {
        RunCardHead(title: "Token mix", value: Fmt.tokens(run.tokens))
        AinkradLegendBar(segments: RunMix.tokens(run, skin: skin))
    }

    @ViewBuilder private var startup: some View {
        let stages = StageTimings(run: run)
        RunCardHead(title: "Startup", value: stages.total.map { String(format: "%.1f s to first token", $0) })
        if stages.rows.isEmpty {
            Text("no stamps yet").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else {
            AinkradLegendBar(segments: RunMix.stages(stages, skin: skin))
        }
    }

    /// Per-file from the transcript's Edit / Write calls when loaded, else per repo (MISSING S4).
    @ViewBuilder private var files: some View {
        let edited: [(name: String, dir: String, added: Int64, removed: Int64)] = Transcript.items(
            model.transcripts[run.id] ?? [], runState: run.state
        ).compactMap { item in
            guard case .tool(let call) = item, call.status != .running, ["Edit", "Write"].contains(call.name) else {
                return nil
            }
            var raw = call.argument
            for prefix in ["citadel/", "ainkrad-citadel-plugin/"] where raw.hasPrefix(prefix) {
                raw = String(raw.dropFirst(prefix.count))
            }
            let parts = raw.split(separator: "/").map(String.init)
            let name = parts.last ?? raw
            let dir = parts.dropLast().joined(separator: "/")
            var added: Int64 = 6
            var removed: Int64 = 0
            if case .counts(let a, let r) = call.result {
                added = Int64(a)
                removed = Int64(r)
            }
            return (name: name, dir: dir, added: added, removed: removed)
        }
        if !edited.isEmpty {
            RunPanel {
                RunCardHead(title: "Files changed", aside: "\(edited.count)")
                ForEach(Array(edited.enumerated()), id: \.offset) { _, file in
                    DiffRow(name: file.name, detail: file.dir, insertions: file.added, deletions: file.removed)
                }
            }
        } else if !run.diffRepos.isEmpty {
            RunPanel {
                RunCardHead(title: "Files changed", aside: "\(run.diffRepos.reduce(0) { $0 + $1.files })")
                ForEach(run.diffRepos, id: \.repo) { diff in
                    DiffRow(
                        name: diff.repo, detail: Wording.count(diff.files, "file"), insertions: diff.insertions,
                        deletions: diff.deletions)
                }
            }
        }
    }

    private var context: some View {
        let issue = model.issue(run.issueID)
        let project = model.projects.first { $0.id == issue?.projectID }
        let requirement = model.requirements.first { $0.id == issue?.requirementID }
        let branch =
            run.issueID.flatMap { model.issuePRs[$0]?.first?.head }
            ?? issue.map { "feat/\($0.key.lowercased())" }
        let tint = colors.0
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: skin.size.s8), GridItem(.flexible())], spacing: skin.size.s8
        ) {
            if let account = run.accountID.flatMap({ model.accounts[$0] }) {
                ContextTile(
                    icon: "key", tint: tint, label: "Account", value: Text(account.label).monospaced(),
                    action: { store.go(.accounts) })
            }
            if let branch {
                ContextTile(
                    icon: "arrow.triangle.branch", tint: tint, label: "Branch", value: Text(branch).monospaced())
            }
            if let project {
                ContextTile(
                    icon: "square.split.2x1", tint: tint, label: "Project", value: Text(project.name),
                    action: { store.go(.projects) })
            }
            if let requirement {
                ContextTile(
                    icon: "list.bullet", tint: tint, label: "Requirement",
                    value: Text(requirement.key).foregroundStyle(skin.color(skin.palette.accentSecondary)),
                    action: { store.goRequirement(requirement.id) })
            }
        }
    }

    // MARK: - Footer

    private var foot: some View {
        HStack(spacing: skin.size.s8) {
            if look.isLive {
                AinkradDockButton("Stop run", systemImage: "stop", tone: .danger) { confirmsStop = true }
            } else if look.key == "cap_hit" {
                AinkradDockButton("Raise the cap", systemImage: "arrow.up.circle") { store.goLimits() }
            } else if look.key != "succeeded", run.runnerID != nil {
                AinkradDockButton("Retry run", systemImage: "arrow.clockwise") { store.retry(run: run) }
            }
            Spacer(minLength: skin.size.s8)
            if let agent {
                AinkradTapArea(action: { store.open(.agent(agent.id)) }) {
                    HStack(spacing: skin.size.s6) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s16)
                        Text(agent.name).citadelFont("t12", weight: "medium")
                    }
                    .foregroundStyle(skin.color(skin.text.primary))
                    .padding(.horizontal, skin.size.s12)
                    .frame(height: skin.size.s34)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o07)),
                        in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                            .strokeBorder(skin.color(.palette("foreground", skin.opacity.o09)), lineWidth: 1))
                }
            }
            AinkradDockButton("Open transcript", systemImage: "text.alignleft", tone: .primary) {
                store.peek(run: nil)
                store.open(.run(run.id))
            }
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s12)
        .background(skin.color(.palette("foreground", skin.opacity.o03)))
    }
}

/// The token-mix and startup segments, in the prototype's colours.
enum RunMix {
    static func tokens(_ run: RunInfo, skin: AinkradSkin) -> [AinkradLegendSegment] {
        [
            AinkradLegendSegment(
                label: "Input", value: Double(run.inputTokens), text: Fmt.tokens(run.inputTokens),
                color: Hue.blue.color(skin)),
            AinkradLegendSegment(
                label: "Cached", value: Double(run.cacheTokens), text: Fmt.tokens(run.cacheTokens),
                color: Hue.violet.color(skin)),
            AinkradLegendSegment(
                label: "Output", value: Double(run.outputTokens), text: Fmt.tokens(run.outputTokens),
                color: Hue.cyan.color(skin)),
        ]
    }

    static func stages(_ stages: StageTimings, skin: AinkradSkin) -> [AinkradLegendSegment] {
        let hues: [Hue] = [.violet, .blue, .cyan, .green]
        return stages.rows.enumerated().map {
            AinkradLegendSegment(
                label: $0.element.name, value: $0.element.seconds, text: String(format: "%.1fs", $0.element.seconds),
                color: hues[$0.offset % hues.count].color(skin))
        }
    }
}

/// `.rsd-file`: a name (with a faint detail), `+a −r`, and the green/red ratio bar.
struct DiffRow: View {
    let name: String
    var detail: String?
    let insertions: Int64
    let deletions: Int64
    var barWidth: CGFloat?
    var stacked = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s12) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).foregroundStyle(skin.color(skin.text.primary))
                        if let detail {
                            Text(detail).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                } else {
                    HStack(spacing: skin.size.s8) {
                        Text(name).foregroundStyle(skin.color(skin.text.primary))
                        if let detail { Text(detail).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint)) }
                    }
                }
            }
            .citadelFont(stacked ? "t11" : "t12", mono: true)
            .lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            (Text("+\(insertions)").foregroundStyle(skin.color(skin.palette.success)) + Text(" ")
                + Text("−\(deletions)").foregroundStyle(skin.color(skin.palette.danger)))
                .citadelFont("t11", mono: true).fixedSize()
            GeometryReader { geo in
                let total = Double(max(insertions + deletions, 1))
                if insertions + deletions == 0 {
                    Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                } else {
                    HStack(spacing: skin.size.s1) {
                        Rectangle().fill(skin.color(skin.palette.success))
                            .frame(width: geo.size.width * Double(insertions) / total)
                        Rectangle().fill(skin.color(skin.palette.danger))
                    }
                }
            }
            .frame(width: barWidth ?? skin.size.s70, height: skin.size.s6)
            .clipShape(Capsule())
        }
    }
}
