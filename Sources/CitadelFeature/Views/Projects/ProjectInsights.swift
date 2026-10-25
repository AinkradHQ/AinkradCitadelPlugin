import AinkradAppKit
import SwiftUI

/// The Timeline tab (`quest-plan.js` `qTimeline`): epics as roadmap bars over weeks with a today line, then a card
/// per epic. The server keeps no epic dates (MISSING `Epic.starts_on/ends_on`), so a bar spans the sprints its
/// issues sit in; an epic with no sprinted issue has no bar.
struct ProjectTimeline: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    private struct Span {
        var epic: EpicInfo
        var start: Date?
        var end: Date?
    }

    var body: some View {
        let work = facts.work
        let spans = work.epics.map { epic -> Span in
            let sprints = Set(work.items.filter { $0.epicID == epic.id }.compactMap(\.sprintID))
            let mine = work.sprints.filter { sprints.contains($0.id) }
            return Span(epic: epic, start: mine.compactMap(\.startsOn).min(), end: mine.compactMap(\.endsOn).max())
        }
        let starts = spans.compactMap(\.start) + [Date()]
        let ends = spans.compactMap(\.end) + [Date()]
        let from = Calendar.current.date(byAdding: .day, value: -3, to: starts.min() ?? Date()) ?? Date()
        let to = max(
            Calendar.current.date(byAdding: .day, value: 3, to: ends.max() ?? Date()) ?? Date(),
            from.addingTimeInterval(7 * 86_400 * 4))
        VStack(alignment: .leading, spacing: skin.size.s14) {
            AinkradBentoTile {
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    OverviewHead(title: "Roadmap · epics") {
                        Text(
                            "\(from.formatted(.dateTime.month(.abbreviated))) → \(to.formatted(.dateTime.month(.abbreviated)))"
                        )
                        .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                    if work.epics.isEmpty {
                        Text("No epics yet — the PO groups issues into epics while planning.").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint))
                    } else {
                        RoadmapGrid(
                            rows: spans.enumerated().map { index, span in
                                let progress = work.progress(span.epic.id)
                                return RoadmapRow(
                                    id: span.epic.id, title: span.epic.title,
                                    caption: "\(progress.done)/\(progress.of) items · \(percent(progress))%",
                                    tint: ProjectLook.epicTint(span.epic.id, in: work, skin: skin), start: span.start,
                                    end: span.end,
                                    progress: Double(percent(progress)) / 100, order: index)
                            }, from: from, to: to
                        ) { facts.page.filter.epic = $0 }
                    }
                }
            }
            AinkradCardGrid(columns: 2, spacing: skin.size.s14) {
                ForEach(work.epics) { epic in card(epic) }
            }
        }
    }

    private func percent(_ p: (done: Int, of: Int, donePoints: Int, points: Int)) -> Int {
        p.points > 0 ? Int(Double(p.donePoints) / Double(p.points) * 100) : (p.of > 0 ? p.done * 100 / p.of : 0)
    }

    private func card(_ epic: EpicInfo) -> some View {
        let work = facts.work
        let progress = work.progress(epic.id)
        let tint = ProjectLook.epicTint(epic.id, in: work, skin: skin)
        // The requirement its issues serve, when they all serve one (MISSING `Epic.requirement_id`).
        let reqs = Set(work.items.filter { $0.epicID == epic.id }.compactMap(\.requirementID))
        let requirement = reqs.count == 1 ? facts.model.requirements.first { $0.id == reqs.first } : nil
        return AinkradBentoTile(onTap: { facts.page.filter.epic = epic.id }) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s8) {
                    Text("⚡").citadelFont("t12").foregroundStyle(tint)
                        .frame(width: skin.size.s26, height: skin.size.s26)
                        .background(tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s8))
                    Text(epic.title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                        .lineLimit(1)
                    Spacer(minLength: skin.size.s8)
                    Text(epic.key).citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                }
                ProgressTrack(
                    value: progress.points > 0 ? Double(progress.donePoints) / Double(progress.points) : 0, tint: tint)
                HStack(spacing: skin.size.s12) {
                    Text("\(progress.done) of \(progress.of) items")
                    Text("\(progress.donePoints)/\(progress.points) pts")
                    if let requirement {
                        TileLink(requirement.key) { store.screen = .requirements }
                    }
                }
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }
}

