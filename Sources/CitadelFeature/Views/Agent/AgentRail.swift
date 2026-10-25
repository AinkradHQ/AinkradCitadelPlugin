import AinkradAppKit
import SwiftUI

struct RailLabel: View {
    let title: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(skin.labelCased(title)).citadelFont("t10", weight: "semibold").tracking(skin.size.s1 / 2)
            .foregroundStyle(skin.color(skin.text.muted))
    }
}

/// The last seven days of an agent's runs: one bar a day, stacked by how they ended.
struct WeekOfRuns {
    let bars: [AinkradChartBar]
    let caption: String

    init(runs: [RunInfo], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let recent = runs.filter { $0.queuedAt >= days[0] && !$0.isLive }
        bars = days.map { day in
            let mine = recent.filter { calendar.isDate($0.queuedAt, inSameDayAs: day) }
            return AinkradChartBar(
                label: day.formatted(.dateTime.weekday(.narrow)),
                segments: [
                    AinkradBarSegment(
                        name: "succeeded", value: Double(mine.filter { $0.endWord == "succeeded" }.count),
                        tone: .accentSecondary),
                    AinkradBarSegment(
                        name: "cap hit", value: Double(mine.filter { $0.endWord == "cap hit" }.count), tone: .warning),
                    AinkradBarSegment(
                        name: "failed",
                        value: Double(
                            mine.filter { ["failed", "runner lost", "timed out"].contains($0.endWord) }.count),
                        tone: .danger),
                ])
        }
        let succeeded = recent.filter { $0.endWord == "succeeded" }.count
        let failed = recent.filter { ["failed", "runner lost", "timed out"].contains($0.endWord) }.count
        let capped = recent.filter { $0.endWord == "cap hit" }.count
        caption =
            "\(Wording.count(recent.count, "run")) · \(succeeded) succeeded · \(failed) failed · \(capped) cap hit"
    }
}
