import AinkradAppKit
import SwiftUI

/// Screen 10: one card per runner — its state and why, tags, disk split into shared caches, active and idle
/// worktrees, idle worktrees with their removal countdown, and its limits (server → runner, decision #57).
struct RunnersView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var adding = false

    private var page: RunnersPage { model.runnersPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Runners", crumb: crumb) {
                AinkradButton(title: "+ Add runner", style: .secondary) {
                    page.registered = nil
                    page.registerFailure = nil
                    adding = true
                }
                .secondaryAccent().compact().fixedSize()
                .ainkradTooltip("Registers a runner and shows its start command with a key, once")
            }
            ScrollView {
                if page.isLoaded && page.runners.isEmpty {
                    AinkradEmptyState(
                        icon: "cylinder.split.1x2", title: "No runners yet",
                        message: "A runner is a machine that takes work. Register one with its install command."
                    )
                    .frame(maxWidth: .infinity).padding(.top, skin.size.s60)
                } else if !page.isLoaded {
                    FirstLoadView()
                } else {
                    grid
                }
            }
            .offlineDimmed()
        }
        .task { store.loadRunnersPage() }
        // Open while a new runner's key is on screen, so it is never lost to a redraw.
        .ainkradSheet(
            isPresented: Binding(
                get: { adding || page.registered != nil },
                set: {
                    adding = $0
                    if !$0 { page.registered = nil }
                })
        ) { AddRunnerSheet(store: store, page: page, isPresented: $adding) }
        .ainkradSheet(
            isPresented: Binding(get: { page.log != nil }, set: { if !$0 { page.log = nil } })
        ) {
            RunnerLogSheet(
                name: page.runners.first { $0.id == page.log?.runner }?.name ?? "Runner",
                lines: page.log?.lines ?? []
            ) { page.log = nil }
        }
    }

    /// Two columns, each row as tall as its taller card (the mockup's `cols c2`).
    private var grid: some View {
        let rows = stride(from: 0, to: page.runners.count, by: 2).map {
            Array(page.runners[$0..<min($0 + 2, page.runners.count)])
        }
        return Grid(alignment: .topLeading, horizontalSpacing: skin.size.s14, verticalSpacing: skin.size.s14) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { runner in
                        RunnerCard(store: store, model: model, runner: runner, running: running[runner.id] ?? 0)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s20)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: page.runners)
    }

    /// Live runs per runner: the slot meters.
    private var running: [Int64: Int] {
        Dictionary(grouping: model.liveRuns.compactMap(\.runnerID), by: { $0 }).mapValues(\.count)
    }

    /// `1 online · 1 unhealthy · 1 asleep · 1 offline · 5 of 8 slots free · disk 87 GB used`.
    private var crumb: Text {
        let counts = page.counts
        let muted = skin.color(skin.text.muted)
        let dot = Text(verbatim: " · ").foregroundStyle(muted)
        var text = Text("\(counts.online) online").foregroundStyle(status.success)
        if counts.unhealthy > 0 {
            text = text + dot + Text("\(counts.unhealthy) unhealthy").foregroundStyle(status.danger)
        }
        if counts.asleep > 0 {
            text = text + dot + Text("\(counts.asleep) asleep").foregroundStyle(status.warning)
        }
        if counts.offline > 0 {
            text = text + dot + Text("\(counts.offline) offline").foregroundStyle(skin.color(skin.text.faint))
        }
        if let slots = page.freeSlots(running: running) {
            text = text + dot + Text("\(slots.free) of \(slots.total) slots free").foregroundStyle(muted)
        }
        if counts.diskUsed > 0 {
            text = text + dot + Text("disk \(ScopedSetting.bytes(counts.diskUsed)) used").foregroundStyle(muted)
        }
        return text
    }
}