struct RoadmapRow {
    var id: Int64
    var title: String
    var caption: String
    var tint: Color
    var start: Date?
    var end: Date?
    var progress: Double
    var order: Int
}

// kit-candidate: Gantt / roadmap bars with a week header and a today line (spec 05 §10.9); the kit has no time axis.
struct RoadmapGrid: View {
    let rows: [RoadmapRow]
    let from: Date
    let to: Date
    let pick: (Int64) -> Void
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let span = max(1, to.timeIntervalSince(from))
        let weeks = stride(from: 0, to: span, by: 7 * 86_400).map { from.addingTimeInterval($0) }
        let today = Date().timeIntervalSince(from) / span
        let red = skin.color(skin.palette.danger)
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: skin.size.s10) {
            GridRow {
                Color.clear.frame(width: skin.size.s220, height: skin.size.s1)
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            Text(week.formatted(.dateTime.month(.abbreviated).day())).citadelFont("t10", mono: true)
                                .foregroundStyle(skin.color(skin.text.faint))
                                .padding(.leading, skin.size.s6)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o06))).frame(
                                        width: skin.size.s1)
                                }
                                .offset(x: geo.size.width * week.timeIntervalSince(from) / span)
                        }
                        Text("today").citadelFont("t9", mono: true).foregroundStyle(red)
                            .padding(.horizontal, skin.size.s4)
                            .background(red.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s4))
                            .offset(x: geo.size.width * today - skin.size.s14, y: -skin.size.s2)
                    }
                }
                .frame(height: skin.size.s16)
            }
            ForEach(rows, id: \.id) { row in
                GridRow {
                    HStack(spacing: skin.size.s10) {
                        RoundedRectangle(cornerRadius: skin.size.s3).fill(row.tint).frame(
                            width: skin.size.s10, height: skin.size.s10)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.title).citadelFont("t12_5", weight: "bold").foregroundStyle(
                                skin.color(skin.text.primary)
                            ).lineLimit(1)
                            Text(row.caption).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                    .frame(width: skin.size.s220, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: skin.size.s8).fill(
                                skin.color(.palette("foreground", skin.opacity.o03)))
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o05))).frame(
                                    width: skin.size.s1
                                )
                                .offset(x: geo.size.width * week.timeIntervalSince(from) / span)
                            }
                            if let start = row.start, let end = row.end {
                                let x = geo.size.width * start.timeIntervalSince(from) / span
                                let w = max(skin.size.s24, geo.size.width * end.timeIntervalSince(start) / span)
                                AinkradTapArea(help: row.title, action: { pick(row.id) }) {
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: skin.size.s8).fill(
                                            row.tint.opacity(skin.opacity.o22))
                                        Rectangle().fill(row.tint.opacity(skin.opacity.o55)).frame(
                                            width: w * row.progress)
                                        Text("\(Int(row.progress * 100))%").citadelFont(
                                            "t10_5", weight: "semibold", mono: true
                                        )
                                        .foregroundStyle(skin.color(skin.text.primary)).padding(.leading, skin.size.s8)
                                    }
                                    .frame(width: w, height: skin.size.s24)
                                    .clipShape(RoundedRectangle(cornerRadius: skin.size.s8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: skin.size.s8).strokeBorder(
                                            row.tint.opacity(skin.opacity.o55)))
                                }
                                .scaleEffect(x: grown || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                                .animation(
                                    skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.6)).delay(
                                        Double(row.order) * 0.09), value: grown
                                )
                                .offset(x: x, y: skin.size.s5)
                            }
                            Rectangle().fill(red.opacity(skin.opacity.o65)).frame(width: skin.size.s2)
                                .padding(.vertical, -skin.size.s6)
                                .offset(x: geo.size.width * today)
                        }
                    }
                    .frame(height: skin.size.s34)
                }
            }
        }
        .onAppear { grown = true }
    }
}

