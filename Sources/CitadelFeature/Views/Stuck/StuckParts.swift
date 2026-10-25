import AinkradAppKit
import SwiftUI

/// The evidence trail of a stuck card, from what the plugin knows (the server sends no `trail` yet): a live run's
/// runner, its silence counting up and the watchdog's limit; otherwise the engine's last repair, the stuck rule, the
/// runner it waits on, and who it waits on.
struct StuckTrail: View {
    let model: CompanyModel
    let stuck: StuckInfo
    let liveRun: RunInfo?
    let isWarn: Bool

    var body: some View {
        if let run = liveRun {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StepTrail(steps: runSteps(run, now: context.date), delay: 0.15)
            }
        } else {
            StepTrail(steps: steps, delay: 0.15)
        }
    }

    private func runSteps(_ run: RunInfo, now: Date) -> [TrailStep] {
        let runner = run.runnerID.flatMap { model.runners[$0] }
        var out = [TrailStep(label: ["run #\(run.id)", runner].compactMap { $0 }.joined(separator: " · "))]
        if let last = run.lastProgressAt {
            out.append(TrailStep(label: "silent", state: .warn, detail: Fmt.duration(now.timeIntervalSince(last))))
        }
        if let stall = model.limits["run.stall_after_secs"]?.value {
            out.append(TrailStep(label: "watchdog stops it at \(Fmt.age(TimeInterval(stall)))", state: .bad))
        }
        return out
    }

    private var steps: [TrailStep] {
        var out: [TrailStep] = []
        if let repair = stuck.lastRepair {
            out.append(
                TrailStep(
                    label: "engine \(repair.replacingOccurrences(of: "_", with: " "))",
                    detail: stuck.lastRepairAt?.formatted(date: .omitted, time: .shortened)))
        }
        if stuck.waitsOnASleepingRunner {
            let tags = model.agent(stuck.agentID)?.runnerTags ?? []
            if !tags.isEmpty { out.append(TrailStep(label: "needs tag \(tags.joined(separator: ", "))")) }
            if let runner = sleepingRunner(for: tags, in: model.runnersPage.runners) {
                out.append(
                    TrailStep(
                        label: "\(runner.name) asleep", state: .bad,
                        detail: runner.lastSeenAt.map { "since \($0.formatted(date: .omitted, time: .shortened))" }))
            }
        } else {
            out.append(TrailStep(label: Self.rule(stuck.kind), state: isWarn ? .warn : .bad))
        }
        if let agent = model.agent(stuck.agentID) {
            out.append(TrailStep(label: "waits on \(agent.name)", state: isWarn ? .warn : .ok))
        }
        return out
    }

    /// The stuck rule in words.
    static func rule(_ kind: String) -> String {
        switch kind {
        case "run_queued_no_lease": "no runner took the run"
        case "checkout_dead": "its run died holding it"
        case "reviewer_inactive": "reviewer inactive"
        case "review_no_reviewer": "no reviewer"
        case "blocked_no_blocker": "blocked, no blocker named"
        case "blocked_blockers_closed", "blocker_closed": "blockers closed"
        case "agent_paused_by_breaker": "loop breaker tripped"
        case "in_progress_idle", "issue_idle", "todo_idle": "no progress"
        default: kind.replacingOccurrences(of: "_", with: " ")
        }
    }
}

/// The 22 pt severity badge on a stuck card's orb: a white glyph on the card colour, ringed, pulsing for stuck.
struct SeverityBadge: View {
    let tint: Color
    let systemImage: String
    let pulses: Bool
    @State private var glow = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemImage).citadelFont("t10", weight: "bold")
            .foregroundStyle(skin.color(.palette("foreground", 1)))
            .frame(width: skin.size.s22, height: skin.size.s22)
            .background(tint, in: RoundedRectangle(cornerRadius: skin.size.s7))
            .background(
                RoundedRectangle(cornerRadius: skin.size.s9).fill(skin.color(.palette("background", 1)))
                    .padding(-skin.size.s3)
            )
            .shadow(color: tint.opacity(glow ? 1 : 0), radius: skin.size.s7)
            .onAppear {
                guard pulses, !reduceMotion else { return }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 1)).repeatForever()) {
                    glow = true
                }
            }
    }
}

/// A dock-button look for a menu's label (`AinkradMenuButton` draws its own button around a plain label).
struct DockLabel: View {
    let title: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(title).citadelFont("t12", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                skin.color(.palette("foreground", skin.opacity.o07)), in: RoundedRectangle(cornerRadius: skin.size.s10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o09))))
    }
}
