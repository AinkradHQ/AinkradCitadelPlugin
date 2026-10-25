import AinkradAppKit
import SwiftUI

/// One limit (`lm-row`): its name over "key · bounds"; the draggable gauge with the server default ticked (read-only
/// for server-wide rows); this company's value as an editable pill with its scope chip; the values set below as chips
/// that open their screen. Click selects it for the CLI card; hover shows the resolution chain.
struct LimitRowView: View {
    let store: CitadelStore
    let model: CompanyModel
    let row: LimitRow
    let tint: Color
    @State private var preview: Int64?
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var page: LimitsPage { model.limitsPage }
    private var scope: String { "company:\(model.companyID)" }
    private var setting: ScopedSetting { row.company ?? row.setting }

    var body: some View {
        let selected = page.selected == row.id
        let flashing = page.flashed == row.id
        HStack(spacing: skin.size.s16) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(row.name).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                Text("\(row.setting.key) · \(row.setting.bounds)").citadelFont("t10", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1).truncationMode(.middle)
            }
            .frame(minWidth: skin.size.s140, maxWidth: .infinity, alignment: .leading)
            VStack(spacing: skin.size.s2) {
                AinkradDragGauge(
                    value: Double(setting.value), range: Double(row.setting.min)...Double(row.setting.max),
                    step: Double(Self.step(row.setting)), mark: Double(row.setting.value), tint: tint,
                    isEnabled: row.company != nil, label: row.name,
                    valueText: { ScopedSetting.format(Int64($0), unit: row.setting.unit) },
                    onChange: { preview = Int64($0) },
                    onCommit: { value in
                        preview = nil
                        if let company = row.company { store.commitLimit(company, scope: scope, value: Int64(value)) }
                    })
                GaugeLegend(
                    low: row.setting.text(row.setting.min), middle: "server \(row.setting.text)",
                    high: row.setting.text(row.setting.max))
            }
            .frame(minWidth: skin.size.s150, maxWidth: .infinity)
            value.frame(minWidth: skin.size.s180, alignment: .leading)
            overrides.frame(minWidth: skin.size.s110, alignment: .leading)
        }
        .padding(.horizontal, skin.size.s8)
        .padding(.vertical, skin.size.s11)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous).fill(
                tint.opacity(flashing ? skin.opacity.o20 : selected ? skin.opacity.o09 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
                    .fill(skin.color(.palette("foreground", hovering && !selected ? skin.opacity.o03 : 0))))
        )
        .contentShape(Rectangle())
        .onTapGesture { page.selected = row.id }
        .onHover { hovering = $0 }
        .ainkradHoverCard { resolutionCard }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .animation(skin.animation(skin.motion.present), value: flashing)
        .animation(skin.animation(skin.motion.hover), value: selected)
    }

    /// The gauge's step in the setting's unit: whole minutes / hours, whole GB / KB, thousands of tokens.
    static func step(_ setting: ScopedSetting) -> Int64 {
        switch setting.unit {
        case "seconds": setting.min >= 3600 && setting.max >= 86_400 ? 3600 : 60
        case "bytes": setting.min >= 1_000_000_000 || setting.max >= 100_000_000_000 ? 1_000_000_000 : 1_000
        case "tokens": 1_000
        case "milliseconds": 100
        default: 1
        }
    }

    @ViewBuilder private var value: some View {
        if let company = row.company {
            let set = company.isSet(at: scope)
            HStack(spacing: skin.size.s6) {
                AinkradValuePill(
                    text: preview.map { ScopedSetting.format($0, unit: company.unit) } ?? company.text,
                    help: "Click to edit · \(company.bounds)"
                ) { text in
                    if let parsed = company.parse(text) { store.commitLimit(company, scope: scope, value: parsed) }
                }
                .validating(
                    { page.check(company, $0) },
                    onRefuse: { text in
                        store.toast(
                            AinkradRichToast(
                                title: "Refused: \(text.isEmpty ? "empty" : text) is outside \(company.bounds)",
                                body: "Values are validated against the bounds — never clamped.", status: .danger))
                    })
                AinkradScopeChip(
                    text: set ? "company" : company.sourceKind, overridden: set,
                    reset: set ? { store.resetLimitWithToast(company, scope: scope) } : nil
                )
                .tooltip(set ? "Set for this company" : "Inherited from the \(company.sourceKind)")
                if let refused = page.refused[row.id] {
                    Text(refused).citadelFont("t10").foregroundStyle(status.danger).lineLimit(1)
                }
            }
        } else {
            Text(row.companyNote ?? "").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    @ViewBuilder private var overrides: some View {
        if row.overrides.isEmpty {
            Text(verbatim: "—").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else {
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s4) {
                ForEach(row.overrides, id: \.scope) { item in OverrideChip(item: item) { store.openOverride(item) } }
            }
        }
    }

    /// "Stall timeout · resolution": Server 15 min → company 15 min → CIT 10 min, bounds and key.
    private var resolutionCard: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            Text("\(row.name) · resolution").citadelFont("t11", weight: "semibold").foregroundStyle(
                skin.color(skin.text.muted))
            HStack(spacing: skin.size.s6) {
                step("Server \(row.setting.text)", isHere: false)
                Text(verbatim: "→").foregroundStyle(skin.color(skin.text.faint))
                step(
                    "\(store.company?.name ?? "Company") \(row.company?.text ?? "—")",
                    isHere: row.company?.isSet(at: scope) == true)
                ForEach(row.overrides, id: \.scope) { item in
                    Text(verbatim: "→").foregroundStyle(skin.color(skin.text.faint))
                    step("\(item.owner) \(item.value)", isHere: true)
                }
            }
            .citadelFont("t11")
            Text("Bounds \(row.setting.bounds) · \(row.setting.key)").citadelFont("t11").foregroundStyle(
                skin.color(skin.text.faint))
        }
        .padding(skin.size.s12)
    }

    private func step(_ text: String, isHere: Bool) -> some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        return Text(text).foregroundStyle(isHere ? cyan : skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s9).padding(.vertical, skin.size.s3)
            .background(
                isHere ? cyan.opacity(skin.opacity.o12) : skin.color(.palette("foreground", skin.opacity.o05)),
                in: RoundedRectangle(cornerRadius: skin.size.s6))
    }
}

/// "CIT **10 min**": a value set below the company; opens its screen.
private struct OverrideChip: View {
    let item: LimitOverride
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(help: "Open \(item.owner)", action: open) {
            (Text(item.owner).foregroundStyle(skin.color(skin.text.muted)) + Text(" ")
                + Text(item.value).bold().foregroundStyle(skin.color(skin.text.primary)))
                .citadelFont("t10_5", mono: true).lineLimit(1)
                .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s1)
                .background(
                    skin.color(skin.palette.accentSecondary).opacity(hovering ? skin.opacity.o18 : skin.opacity.o08),
                    in: RoundedRectangle(cornerRadius: skin.size.s6)
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
