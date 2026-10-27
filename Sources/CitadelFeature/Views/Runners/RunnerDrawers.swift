import AinkradAppKit
import AppKit
import SwiftUI

/// One line of a runner's log as the drawer draws it: time, source, level and message.
struct RunnerLogLine: Equatable {
    var time: String
    var source: String
    /// `err`, `warn` or `info`.
    var level: String
    var message: String

    // ponytail: the server sends log lines as plain strings; the level is read from the words. Parse the structured
    // `[{at, source, level, message}]` once `getRunnerLogs` returns it.
    init(_ line: String) {
        var words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let isTime = { (word: String) in word.contains(":") && word.allSatisfy { $0.isNumber || $0 == ":" || $0 == "." }
        }
        time = words.first.map(isTime) == true ? words.removeFirst() : ""
        let explicit = ["error": "err", "err": "err", "warn": "warn", "warning": "warn", "info": "info"]
        if let first = words.first, explicit[first.lowercased()] == nil, !first.hasSuffix(":"), words.count > 1 {
            source = words.removeFirst()
        } else {
            source = ""
        }
        if let first = words.first, let level = explicit[first.lowercased()] {
            words.removeFirst()
            self.level = level
        } else {
            let lower = words.joined(separator: " ").lowercased()
            let bad = ["error", "fail", "not logged in", "lost", "refused", "gave up", "reset by peer", "missed"]
            let warn = ["warn", "newer than tested", "retry", "suspend", "sleep", "paused"]
            level = bad.contains(where: lower.contains) ? "err" : warn.contains(where: lower.contains) ? "warn" : "info"
        }
        message = words.joined(separator: " ")
    }
}

/// "Show log" / "Log": the hero, level filters with counts, Download, and the tail as a terminal.
struct RunnerLogDrawer: View {
    let page: RunnersPage
    let runner: RunnerInfo
    let lines: [String]
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let parsed = lines.map(RunnerLogLine.init)
        let shown = parsed.filter { page.logFilter == "all" || $0.level == page.logFilter }
        RunnerHero(runner: runner)
        HStack(spacing: skin.size.s6) {
            ForEach(filters, id: \.id) { filter in
                FilterChip(
                    title: filter.title,
                    count: filter.id == "all" ? parsed.count : parsed.filter { $0.level == filter.id }.count,
                    tint: filter.tint, isOn: page.logFilter == filter.id
                ) { page.logFilter = filter.id }
            }
            Spacer(minLength: skin.size.s8)
            AinkradDockButton("Download", systemImage: "arrow.down.to.line", height: skin.size.s30) { download() }
                .disabled(lines.isEmpty)
        }
        terminal(shown)
    }

    private var filters: [(id: String, title: String, tint: Color?)] {
        [
            ("all", "All", nil), ("err", "Errors", status.danger), ("warn", "Warnings", status.warning),
            ("info", "Info", skin.color(skin.palette.accentPrimary)),
        ]
    }

    private func terminal(_ shown: [RunnerLogLine]) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(skin.color(.palette("foreground", skin.opacity.o12))).frame(
                        width: skin.size.s10, height: skin.size.s10)
                }
                Text("\(runner.name) · runner.log\(runner.status == "online" ? " · tailing" : "")")
                    .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint)).padding(
                        .leading, skin.size.s8)
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(skin.color(.palette("foreground", skin.opacity.o03)))
            VStack(alignment: .leading, spacing: 0) {
                if shown.isEmpty {
                    Text(lines.isEmpty ? "The log is empty." : "nothing at this level")
                        .foregroundStyle(skin.color(skin.text.faint)).padding(.horizontal, skin.size.s14)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    LogRow(line: line).ainkradRiseIn(delay: 0.035 * Double(index))
                }
                if runner.status == "online" {
                    HStack(spacing: skin.size.s10) {
                        Text("now").foregroundStyle(skin.color(skin.text.faint))
                        LogCaret()
                    }
                    .padding(.horizontal, skin.size.s14)
                } else {
                    Text("— no entries since —").foregroundStyle(skin.color(skin.text.faint))
                        .padding(.horizontal, skin.size.s14).padding(.vertical, skin.size.s4)
                }
            }
            .citadelFont("t12", mono: true)
            .padding(.vertical, skin.size.s10)
        }
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o75), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }

    /// Saves the tail as text where the user picks.
    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(runner.name)-runner.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// One log line: its level tints the row (red and amber), and a hover washes it faintly, still under reduce-motion.
private struct LogRow: View {
    let line: RunnerLogLine
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let tint: Color? = line.level == "err" ? status.danger : line.level == "warn" ? status.warning : nil
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
            Text(line.time).foregroundStyle(skin.color(skin.text.faint)).fixedSize()
            Text(line.source).foregroundStyle(skin.color(skin.palette.accentPrimary)).lineLimit(1)
                .frame(width: skin.size.s64, alignment: .leading)
            Text(line.level.uppercased()).citadelFont("t10_5", mono: true)
                .foregroundStyle(tint ?? skin.color(skin.text.faint)).frame(width: skin.size.s44, alignment: .leading)
            Text(line.message).foregroundStyle(tint ?? skin.color(skin.text.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s1)
        .background((tint ?? .clear).opacity(line.level == "err" ? skin.opacity.o07 : skin.opacity.o05))
        .background(skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)))
        .citadelHover($hovering)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
    }
}

