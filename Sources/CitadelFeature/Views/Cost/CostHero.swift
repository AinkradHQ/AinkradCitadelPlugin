import AinkradAppKit
import SwiftUI

/// `.cs-hero`: the company budget as a ring, what it used against its cap with the pace it is on, and the period
/// tabs. In dollars when the budget has a dollar cap (API minor 18), else tokens; with no company budget it shows the priced
/// dollars alone.
struct CostHero: View {
    let model: CompanyModel
    @Binding var period: CostPeriod
    let label: String
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var glow = false

    private var budget: BudgetInfo? { model.budgets.first { $0.scope.hasPrefix("company:") } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
        let blue = skin.color(skin.palette.accentPrimary)
        HStack(alignment: .center, spacing: skin.size.s22) {
            if let budget { ring(budget) }
            VStack(alignment: .leading, spacing: skin.size.s6) {
                Text((budget == nil ? "Priced spend · " : "Company budget · ") + label).textCase(.uppercase)
                    .citadelFont("t11").tracking(0.5).foregroundStyle(skin.color(skin.text.faint))
                if let budget {
                    big(budget.spentWord, small: " / \(budget.capWord)\(budget.isDollars ? "" : " tok")")
                    ProjectionBar(
                        fraction: budget.shownFraction,
                        projected: pace(budget).map { Double($0) / Double(max(budget.shownCap, 1)) })
                    HStack(spacing: skin.size.s14) {
                        AinkradLegendSwatch(color: blue, label: "used")
                        if let pace = pace(budget) {
                            AinkradLegendSwatch(
                                color: blue.opacity(skin.opacity.o35), label: "on pace for \(budget.word(pace))")
                        }
                        Spacer()
                        Text("cap \(budget.capWord)")
                    }
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .frame(maxWidth: skin.size.s560)
                } else {
                    big(Fmt.dollars(micros: SpendTotals(model.costTasks).costMicros), small: "")
                    Text("No company budget — add one below to see the pace.").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AinkradGlideTabs(
                CostPeriod.allCases.filter { $0 != .sprint || model.sprint != nil }.map {
                    AinkradGlideTab($0, title: $0.title)
                }, selection: $period
            )
            .frame(width: skin.size.s360)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, skin.size.s22)
        .padding(.vertical, skin.size.s18)
        .background(
            ZStack(alignment: .topLeading) {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: blue.opacity(skin.opacity.o16), location: 0),
                            .init(color: skin.color(.palette("background", skin.opacity.o90)), location: 0.55),
                            .init(color: skin.color(skin.palette.accentViolet).opacity(skin.opacity.o12), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(
                    RadialGradient(
                        colors: [blue.opacity(skin.opacity.o30), .clear], center: .center, startRadius: 0,
                        endRadius: skin.size.s160)
                )
                .frame(width: skin.size.s320, height: skin.size.s320)
                .offset(x: glow ? -skin.size.s70 : -skin.size.s110, y: -skin.size.s150)
            }
            .clipShape(shape)
        )
        .overlay(shape.strokeBorder(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o25), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o30)), radius: skin.size.s24, y: skin.size.s18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeInOut", durationKey: "breathe")).repeatForever()
            ) {
                glow = true
            }
        }
        .ainkradRiseIn()
    }

    private func ring(_ budget: BudgetInfo) -> some View {
        let percent = Int((budget.fraction * 100).rounded())
        let tint =
            percent >= 90
            ? skin.color(skin.palette.danger)
            : percent >= 70 ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentPrimary)
        return AinkradRingGauge(value: budget.fraction, tint: tint, diameter: skin.size.s104, lineWidth: skin.size.s7) {
            Text("\(percent)%").citadelFont("t18", weight: "bold", mono: true).foregroundStyle(
                skin.color(skin.text.primary))
        }
    }

    private func big(_ value: String, small: String) -> some View {
        (Text(value).font(skin.font(AinkradFontToken(sizeKey: "t34", weight: "bold")))
            .foregroundStyle(skin.color(skin.text.primary))
            + Text(small).font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "medium")))
            .foregroundStyle(skin.color(skin.text.faint)))
            .tracking(-0.5)
            .contentTransition(.numericText())
    }

    /// The budget's pace: what it used so far, spread over the part of its period that has gone (linear).
    private func pace(_ budget: BudgetInfo, now: Date = Date()) -> Int64? {
        let calendar = Calendar.current
        let unit: Calendar.Component? =
            switch budget.period {
            case "day": .day
            case "week": .weekOfYear
            case "month": .month
            default: nil
            }
        guard let unit, let span = calendar.dateInterval(of: unit, for: now) else { return nil }
        let gone = now.timeIntervalSince(span.start) / span.duration
        guard gone > 0.02 else { return nil }
        return Int64(Double(budget.shownSpent) / gone)
    }
}