/// The Reports tab (`quest-plan.js` `qReports`): cumulative flow (needs the server), throughput per week, cycle
/// time with its 85th percentile, and the work mix.
struct ProjectReports: View {
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let work = facts.work
        AinkradCardGrid(columns: 2, spacing: skin.size.s14) {
            AinkradBentoTile {
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    OverviewHead(title: "Cumulative flow") {
                        Text("6 weeks").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                    Text("Needs daily state counts from the server (MISSING `GET /projects/{id}/cfd`).").citadelFont(
                        "t11"
                    )
                    .foregroundStyle(skin.color(skin.text.faint)).frame(maxWidth: .infinity, minHeight: skin.size.s140)
                    HStack(spacing: skin.size.s14) {
                        ForEach(["done", "review", "in_progress", "todo"], id: \.self) {
                            ProjectLegend(tint: ProjectLook.flowTint($0, skin: skin), label: ProjectLogic.title($0))
                        }
                    }
                }
            }
            AinkradBentoTile {
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    OverviewHead(title: "Throughput") {
                        Text("items done per week").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                    let top = Double(max(1, work.throughput.map(\.done).max() ?? 1))
                    VBars(
                        bars: work.throughput.map {
                            VBar(label: "\($0.done)", value: $0.week, back: 0, front: Double($0.done) / top)
                        }
                    )
                    .frame(height: skin.size.s150)
                }
            }
            cycle(work.cycleDays)
            mix(work.items.filter { $0.state != "cancelled" })
        }
    }

    private func cycle(_ days: [Double]) -> some View {
        let p85 = ProjectLogic.percentile(days, 0.85)
        let cyan = skin.color(skin.palette.accentSecondary)
        let amber = skin.color(skin.palette.warning)
        let top = max(10, (days.max() ?? 0) * 1.1)
        return AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Cycle time") {
                    Text("days from start to done").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.text.faint))
                }
                GeometryReader { geo in
                    let y = { (v: Double) in geo.size.height * (1 - v / top) }
                    ZStack(alignment: .topLeading) {
                        ForEach([2.0, 5.0, 8.0], id: \.self) { v in
                            Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o06))).frame(
                                height: skin.size.s1
                            ).offset(y: y(v))
                        }
                        ForEach(Array(days.suffix(18).enumerated()), id: \.offset) { index, v in
                            Circle().fill(v > 6 ? amber : cyan).opacity(skin.opacity.o85)
                                .frame(width: skin.size.s10, height: skin.size.s10)
                                .position(
                                    x: skin.size.s10 + CGFloat(index) / CGFloat(max(1, min(18, days.count) - 1))
                                        * (geo.size.width - skin.size.s20), y: y(v)
                                )
                                .help(String(format: "%.1f days", v))
                        }
                        if let p85 {
                            Path {
                                $0.move(to: CGPoint(x: 0, y: y(p85)))
                                $0.addLine(to: CGPoint(x: geo.size.width, y: y(p85)))
                            }
                            .stroke(
                                cyan.opacity(skin.opacity.o60),
                                style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s4]))
                        }
                    }
                }
                .frame(height: skin.size.s140)
                HStack(spacing: skin.size.s14) {
                    ProjectLegend(tint: cyan, label: "item")
                    ProjectLegend(tint: amber, label: "slower than 6 days")
                    ProjectLegend(
                        tint: cyan,
                        label: p85.map { String(format: "85th percentile · %.1f d", $0) } ?? "85th percentile",
                        dashed: true)
                }
            }
        }
    }

    private func mix(_ items: [WorkItem]) -> some View {
        let kinds = ["story", "task", "bug", "subtask"]
        return AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Work mix") {
                    Text("\(items.count) items").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.text.faint))
                }
                ForEach(kinds, id: \.self) { kind in
                    let count = items.filter { $0.kind == kind }.count
                    let look = ProjectLook.kind(kind, skin: skin)
                    HStack(spacing: skin.size.s10) {
                        ItemKindChip(kind: kind)
                        Text(look.title).citadelFont("t12", weight: "bold").foregroundStyle(
                            skin.color(skin.text.primary)
                        )
                        .frame(width: skin.size.s60, alignment: .leading)
                        ProgressTrack(value: items.isEmpty ? 0 : Double(count) / Double(items.count), tint: look.tint)
                        Text("\(count)").citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.muted))
                            .frame(width: skin.size.s24, alignment: .trailing)
                    }
                }
            }
        }
    }
}
