import AinkradAppKit
import SwiftUI

/// The pool overview (`.ach`): the health donut with its legend, headroom per harness in the current window, and who
/// is on the pool now with the next reset.
struct AccountsOverview: View {
    let model: CompanyModel
    let accounts: [PoolAccount]
    @Environment(\.ainkradSkin) private var skin

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            health.frame(maxWidth: .infinity)
            headroom.frame(maxWidth: .infinity).layoutPriority(1.4)
            poolNow.frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        BentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s10) { content() }
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func title(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: skin.size.s8) {
            Image(systemName: symbol).citadelFont("t12").foregroundStyle(skin.color(skin.palette.accentPrimary))
            Text(text).citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
        }
    }

    private var health: some View {
        let counts = PoolAccount.Health.legend.map { health, label in
            (health, label, accounts.filter { page.health(of: $0) == health }.count)
        }
        .filter { $0.2 > 0 }
        return tile {
            HStack(spacing: skin.size.s16) {
                SegmentDonut(
                    segments: counts.enumerated().map {
                        DonutSegment(id: $0.offset, value: Double($0.element.2), color: $0.element.0.tone.tint(skin))
                    }, diameter: skin.size.s90, lineWidth: skin.size.s10, gap: skin.size.s3
                ) {
                    VStack(spacing: 0) {
                        Text("\(accounts.count)").citadelFont("t21", weight: "bold", mono: true)
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text("accounts").citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    ForEach(counts, id: \.1) { health, label, count in
                        HStack(spacing: skin.size.s8) {
                            RoundedRectangle(cornerRadius: skin.size.s3).fill(health.tone.tint(skin))
                                .frame(width: skin.size.s9, height: skin.size.s9)
                            Text(label).lineLimit(1)
                            Spacer(minLength: skin.size.s4)
                            Text("\(count)").citadelFont("t12", weight: "semibold", mono: true)
                                .foregroundStyle(skin.color(skin.text.primary))
                        }
                        .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                    }
                }
                .fixedSize()
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var headroom: some View {
        let rows = Headroom.of(accounts, warnPercent: page.warnPercent)
        return tile {
            title("Headroom in the current window", "gauge.with.dots.needle.33percent")
            VStack(alignment: .leading, spacing: skin.size.s8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                    let tint = AgentLook.harness(row.harness)?.color ?? skin.color(skin.text.muted)
                    HStack(spacing: skin.size.s10) {
                        HarnessTag(harness: row.harness, size: skin.size.s26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(AgentLook.harnessName(row.harness)).citadelFont("t12", weight: "semibold")
                                .foregroundStyle(skin.color(skin.text.primary))
                            Text(Wording.count(row.accounts, "account")).citadelFont("t10_5")
                                .foregroundStyle(skin.color(skin.text.faint))
                        }
                        .frame(width: skin.size.s90, alignment: .leading)
                        if let used = row.used {
                            FillTrack(
                                fraction: 1 - used,
                                fill: AnyShapeStyle(
                                    LinearGradient(
                                        colors: [tint.opacity(skin.opacity.o55), tint], startPoint: .leading,
                                        endPoint: .trailing)), height: skin.size.s8)
                            Text("\(Int(((1 - used) * 100).rounded()))% left")
                                .citadelFont("t11", weight: "semibold", mono: true)
                                .foregroundStyle(
                                    used > 0.8 ? skin.color(skin.palette.warning) : skin.color(skin.text.primary)
                                )
                                .frame(width: skin.size.s70, alignment: .trailing)
                        } else {
                            Text("metered · no window").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var poolNow: some View {
        let ids = Set(accounts.map(\.id))
        let live = model.liveRuns.filter { $0.accountID.map(ids.contains) ?? true }
        var seen = Set<Int64>()
        let agents = live.compactMap { model.agent($0.agentID) }.filter { seen.insert($0.id).inserted }
        let limited = accounts.first { $0.health == .atLimit }
        let reset =
            limited.flatMap { account in
                account.windows(warnPercent: page.warnPercent(account.id)).first(where: \.isAtLimit)?.resetsAt
                    ?? account.statusUntil
            }
        return tile {
            title("On the pool now", "bolt")
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                Text("\(live.count)").citadelFont("t30", weight: "bold", mono: true).fixedSize().layoutPriority(1)
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                Text(live.count == 1 ? "run" : "runs").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: skin.size.s4)
                AvatarStack(items: Array(agents.prefix(5)), size: skin.size.s28) {
                    AgentFigure(agent: $0, model: model, size: skin.size.s28)
                }
            }
            let amber = skin.color(skin.palette.warning)
            let green = skin.color(skin.palette.success)
            HStack(spacing: skin.size.s8) {
                Image(systemName: limited == nil ? "checkmark" : "clock").citadelFont("t12")
                    .foregroundStyle(limited == nil ? green : amber)
                if let limited {
                    (Text(limited.label).bold().font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family")))
                        .foregroundStyle(skin.color(skin.text.primary))
                        + Text(" resets ")
                        + Text(reset?.formatted(date: .omitted, time: .shortened) ?? "soon").bold()
                        .foregroundStyle(skin.color(skin.text.primary)))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text("No account at its limit")
                }
                Spacer(minLength: 0)
            }
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s8)
            .background(
                (limited == nil ? green : amber).opacity(skin.opacity.o08),
                in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
        }
    }
}