/// The "now" caret at the foot of a live log: it blinks, and holds still under reduce-motion.
private struct LogCaret: View {
    @State private var dim = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle().fill(skin.color(skin.palette.accentSecondary))
            .frame(width: skin.size.s8, height: skin.size.s14)
            .opacity(dim ? skin.opacity.o30 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                let blink = skin.animation(AinkradAnimationToken(curve: "easeInOut", durationKey: "slow"))
                withAnimation(blink.repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// The runner as the drawers' hero: its device tile, name, platform line and state.
struct RunnerHero: View {
    let runner: RunnerInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let look = RunnerLook(runner: runner)
        AinkradDrawerHero(
            tint: look.tint(skin), title: runner.name, subtitle: look.line(now: Date()),
            leading: { DeviceTile(look: look, size: skin.size.s56) },
            trailing: { AinkradStatePill(text: look.state, tint: look.tint(skin), dot: true) })
    }
}

/// "Re-login on server": the login command for each harness the runner reports logged out, run on its host as the
/// runner's user; then its harnesses as tiles until its next probe reports them back.
struct RunnerReloginDrawer: View {
    let page: RunnersPage
    let runner: RunnerInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let healthy = runner.status == "online"
        RunnerHero(runner: runner)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                .frame(width: skin.size.s2).padding(.leading, skin.size.s15).padding(.vertical, skin.size.s20)
            VStack(alignment: .leading, spacing: skin.size.s14) {
                step(1, "Copy the login command", done: page.reloginWaiting || healthy) {
                    ForEach(logins, id: \.dir) { login in CommandStrip(command: login.command) }
                }
                step(2, "Run it on \(runner.name)", done: page.reloginWaiting || healthy) {
                    Text(
                        "Logins belong to the runner's own user — Citadel never sees them. Finish the browser login it opens."
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .fixedSize(horizontal: false, vertical: true)
                }
                step(3, "Re-probe the harnesses", done: healthy) { probes }
            }
        }
    }

    /// What to log in again: every logged-out login (they survive the drawer while the runner flips healthy).
    private var logins: [RunnerLoginInfo] {
        runner.loggedOut.isEmpty
            ? runner.logins.filter { $0.harness != nil && !$0.dir.hasPrefix("accounts/") } : runner.loggedOut
    }

    private func step<Content: View>(
        _ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            Text(verbatim: done && number < 3 ? "✓" : "\(number)").citadelFont("t13", weight: "bold", mono: true)
                .foregroundStyle(skin.color(done && number < 3 ? .palette("background", 1) : .palette("foreground", 1)))
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(
                    done && number < 3
                        ? AnyShapeStyle(status.success)
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing)), in: Circle())
            VStack(alignment: .leading, spacing: skin.size.s8) {
                Text(title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                content()
            }
            .padding(.top, skin.size.s5)
        }
    }

    private var probes: some View {
        let rows = runner.harnessRows
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: skin.size.s8), count: 3), spacing: skin.size.s8
        ) {
            ForEach(rows, id: \.name) { row in
                let out = row.login == "logged_out"
                let checking = out && page.reloginWaiting
                let tint = checking ? skin.color(skin.palette.accentPrimary) : out ? status.danger : status.success
                VStack(spacing: skin.size.s6) {
                    HarnessTag(harness: row.name)
                    Text(AgentLook.harnessName(row.name)).citadelFont("t12", weight: "semibold", mono: true)
                    HStack(spacing: skin.size.s5) {
                        if checking { ProgressView().controlSize(.mini) }
                        Text(checking ? "waiting for its probe" : out ? "✗ logged out" : "✓ \(row.version)")
                    }
                    .citadelFont("t11").foregroundStyle(tint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, skin.size.s12)
                .padding(.horizontal, skin.size.s8)
                .background(tint.opacity(skin.opacity.o08), in: RoundedRectangle(cornerRadius: skin.size.s14))
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(
                        tint.opacity(skin.opacity.o28), lineWidth: 1))
            }
        }
    }
}

/// Later · "I've logged in" (then it waits for the runner's own probe — the server has no probe call yet) → Done.
struct ReloginFoot: View {
    let page: RunnersPage
    let runner: RunnerInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let healthy = runner.status == "online"
        Spacer()
        if !healthy { AinkradDockButton("Later") { page.relogin = nil } }
        AinkradDockButton(
            healthy ? "Done" : page.reloginWaiting ? "Waiting for its next probe…" : "I've logged in", tone: .primary,
            isEnabled: healthy || !page.reloginWaiting
        ) {
            if healthy { page.relogin = nil } else { page.reloginWaiting = true }
        }
        .help("The runner re-probes its harnesses on its own (within 10 min); this page updates when it does")
    }
}