/// One runner.
private struct RunnerCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let runner: RunnerInfo
    let running: Int
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @State private var confirmsRemove = false
    @State private var relogin = false

    private var disk: RunnerDiskInfo? { model.runnersPage.disk[runner.id] }

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                head
                if let reason = runner.reason(now: Date()) {
                    ReasonBlock(
                        title: reason.title, detail: reason.detail, tone: runner.status == "unhealthy" ? .danger : nil
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let drain = runner.drainLine(now: Date()) {
                    ReasonBlock(title: drain.title, detail: drain.detail, tone: .warning)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let wake = runner.wakeLine(now: Date()) {
                    ReasonBlock(title: wake.title, detail: wake.detail, tone: .warning)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !runner.tags.isEmpty {
                    HStack(spacing: skin.size.s6) {
                        ForEach(runner.tags, id: \.self) { AinkradBadge(text: $0, tint: theme.accentSecondary) }
                    }
                }
                if let slots = runner.slots, runner.status != "offline" { slotRow(slots) }
                if !runner.harnesses.isEmpty { harnessRows }
                if let disk { DiskSection(store: store, model: model, runner: runner, disk: disk) }
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rim(runner.status == "unhealthy" ? .danger : runner.state == "asleep" ? .warning : nil)
        .opacity(runner.state == "offline" ? skin.opacity.o80 : 1)
        .ainkradConfirmDialog(
            isPresented: $confirmsRemove, title: "Remove \(runner.name)?",
            message: "Its key stops working at once. Register it again to bring the machine back.",
            confirmTitle: "Remove", isDestructive: true
        ) { store.removeRunner(runner) }
        .ainkradSheet(isPresented: $relogin) { ReloginSheet(runner: runner, isPresented: $relogin) }
    }

    /// `SLOTS ▮▮▮▯ 3 running · heartbeat 2s ago · up 6d`.
    private func slotRow(_ slots: Int) -> some View {
        HStack(spacing: skin.size.s10) {
            Text(skin.labelCased("Slots")).citadelFont("t10", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted))
            AinkradStatusBar(
                value: Double(min(running, slots)), total: Double(max(slots, 1)), kind: .accent,
                segments: max(slots, 1)
            )
            .frame(width: CGFloat(max(slots, 1)) * skin.size.s18, height: skin.size.s6)
            Text(slotLine).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }

    private var slotLine: String {
        var parts = ["\(running) running"]
        if let seen = runner.lastSeenAt { parts.append("heartbeat \(Fmt.age(Date().timeIntervalSince(seen))) ago") }
        if let up = runner.uptime(now: Date()) { parts.append(up) }
        return parts.joined(separator: " · ")
    }

    /// Each harness: its version and whether it is logged in on the runner.
    private var harnessRows: some View {
        Grid(alignment: .leading, horizontalSpacing: skin.size.s10, verticalSpacing: skin.size.s3) {
            ForEach(runner.harnessRows, id: \.name) { row in
                GridRow {
                    Text(AgentLook.harnessName(row.name)).foregroundStyle(skin.color(skin.text.muted))
                    Text(row.version).citadelFont("t11_5", mono: true)
                    loginText(row.login).gridColumnAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .citadelFont("t11_5")
            }
        }
    }

    @ViewBuilder private func loginText(_ state: String?) -> some View {
        switch state {
        case "logged_in": Text("✓ logged in").foregroundStyle(status.success)
        case "logged_out": Text("✗ logged out").foregroundStyle(status.danger)
        case "unknown": Text("keychain login").foregroundStyle(skin.color(skin.text.faint))
        default: Text("")
        }
    }

    private var head: some View {
        HStack(alignment: .top, spacing: skin.size.s10) {
            Image(systemName: "cylinder.split.1x2")
                .citadelFont("t13")
                .foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(
                    skin.color(skin.palette.white).opacity(skin.opacity.o06),
                    in: RoundedRectangle(cornerRadius: skin.size.s8))
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(runner.name).citadelFont("t15", weight: "semibold")
                    .foregroundStyle(skin.color(runner.status == "offline" ? skin.text.muted : skin.text.primary))
                if let seen = runner.lastSeenAt, runner.status != "offline", runner.slots == nil {
                    Text("heartbeat \(Fmt.age(Date().timeIntervalSince(seen))) ago").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
            Spacer(minLength: skin.size.s8)
            pill.transition(.opacity).id(runner.status)
        }
    }

    @ViewBuilder private var pill: some View {
        switch runner.state {
        case "online" where runner.drainedAt != nil: AinkradBadge(text: "◐ drained", status: .warning)
        case "online": AinkradBadge(text: "● online", status: .success)
        case "unhealthy": AinkradBadge(text: "● unhealthy", status: .danger)
        case "asleep": AinkradBadge(text: "☾ asleep", status: .warning)
        default: AinkradBadge(text: "○ \(runner.status)")
        }
    }

    /// Actions follow the state: re-login, drain and the probe log when unhealthy; drain when online; wake and
    /// Power Nap when asleep; the last log and remove when offline.
    @ViewBuilder private var actions: some View {
        HStack(spacing: skin.size.s8) {
            switch runner.state {
            case "unhealthy":
                AinkradButton(title: "Re-login on server…", style: .primary) { relogin = true }.compact().fixedSize()
                    .disabled(runner.loggedOut.isEmpty)
                    .ainkradTooltip(
                        runner.loggedOut.isEmpty
                            ? "The runner reports no logged-out harness" : "The command to run on the runner's host")
                drainButton
                AinkradButton(title: "Probe log", style: .ghost) { store.showRunnerLog(runner) }.borderless()
                    .secondaryAccent().compact().fixedSize()
            case "online":
                drainButton
                AinkradButton(title: "Show log", style: .ghost) { store.showRunnerLog(runner) }.borderless()
                    .secondaryAccent().compact().fixedSize()
            case "asleep":
                AinkradButton(title: "Wake now", style: .primary) { store.wakeRunner(runner.id, when: "now") }
                    .compact().fixedSize()
                    .ainkradTooltip("Pushes a wake to the Mac; its queued work starts when it connects")
                AinkradButton(
                    title: runner.powerNap == true ? "Keeping awake while jobs queue" : "Keep awake while jobs queue",
                    style: runner.powerNap == true ? .primary : .secondary
                ) { store.setPowerNap(runner, runner.powerNap != true) }
                .secondaryAccent().compact().fixedSize()
                .ainkradTooltip(powerNapTip)
            default:
                AinkradButton(title: "Show last log", style: .secondary) { store.showRunnerLog(runner) }
                    .secondaryAccent().compact().fixedSize()
                AinkradButton(title: "Remove runner…", style: .ghost) { confirmsRemove = true }.borderless()
                    .secondaryAccent().compact().fixedSize()
            }
        }
        if let failure = model.runnersPage.failures[runner.id] { RefusalLine(failure: failure) }
    }

    @ViewBuilder private var drainButton: some View {
        if runner.drainedAt == nil {
            AinkradButton(title: "Drain", style: .secondary) { store.setDrained(runner, true) }
                .secondaryAccent().compact().fixedSize()
                .ainkradTooltip("Stops new work; its runs finish")
        } else {
            AinkradButton(title: "Undrain", style: .secondary) { store.setDrained(runner, false) }
                .secondaryAccent().compact().fixedSize()
                .ainkradTooltip("Takes work again")
        }
    }

    /// The preference and whether the Mac took it yet.
    private var powerNapTip: String {
        let on = runner.powerNap == true
        let applied = runner.powerNapApplied.map { $0 == on ? " The Mac holds it." : " The Mac has not taken it yet." }
        return
            (on ? "Power Nap is on: the Mac wakes for queued jobs." : "Turns Power Nap on so queued jobs wake the Mac.")
            + (applied ?? "")
    }
}

/// Disk: used / cap, the split bar and its legend, idle worktrees with their countdown, and the runner's limits.
private struct DiskSection: View {
    let store: CitadelStore
    let model: CompanyModel
    let runner: RunnerInfo
    let disk: RunnerDiskInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack {
                Text(skin.labelCased("Disk")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                Spacer()
                Text(total).citadelFont("t12", mono: true)
                    .foregroundStyle(disk.isNearCap ? status.warning : skin.color(skin.text.muted))
            }
            DiskBar(disk: disk)
            legend
            worktrees
            if disk.isNearCap, let next = disk.idleWorktrees.first {
                Text(
                    "Past \(disk.evictPercent)% the oldest idle worktree is evicted first (\(key(next.issueID)), idle \(Fmt.age(TimeInterval(next.idleSecs))))."
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            limits
        }
    }

    /// `31.4 / 50 GB`, `43.8 / 50 GB · 88%` near the cap.
    private var total: String {
        let used = (Double(disk.used) / 1e9).formatted(.number.precision(.fractionLength(1)))
        let text = "\(used) / \(ScopedSetting.bytes(disk.capBytes))"
        return disk.isNearCap ? "\(text) · \(Int((disk.fraction * 100).rounded()))%" : text
    }

    private var legend: some View {
        HStack(spacing: skin.size.s12) {
            LegendItem(tone: .accentSecondary, text: "shared build cache \(ScopedSetting.bytes(disk.shared))")
            LegendItem(tone: .accentPrimary, text: "\(disk.activeCount) active \(ScopedSetting.bytes(disk.active))")
            LegendItem(
                tone: .accentViolet, text: "\(disk.idleWorktrees.count) idle \(ScopedSetting.bytes(disk.idle))")
        }
    }

    @ViewBuilder private var worktrees: some View {
        let idle = disk.idleWorktrees
        if !idle.isEmpty {
            VStack(alignment: .leading, spacing: skin.size.s3) {
                ForEach(idle, id: \.issueID) { worktree in
                    HStack {
                        Text(
                            worktree.line(
                                key: model.issue(worktree.issueID)?.key, repos: model.issueRepos[worktree.issueID])
                        )
                        .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                        Spacer(minLength: skin.size.s8)
                        if let countdown = worktree.removalCountdown(measuredAt: disk.measuredAt, now: Date()) {
                            Text(countdown).foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                    .citadelFont("t11", mono: true)
                }
            }
        }
    }

    private func key(_ issue: Int64) -> String { (model.issue(issue)?.key ?? "issue \(issue)").lowercased() }

    @ViewBuilder private var limits: some View {
        let page = model.runnersPage
        let titles = [
            "runner.disk_cap_bytes": "Cap", "workspace.idle_secs": "Idle after",
            "runner.disk_evict_percent": "Evict past",
        ]
        VStack(spacing: skin.size.s4) {
            ForEach(RunnersPage.limitKeys, id: \.self) { key in
                if let setting = page.settings[runner.id]?[key] {
                    let scope = "runner:\(runner.id)"
                    AinkradScopedValue(
                        label: titles[key] ?? key, bounds: setting.bounds,
                        value: Binding(
                            get: { setting.text },
                            set: { store.setRunnerLimit(runner.id, key: key, text: $0) }),
                        scope: setting.chip(at: scope, inherited: page.serverSettings[key]),
                        validate: setting.accepts,
                        onReset: setting.isSet(at: scope) ? { store.resetRunnerLimit(runner.id, key: key) } : nil)
                }
            }
        }
    }
}

/// The disk bar: the split, as wide as the share of the cap it uses, over the cap's track.
private struct DiskBar: View {
    let disk: RunnerDiskInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { proxy in
            AinkradStackedStatusBar(toneRuns: [
                AinkradToneRun(value: Double(disk.shared), tone: .accentSecondary),
                AinkradToneRun(value: Double(disk.active), tone: .accentPrimary),
                AinkradToneRun(value: Double(disk.idle), tone: .accentViolet),
            ])
            .frame(width: proxy.size.width * min(1, disk.fraction))
        }
        .frame(height: skin.size.s4)
        .background(Capsule().fill(skin.color(skin.palette.white).opacity(skin.opacity.o08)))
    }
}

/// A legend swatch and its text.
struct LegendItem: View {
    let tone: AinkradChartTone
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            RoundedRectangle(cornerRadius: skin.size.s2).fill(tone.tint(skin)).frame(
                width: skin.size.s8, height: skin.size.s8)
            Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
        }
    }
}

/// The mockups' `.why` block: a bold sentence, then the detail, on a tinted fill (red unhealthy, amber waiting).
struct ReasonBlock: View {
    let title: String
    let detail: String
    var tone: AinkradChartTone?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = tone.map { $0.tint(skin) }
        // Amber text for waiting (the mockups' `.why.warn`); a red block keeps its text light on the red fill.
        let text = tone == .warning ? tint : nil
        (Text(title).bold().foregroundStyle(text ?? skin.color(skin.text.primary))
            + Text(" \(detail)").foregroundStyle(text ?? skin.color(skin.text.muted)))
            .citadelFont("t12_5")
            .lineSpacing(skin.size.s3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (tint ?? skin.color(skin.palette.white)).opacity(tone == nil ? skin.opacity.o05 : skin.opacity.o10),
                in: RoundedRectangle(cornerRadius: skin.size.s8))
    }
}