/// `.cs-pt`: used so far (blue gradient, grows in) then the hatched stretch to where the pace ends.
private struct ProjectionBar: View {
    let fraction: Double
    let projected: Double?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let used = geo.size.width * CGFloat(min(fraction, 1))
            let ahead = geo.size.width * CGFloat(min(max((projected ?? 0) - fraction, 0), 1 - min(fraction, 1)))
            let blue = skin.color(skin.palette.accentPrimary)
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o07)))
                Hatch(color: blue)
                    .frame(width: ahead)
                    .offset(x: used)
                    .opacity(grown ? 1 : 0)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [blue.opacity(skin.opacity.o85), blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: used * (grown ? 1 : 0))
            }
            .clipShape(Capsule())
        }
        .frame(height: skin.size.s10)
        .frame(maxWidth: skin.size.s560)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(skin.animation(skin.motion.materializeAnimation)) { grown = true }
        }
    }
}

/// 135° stripes, the projection's "on pace" stretch.
private struct Hatch: View {
    let color: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(skin.opacity.o15)))
            var x = -size.height
            let step = skin.size.s12
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                path.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                context.fill(path, with: .color(color.opacity(skin.opacity.o35)))
                x += step
            }
        }
    }
}

/// `.cs-kinds`: Priced, Unpriced (with Set a price) and Subscription, each with its sparkline.
struct CostKinds: View {
    let model: CompanyModel
    let setPrice: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let t = SpendTotals(model.costTasks)
        let blue = skin.color(skin.palette.accentPrimary)
        let amber = skin.color(skin.palette.warning)
        let violet = skin.color(skin.palette.accentViolet)
        HStack(alignment: .top, spacing: skin.size.s12) {
            tile(
                "Priced", "dollarsign", blue, value: Text(Fmt.dollars(micros: t.costMicros)),
                sub: "API-billed runs at known prices · \(Fmt.tokens(t.pricedTokens)) tok", delay: 0
            ) {
                AinkradMicroTrend(values: model.costDays.map { Double($0.totals.costMicros) }, tint: blue, style: .area)
                    .frame(height: skin.size.s34)
            }
            tile(
                "Unpriced", "exclamationmark.triangle", amber,
                value: Text("\(t.unpricedRuns) ")
                    + Text("run\(t.unpricedRuns == 1 ? "" : "s") · \(Fmt.tokens(t.unpricedTokens)) tok").font(
                        skin.font(AinkradFontToken(sizeKey: "t12", weight: "medium"))
                    ).foregroundStyle(skin.color(skin.text.faint)),
                sub: t.unpricedRuns > 0 ? unpricedLine : "Every model in this period is priced", delay: 0.06
            ) {
                AinkradDockButton(
                    t.unpricedRuns > 0 ? "Set a price" : "Edit price",
                    systemImage: t.unpricedRuns > 0 ? "plus" : "pencil",
                    tone: t.unpricedRuns > 0 ? .warning : .plain, action: setPrice
                )
                .padding(.top, skin.size.s8)
            }
            tile(
                "Subscription", "square.stack.3d.up", violet,
                value: Text(Fmt.tokens(t.subscriptionTokens) + " ")
                    + Text("tokens").font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "medium")))
                    .foregroundStyle(skin.color(skin.text.faint)),
                sub: "\(Wording.count(t.subscriptionRuns, "run")) on Max / Pro logins — tokens, not dollars",
                delay: 0.12
            ) {
                AinkradMicroTrend(
                    values: model.costDays.map { Double($0.totals.subscriptionTokens) }, tint: violet, style: .area
                )
                .frame(height: skin.size.s34)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "qwen3-coder via OpenCode has no price — never counted as $0", naming the biggest model (API minor 18).
    private var unpricedLine: String {
        guard let first = model.unpriced.first else { return "A model with no price — never counted as $0" }
        let more = model.unpriced.count > 1 ? " · +\(model.unpriced.count - 1) more" : ""
        return "\(first.model) via \(AgentLook.harnessName(first.harness)) has no price — never counted as $0\(more)"
    }

    private func tile<Foot: View>(
        _ label: String, _ symbol: String, _ tint: Color, value: Text, sub: String, delay: Double,
        @ViewBuilder foot: () -> Foot
    ) -> some View {
        AinkradBentoTile(padding: skin.size.s14, tint: tint) {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                HStack(spacing: skin.size.s8) {
                    Image(systemName: symbol).citadelFont("t12", weight: "semibold").foregroundStyle(tint)
                        .frame(width: skin.size.s28, height: skin.size.s28)
                        .background(
                            tint.opacity(skin.opacity.o16),
                            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
                    Text(label).citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                }
                value.font(skin.font(AinkradFontToken(sizeKey: "t24", weight: "bold")))
                    .foregroundStyle(skin.color(skin.text.primary)).padding(.top, skin.size.s4)
                    .contentTransition(.numericText())
                Text(sub).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .fixedSize(horizontal: false, vertical: true)
                foot()
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .ainkradHoverLift(nil, cornerRadius: skin.size.s18)
        .ainkradRiseIn(delay: delay)
    }
}

/// `.cs-chart`: per day (per hour on Today), the three kinds stacked in tokens, hover for the split.
struct CostChartTile: View {
    let store: CitadelStore
    let model: CompanyModel
    let hourly: Bool
    @Environment(\.ainkradSkin) private var skin

    /// The company's daily budget: its warn mark is the dashed line, edited under the chart.
    private var daily: BudgetInfo? { model.budgets.first { $0.scope.hasPrefix("company:") && $0.period == "day" } }

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let amber = skin.color(skin.palette.warning)
        let violet = skin.color(skin.palette.accentViolet)
        let days = model.costDays
        AinkradBentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack {
                    Text(hourly ? "Per hour · tokens" : "Per day · tokens").citadelFont("t13", weight: "bold")
                        .foregroundStyle(skin.color(skin.text.primary))
                    Spacer()
                    HStack(spacing: skin.size.s12) {
                        AinkradLegendSwatch(color: blue, label: "Priced")
                        AinkradLegendSwatch(color: amber, label: "Unpriced")
                        AinkradLegendSwatch(color: violet, label: "Subscription")
                    }
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
                if days.isEmpty {
                    Text("No runs in this period").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                        .frame(maxWidth: .infinity, minHeight: skin.size.s160)
                } else {
                    AinkradStackedBarChart(
                        bars: days.enumerated().map { index, day in
                            AinkradStackedBar(
                                id: index,
                                segments: [
                                    AinkradStackedSegment(
                                        value: Double(day.totals.pricedTokens),
                                        fill: AnyShapeStyle(
                                            LinearGradient(
                                                colors: [blue.opacity(skin.opacity.o60), blue], startPoint: .top,
                                                endPoint: .bottom))),
                                    AinkradStackedSegment(
                                        value: Double(day.totals.unpricedTokens), fill: AnyShapeStyle(amber)),
                                    AinkradStackedSegment(
                                        value: Double(day.totals.subscriptionTokens),
                                        fill: AnyShapeStyle(
                                            LinearGradient(
                                                colors: [violet.opacity(skin.opacity.o60), violet], startPoint: .top,
                                                endPoint: .bottom))),
                                ])
                        },
                        threshold: threshold, thresholdColor: amber
                    ) { index in tip(days[index]) }
                    .frame(height: skin.size.s164)
                    .id(days.map(\.day))
                    HStack {
                        Text(axis(days.first))
                        Spacer()
                        Text(axis(days.last))
                    }
                    .citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    if let daily { warnPill(daily) }
                }
            }
        }
    }

    /// The daily warn pill under the chart, editing the day budget's warn % in place. The dashed line is drawn only
    /// for a token budget: the bars are tokens, and a dollar cap has no exact token equivalent.
    private func warnPill(_ budget: BudgetInfo) -> some View {
        HStack(spacing: skin.size.s6) {
            Text("daily warn").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            AinkradValuePill(text: "\(budget.warnPercent)%", help: "Edit warn %") {
                store.editBudgetWarn(budget, text: $0, inherited: Int(model.limits["budget.warn_percent"]?.value ?? 80))
            }
            AinkradScopeChip(text: "company")
        }
    }

    /// The dashed threshold at the day budget's warn mark, in the bars' unit (tokens).
    private var threshold: Double? {
        guard let daily, !daily.isDollars else { return nil }
        return Double(daily.shownCap) * daily.warnFraction
    }

    private func axis(_ day: DaySpend?) -> String {
        guard let day else { return "" }
        return hourly
            ? day.day.formatted(.dateTime.hour().minute()) : day.day.formatted(.dateTime.month(.abbreviated).day())
    }

    private func tip(_ day: DaySpend) -> some View {
        let t = day.totals
        return AinkradChartTip {
            Text(axis(day)).bold().foregroundStyle(skin.color(skin.text.primary))
            AinkradLegendSwatch(
                color: skin.color(skin.palette.accentPrimary),
                label: "Priced \(Fmt.dollars(micros: t.costMicros)) · \(Fmt.tokens(t.pricedTokens)) tok")
            AinkradLegendSwatch(
                color: skin.color(skin.palette.warning),
                label: t.unpricedTokens > 0 ? "\(Fmt.tokens(t.unpricedTokens)) tok unpriced" : "no unpriced")
            AinkradLegendSwatch(
                color: skin.color(skin.palette.accentViolet), label: "\(Fmt.tokens(t.subscriptionTokens)) sub tok")
        }
        .foregroundStyle(skin.color(skin.text.muted))
    }
}
