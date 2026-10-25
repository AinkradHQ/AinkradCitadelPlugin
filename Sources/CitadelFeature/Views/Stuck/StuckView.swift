import AinkradAppKit
import AppKit
import SwiftUI

/// Screen 08: issues that stopped moving and the engine's reason — a summary strip (stuck, slowing, oldest, the
/// agents waiting) beside project tabs, then stuck (nothing moves them without you) above slowing (past their usual
/// time), one diagnosis card each. A fix that lands takes its card out; the engine's next read stays the truth.
struct StuckView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var project: Int64?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let lists = model.stuckList(project: project)
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(
                title: "Why stuck",
                crumb: Text("Issues that stopped moving, and the engine's reason · checked every 30 s")
                    .foregroundStyle(skin.color(skin.text.muted)))
            bar.padding(.horizontal, skin.size.s20).padding(.bottom, skin.size.s12)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s20) {
                    if lists.stuck.isEmpty && lists.slowing.isEmpty {
                        zero.frame(maxWidth: .infinity).padding(.top, skin.size.s80)
                    } else if lists.stuck.isEmpty {
                        clear
                    }
                    section("Stuck — nothing moves these without you", lists.stuck, offset: 0)
                    section("Slowing — moving, but past their usual time", lists.slowing, offset: lists.stuck.count)
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: lists.stuck + lists.slowing)
            }
            .scrollIndicators(.never)
            .offlineDimmed()
        }
    }

    // MARK: - Summary bar

    private var bar: some View {
        let all = model.stuckList(project: nil)
        let waiting = Array(Set(all.stuck.compactMap(\.agentID))).sorted().compactMap { model.agent($0) }
        let oldest = all.stuck.compactMap(\.since).min()
        return HStack(spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                kpi(tint: skin.color(skin.palette.danger), icon: "flag", value: "\(all.stuck.count)", label: "stuck")
                kpi(
                    tint: skin.color(skin.palette.warning), icon: "clock", value: "\(all.slowing.count)",
                    label: "slowing")
                kpi(
                    tint: skin.color(skin.palette.accentViolet), icon: "hourglass",
                    value: oldest.map { Fmt.age(Date().timeIntervalSince($0)) } ?? "—", label: "oldest")
                waitingTile(waiting)
            }
            AinkradGlideTabs(tabs(all), selection: $project)
                .frame(width: skin.size.s380)
        }
    }

    private func tabs(_ all: (stuck: [StuckInfo], slowing: [StuckInfo])) -> [AinkradGlideTab<Int64?>] {
        let items = all.stuck + all.slowing
        return [AinkradGlideTab(nil, title: "All", count: "\(items.count)")]
            + model.projects.map { item in
                AinkradGlideTab(
                    item.id, title: item.key,
                    count: "\(items.filter { model.issue($0.issueID)?.projectID == item.id }.count)")
            }
    }

    private func kpi(tint: Color, icon: String, value: String, label: String) -> some View {
        tile(tint: tint, value: value, label: label) {
            Image(systemName: icon).citadelFont("t14", weight: "medium").foregroundStyle(tint)
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
        }
    }

    private func waitingTile(_ agents: [AgentInfo]) -> some View {
        tile(tint: skin.color(skin.palette.accentPrimary), value: "\(agents.count)", label: "agents waiting") {
            HStack(spacing: -skin.size.s8) {
                ForEach(agents) { agent in
                    AgentFigure(agent: agent, model: model, size: skin.size.s26)
                        .background(Circle().fill(skin.color(.palette("background", 1))))
                }
            }
        }
    }

    private func tile<Leading: View>(
        tint: Color, value: String, label: String, @ViewBuilder leading: () -> Leading
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return HStack(spacing: skin.size.s10) {
            leading()
            VStack(alignment: .leading, spacing: 0) {
                Text(value).citadelFont("t17", weight: "bold", mono: true).foregroundStyle(tint)
                Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s12)
        .layoutPriority(1)
        .frame(maxWidth: .infinity)
        .frame(height: skin.size.s52)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o72))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }

    // MARK: - Lists

    @ViewBuilder private func section(_ title: String, _ items: [StuckInfo], offset: Int) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                AinkradSectionHead(title: title, count: "\(items.count)")
                ForEach(Array(items.enumerated()), id: \.element.cardID) { index, item in
                    StuckCard(store: store, model: model, stuck: item)
                        .ainkradRiseIn(delay: Double(offset + index) * 0.06)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    /// Stuck is empty, slowing is not (`.sk-clear`).
    private var clear: some View {
        let green = skin.color(skin.palette.success)
        return HStack(spacing: skin.size.s10) {
            Text("✓").citadelFont("t13", weight: "bold").foregroundStyle(green)
            Text(
                "Nothing is stuck\(project.flatMap { id in model.projects.first { $0.id == id } }.map { " in \($0.key)" } ?? "") — the engine checks every 30 s."
            )
            .citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s12)
        .background(green.opacity(skin.opacity.o08), in: RoundedRectangle(cornerRadius: skin.size.s14))
        .overlay(RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(green.opacity(skin.opacity.o20)))
    }

    private var zero: some View {
        let green = skin.color(skin.palette.success)
        return VStack(spacing: skin.size.s8) {
            Image(systemName: "checkmark").citadelFont("t24", weight: "semibold").foregroundStyle(green)
                .frame(width: skin.size.s64, height: skin.size.s64)
                .background(green.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s18))
                .overlay(RoundedRectangle(cornerRadius: skin.size.s18).strokeBorder(green.opacity(skin.opacity.o30)))
                .ainkradRiseIn(delay: 0.1, distance: skin.size.s12)
            Text("Every issue has a moving next actor").citadelFont("t14", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            Text("The engine checks every 30 s. Anything that stops moving shows up here with the reason.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        }
    }
}

extension StuckInfo {
    /// A card's identity in the list: its issue (or kind) and kind.
    var cardID: String { "\(issueID.map(String.init) ?? "-")·\(kind)·\(agentID.map(String.init) ?? "-")" }
}

/// A stuck card's age: `48m`, `2h 04m`, `1d`.
func stuckAge(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    if s < 3600 { return "\(s / 60)m" }
    if s < 86_400 { return String(format: "%dh %02dm", s / 3600, s % 3600 / 60) }
    return "\(s / 86_400)d"
}
