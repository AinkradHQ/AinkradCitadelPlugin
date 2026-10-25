import AinkradAppKit
import SwiftUI

/// The fleet overview (`rnh`): machines, capacity, disk and tag coverage, side by side (1.25 : 1 : 1 : 1).
struct RunnerOverview: View {
    let page: RunnersPage
    let running: [Int64: Int]
    let focus: (Int64) -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        WeightedRow(weights: [1.25, 1, 1, 1], spacing: skin.size.s12) {
            tile("server.rack", "Fleet", trailing: "\(page.runners.count) machine\(page.runners.count == 1 ? "" : "s")")
            {
                fleet
            }
            tile("square.split.3x1", "Capacity", trailing: "\(running.values.reduce(0, +)) running") { capacity }
            tile("cylinder", "Disk") { disk }
            tile("tag", "Tag coverage") { tags }
        }
    }

    private func tile<Content: View>(
        _ icon: String, _ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        BentoTile(padding: skin.size.s15) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s8) {
                    Image(systemName: icon).citadelFont("t12").foregroundStyle(skin.color(skin.palette.accentPrimary))
                    Text(title).citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                    Spacer(minLength: skin.size.s4)
                    if let trailing { Text(trailing).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
                }
                content()
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Fleet

    private var fleet: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: skin.size.s80), spacing: skin.size.s6)], spacing: skin.size.s6)
        {
            ForEach(page.runners) { runner in FleetChip(runner: runner) { focus(runner.id) } }
        }
    }

    // MARK: Capacity

    private var capacity: some View {
        let slots = page.freeSlots(running: running)
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                Text(verbatim: "\(slots?.free ?? 0)").citadelFont("t28", weight: "bold", mono: true)
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                Text("of \(slots?.total ?? 0) slots free").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            VStack(alignment: .leading, spacing: skin.size.s5) {
                ForEach(page.runners) { runner in
                    HStack(spacing: skin.size.s8) {
                        name(runner.name)
                        SlotPips(
                            total: runner.slots ?? 0, busy: min(runner.slots ?? 0, running[runner.id] ?? 0),
                            isOn: runner.status == "online" && runner.drainedAt == nil, hollowFree: true,
                            pip: CGSize(width: skin.size.s16, height: skin.size.s7))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func name(_ text: String) -> some View {
        Text(text).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            .frame(width: skin.size.s80, alignment: .leading)
    }

    // MARK: Disk

    private var disk: some View {
        VStack(alignment: .leading, spacing: skin.size.s9) {
            ForEach(page.runners.filter { page.disk[$0.id] != nil }) { runner in
                if let disk = page.disk[runner.id] {
                    let percent = Int((disk.fraction * 100).rounded())
                    HStack(spacing: skin.size.s8) {
                        name(runner.name)
                        GeometryReader { geo in
                            HStack(spacing: skin.size.s1) {
                                ForEach(disk.parts(skin)) { part in
                                    Rectangle().fill(part.color)
                                        .frame(
                                            width: geo.size.width * Double(part.bytes) / Double(max(disk.capBytes, 1)))
                                }
                            }
                        }
                        .frame(height: skin.size.s8)
                        .background(skin.color(.palette("foreground", skin.opacity.o06)))
                        .clipShape(Capsule())
                        Text(verbatim: "\(percent)%").citadelFont("t11", weight: "semibold", mono: true)
                            .foregroundStyle(percent >= 80 ? status.warning : skin.color(skin.text.primary))
                            .frame(width: skin.size.s36, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Tags

    /// Every tag a runner has: green when an online runner has it, amber when only an asleep one, red when none can
    /// take it now.
    private var tagCoverage: [(tag: String, tint: Color, count: Int)] {
        var order: [String] = []
        for tag in page.runners.flatMap(\.tags) where !order.contains(tag) { order.append(tag) }
        return order.map { tag in
            let holders = page.runners.filter { $0.tags.contains(tag) }
            let tint =
                holders.contains { $0.status == "online" }
                ? status.success : holders.contains { $0.state == "asleep" } ? status.warning : status.danger
            return (tag, tint, holders.count)
        }
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            AinkradFlowLayout(spacing: skin.size.s6) {
                ForEach(tagCoverage, id: \.tag) { item in
                    HStack(spacing: skin.size.s6) {
                        Circle().fill(item.tint).frame(width: skin.size.s6, height: skin.size.s6)
                            .shadow(color: item.tint, radius: skin.size.s6)
                        Text(item.tag).foregroundStyle(skin.color(skin.text.primary))
                        Text(verbatim: "\(item.count)").foregroundStyle(skin.color(skin.text.faint))
                    }
                    .citadelFont("t11", mono: true)
                    .padding(.horizontal, skin.size.s9)
                    .frame(height: skin.size.s26)
                    .background(item.tint.opacity(skin.opacity.o10), in: RoundedRectangle(cornerRadius: skin.size.s8))
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s8).strokeBorder(
                            item.tint.opacity(skin.opacity.o28), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
            Text("Green: an online runner has the tag · amber: only asleep · red: nothing can take it.")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize(
                    horizontal: false, vertical: true)
        }
    }
}

/// A machine chip: its device tile, name and state; tap focuses its card.
private struct FleetChip: View {
    let runner: RunnerInfo
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let look = RunnerLook(runner: runner)
        let tint = look.tint(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(help: "\(runner.name) · \(look.state)", action: action) {
            VStack(spacing: skin.size.s5) {
                DeviceTile(look: look, size: skin.size.s34)
                Text(runner.name).citadelFont("t11", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1).truncationMode(.tail)
                Text(look.state).citadelFont("t10").foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, skin.size.s10)
            .padding(.horizontal, skin.size.s6)
            .padding(.bottom, skin.size.s8)
            .background(
                tint.citadelMix(
                    with: skin.color(.palette("black", skin.opacity.o15)), fraction: hovering ? 0.87 : 0.93), in: shape
            )
            .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// A row whose children share the width by weight and all take the tallest child's height.
private struct WeightedRow: Layout {
    let weights: [Double]
    let spacing: CGFloat

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let w = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let free = max(0, total - spacing * CGFloat(max(count - 1, 0)))
        let sum = w.reduce(0, +)
        return w.map { free * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let sizes = widths(width, count: subviews.count)
        let height =
            zip(subviews, sizes).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
