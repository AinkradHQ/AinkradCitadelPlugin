import AinkradAppKit
import SwiftUI

/// One machine card (`rnc`): the device tile and state, why it needs you with the fix inline, slot pips, tags,
/// harness tiles against the tested set, disk as a segmented ring, idle worktrees counting down, its limits, and
/// the actions.
struct RunnerCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let runner: RunnerInfo
    let running: Int
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var confirmsRemove = false

    private var look: RunnerLook { RunnerLook(runner: runner) }
    private var page: RunnersPage { model.runnersPage }
    private var disk: RunnerDiskInfo? { page.disk[runner.id] }

    var body: some View {
        let tint = look.tint(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        let flashing = page.flashed == runner.id
        VStack(alignment: .leading, spacing: skin.size.s12) {
            head
            why
            if runner.status != "offline", let slots = runner.slots { slotRow(slots) }
            if !runner.tags.isEmpty { tags }
            if !tiles.isEmpty { harness }
            if let disk { vitals(disk) }
            if let disk, !disk.idleWorktrees.isEmpty { worktrees(disk) }
            limits
            if runner.status != "offline" { actions }
            if let failure = page.failures[runner.id] { RefusalLine(failure: failure) }
        }
        .padding(.vertical, skin.size.s16)
        .padding(.horizontal, skin.size.s18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    tint.citadelMix(with: skin.color(.palette("background", skin.opacity.o90)), fraction: 0.91),
                    skin.color(.palette("background", 0.86)),
                ],
                startPoint: .topLeading, endPoint: .center), in: shape
        )
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o35), in: shape)
        .overlay(
            shape.strokeBorder(
                tint.citadelMix(with: skin.color(.palette("white", skin.opacity.o06)), fraction: 0.76), lineWidth: 1)
        )
        .overlay(shape.stroke(tint.opacity(flashing ? skin.opacity.o55 : 0), lineWidth: skin.size.s3))
        .shadow(color: tint.opacity(flashing ? skin.opacity.o30 : 0), radius: skin.size.s20)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: flashing)
        .ainkradHoverLift(skin.size.s3, cornerRadius: skin.size.s20)
        .opacity(look.state == "offline" ? skin.opacity.o70 : 1)
        .ainkradConfirmDialog(
            isPresented: $confirmsRemove, title: "Remove \(runner.name)?",
            message: "Its key stops working at once. Register it again to bring the machine back.",
            confirmTitle: "Remove", isDestructive: true
        ) { store.removeRunner(runner) }
    }

    // MARK: Head

    private var head: some View {
        HStack(spacing: skin.size.s12) {
            DeviceTile(look: look)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(runner.name).citadelFont("t15", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
                Text(look.line(now: Date())).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(
                    1)
            }
            Spacer(minLength: skin.size.s8)
            StatePillBox(text: look.state, tint: look.tint(skin)).transition(.opacity).id(look.state)
        }
    }

    // MARK: Why

    /// Why it needs you, with the fix inline: re-login when unhealthy, wake when asleep, the last log and remove when
    /// offline. A drain or a pending wake adds its line.
    @ViewBuilder private var why: some View {
        let lines = [runner.reason(now: Date()), runner.drainLine(now: Date()), runner.wakeLine(now: Date())]
            .compactMap { $0 }
        if !lines.isEmpty {
            let tint = look.tint(skin)
            VStack(alignment: .leading, spacing: skin.size.s10) {
                ForEach(lines, id: \.title) { line in
                    Text("\(line.title) \(line.detail)").citadelFont("t12_5")
                        .foregroundStyle(skin.color(skin.text.muted))
                        .lineSpacing(skin.size.s3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                whyActions
            }
            .padding(.horizontal, skin.size.s14)
            .padding(.vertical, skin.size.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tint.opacity(skin.opacity.o09), in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
                    .strokeBorder(tint.opacity(skin.opacity.o25), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder private var whyActions: some View {
        switch runner.state {
        case "unhealthy":
            HStack(spacing: skin.size.s6) {
                AinkradDockButton(
                    "Re-login on server", systemImage: "key", tone: .danger, isEnabled: !runner.loggedOut.isEmpty
                ) {
                    page.reloginWaiting = false
                    page.relogin = runner.id
                }
                .help(
                    runner.loggedOut.isEmpty
                        ? "The runner reports no logged-out harness" : "Walks you through the login on its host")
            }
        case "asleep":
            HStack(spacing: skin.size.s10) {
                let waking = page.waking.contains(runner.id)
                AinkradDockButton(
                    waking ? "Waking…" : "Wake now", systemImage: "sun.max", tone: .warning, isEnabled: !waking
                ) {
                    store.wakeRunner(runner.id, when: "now")
                }
                .help("Pushes a wake to the Mac; its queued work starts when it connects")
                HStack(spacing: skin.size.s8) {
                    AinkradToggle(
                        isOn: Binding(get: { runner.powerNap == true }, set: { store.setPowerNap(runner, $0) })
                    )
                    .controlSize(.mini)
                    Text("Keep awake while macos jobs queue").citadelFont("t11").foregroundStyle(
                        skin.color(skin.text.muted))
                }
                .help(powerNapTip)
            }
        case "offline":
            HStack(spacing: skin.size.s6) {
                AinkradDockButton("Show last log", systemImage: "text.alignleft", height: skin.size.s30) {
                    openLog()
                }
                AinkradDockButton("Remove runner", tone: .danger, height: skin.size.s30) { confirmsRemove = true }
            }
        default: EmptyView()
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

    // MARK: Slots, tags, harnesses

    private func slotRow(_ slots: Int) -> some View {
        HStack(spacing: skin.size.s10) {
            SlotPips(total: slots, busy: min(running, slots))
            Text("\(min(running, slots)) of \(slots) slots busy")
            Spacer(minLength: skin.size.s8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(heartbeat(context.date))
            }
        }
        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
    }

    private func heartbeat(_ now: Date) -> String {
        guard runner.status != "offline", let seen = runner.lastSeenAt else { return "no heartbeat" }
        return runner.status == "online" ? "heartbeat \(Fmt.age(now.timeIntervalSince(seen))) ago" : "no heartbeat"
    }

    private var tags: some View {
        AinkradFlowLayout(spacing: skin.size.s5) {
            ForEach(runner.tags, id: \.self) { tag in
                Text(tag).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                    .background(
                        skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o10),
                        in: RoundedRectangle(cornerRadius: skin.size.s6))
            }
        }
    }

    /// Each harness against the tested set: ✓ tested and logged in, ▲ newer than tested, ✗ refused or logged out.
    private var tiles: [(name: String, version: String, level: Int, note: String)] {
        runner.harnessRows.map { row in
            if row.login == "logged_out" { return (row.name, row.version, 2, "logged out") }
            if let harness = row.status, !harness.offered { return (row.name, row.version, 2, harness.word) }
            let login = row.login == "logged_in" ? "logged in" : row.login == "unknown" ? "keychain login" : nil
            if let harness = row.status, harness.status != "supported" {
                return (row.name, row.version, 1, harness.word)
            }
            let tested = row.status == nil ? nil : "tested"
            return (row.name, row.version, 0, [tested, login].compactMap { $0 }.joined(separator: " · "))
        }
    }

    private var harness: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: skin.size.s190), spacing: skin.size.s6)], spacing: skin.size.s6)
        {
            ForEach(tiles, id: \.name) { tile in
                let tint = tile.level == 0 ? status.success : tile.level == 1 ? status.warning : status.danger
                HStack(spacing: skin.size.s9) {
                    Text(verbatim: tile.level == 0 ? "✓" : tile.level == 1 ? "▲" : "✗")
                        .citadelFont("t11", weight: "bold").foregroundStyle(tint)
                        .frame(width: skin.size.s22, height: skin.size.s22)
                        .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s7))
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(AgentLook.harnessName(tile.name)).citadelFont("t12", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text(tile.version).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        if !tile.note.isEmpty {
                            Text(tile.note).citadelFont("t10_5").foregroundStyle(tint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, skin.size.s10)
                .padding(.vertical, skin.size.s8)
                .background(
                    skin.color(.palette("foreground", skin.opacity.o03)),
                    in: RoundedRectangle(cornerRadius: skin.size.s12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                        tint.opacity(skin.opacity.o20), lineWidth: 1))
            }
        }
    }

    // MARK: Disk

    private func vitals(_ disk: RunnerDiskInfo) -> some View {
        let parts = disk.parts(skin)
        let percent = Int((disk.fraction * 100).rounded())
        let gb = { (bytes: Int64) in (Double(bytes) / 1e9).formatted(.number.precision(.fractionLength(0...1))) }
        return HStack(spacing: skin.size.s16) {
            DiskDonut(
                parts: parts, cap: disk.capBytes, center: "\(percent)%",
                caption: "\(gb(disk.used)) / \(gb(disk.capBytes)) GB", warn: percent >= 80)
            VStack(alignment: .leading, spacing: skin.size.s6) {
                ForEach(parts) { part in legendRow(part.color, part.label, "\(gb(part.bytes)) GB") }
                legendRow(
                    skin.color(.palette("foreground", skin.opacity.o10)), "free",
                    "\(gb(max(0, disk.capBytes - disk.used))) GB")
            }
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s16))
    }

    private func legendRow(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: skin.size.s7) {
            RoundedRectangle(cornerRadius: skin.size.s2).fill(color).frame(width: skin.size.s8, height: skin.size.s8)
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: skin.size.s8)
            Text(value).citadelFont("t11", weight: "medium", mono: true).foregroundStyle(skin.color(skin.text.primary))
        }
    }

    private func worktrees(_ disk: RunnerDiskInfo) -> some View {
        VStack(spacing: skin.size.s4) {
            ForEach(disk.idleWorktrees, id: \.issueID) { worktree in
                HStack(spacing: skin.size.s8) {
                    Image(systemName: "clock").foregroundStyle(skin.color(skin.palette.accentViolet))
                    Text(
                        worktree.line(
                            key: model.issue(worktree.issueID)?.key, repos: model.issueRepos[worktree.issueID])
                    )
                    .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                    Spacer(minLength: skin.size.s8)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(worktree.removalCountdown(measuredAt: disk.measuredAt, now: context.date) ?? "")
                            .foregroundStyle(skin.color(skin.palette.accentViolet))
                    }
                }
                .citadelFont("t11", mono: true)
                .padding(.horizontal, skin.size.s10)
                .padding(.vertical, skin.size.s7)
                .background(
                    skin.color(skin.palette.accentViolet).opacity(skin.opacity.o06),
                    in: RoundedRectangle(cornerRadius: skin.size.s10))
            }
        }
    }

    // MARK: Limits and actions

    /// "Cap **50 GB** ↳ server", "Idle after **12 h** ● runner · server 24 h ↺" … and "Limits ›".
    @ViewBuilder private var limits: some View {
        let titles = [
            "runner.disk_cap_bytes": "Cap", "workspace.idle_secs": "Idle after",
            "runner.disk_evict_percent": "Evict past",
        ]
        let settings = RunnersPage.limitKeys.compactMap { key in page.settings[runner.id]?[key] }
        if !settings.isEmpty {
            let scope = "runner:\(runner.id)"
            HStack(spacing: skin.size.s8) {
                AinkradFlowLayout(spacing: skin.size.s10, lineSpacing: skin.size.s6) {
                    ForEach(settings) { setting in
                        let set = setting.isSet(at: scope)
                        HStack(spacing: skin.size.s5) {
                            Text(titles[setting.key] ?? setting.key).citadelFont("t11").foregroundStyle(
                                skin.color(skin.text.muted))
                            ValPill(
                                text: setting.text, help: "\(setting.bounds) · Return sets it on this runner",
                                validate: setting.accepts,
                                commit: { store.setRunnerLimit(runner.id, key: setting.key, text: $0) },
                                onRefuse: { refuse($0, setting) })
                            ScopeChip(
                                text: set
                                    ? "runner · server \(page.serverSettings[setting.key]?.text ?? "")" : "server",
                                isOverridden: set,
                                help: set ? "Set on this runner" : "Server default · runners are server-wide",
                                reset: set ? { store.resetRunnerLimit(runner.id, key: setting.key) } : nil)
                        }
                    }
                }
                Spacer(minLength: skin.size.s4)
                AinkradTapArea {
                    store.model?.limitsPage.section = .limits
                    store.isShowingSettings = true
                } label: {
                    Text("Limits ›").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func refuse(_ text: String, _ setting: ScopedSetting) {
        store.toast(
            AinkradRichToast(
                title: "Refused: \(text.isEmpty ? "empty" : text) is outside \(setting.bounds)",
                body: "Values are validated against the bounds — never clamped.", status: .danger))
    }

    /// Drain / Stop draining, the log and remove (Pause and Probe wait for the server).
    private var actions: some View {
        let drained = runner.drainedAt != nil
        return HStack(spacing: skin.size.s6) {
            AinkradDockButton(
                drained ? "Stop draining" : "Drain", systemImage: "arrow.down.to.line",
                tone: drained ? .warning : .plain,
                height: skin.size.s30
            ) { store.setDrained(runner, !drained) }
            .help(drained ? "Takes work again" : "Running jobs finish; nothing new is claimed")
            AinkradDockButton("Log", systemImage: "text.alignleft", height: skin.size.s30) { openLog() }
            AinkradDockButton("", systemImage: "trash", tone: .danger, height: skin.size.s30) { confirmsRemove = true }
                .help("Remove runner")
        }
    }

    private func openLog() {
        page.logFilter = "all"
        store.showRunnerLog(runner)
    }
}
