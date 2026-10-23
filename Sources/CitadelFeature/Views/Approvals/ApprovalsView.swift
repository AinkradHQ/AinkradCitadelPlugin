import AinkradAppKit
import SwiftUI

/// Screen 06: everything waiting on you, filterable by type, beside the selected approval's detail — its body by
/// kind, a reply that goes with the decision (or alone, "Reply only"), and the decision buttons. Decided items
/// stay greyed under "Answered".
struct ApprovalsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var filter: ApprovalFilter = .all
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var items: [ApprovalInfo] { model.inbox(filter) }

    /// The selection, or the first item; after a decision it moves to the next one.
    private var selected: ApprovalInfo? {
        let id = store.selectedApproval
        return items.first { $0.id == id } ?? model.answeredApprovals.first { $0.id == id } ?? items.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: skin.size.s380)
                .background(theme.surface.opacity(skin.opacity.o20))
            Group {
                if let selected {
                    ApprovalDetail(store: store, model: model, approval: selected)
                        .id(selected.id)
                        .transition(.opacity)
                } else {
                    AinkradEmptyState(
                        icon: "checkmark", title: "Nothing waits on you",
                        message: "Agents ask here when a sprint, a merge, a budget, a hire or a permission needs you.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: selected?.id)
        }
        .offlineDimmed()
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Approvals", crumb: nil) {
                if !model.approvals.isEmpty { AinkradBadge(text: "\(model.approvals.count) waiting", status: .warning) }
            }
            HStack(spacing: skin.size.s6) {
                ForEach(ApprovalFilter.allCases.filter { $0 != .permission }, id: \.self) { option in
                    AinkradToggleButton(
                        isOn: Binding(get: { filter == option }, set: { if $0 { filter = option } }),
                        title: option.title)
                }
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.bottom, skin.size.s10)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    ForEach(items) { approval in
                        row(approval, answered: false).transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if items.isEmpty {
                        Text(filter == .all ? "Nothing waits on you." : "No \(filter.title.lowercased()) approvals.")
                            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                            .padding(skin.size.s10)
                    }
                    if !model.answeredApprovals.isEmpty {
                        Text(skin.labelCased("Answered")).citadelFont("t10", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.muted))
                            .padding(.top, skin.size.s14).padding(.leading, skin.size.s10)
                        ForEach(model.answeredApprovals.filter(filter.matches)) { approval in
                            row(approval, answered: true).opacity(skin.opacity.o55)
                        }
                    }
                }
                .padding(.horizontal, skin.size.s10)
                .padding(.bottom, skin.size.s14)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
            }
        }
    }

    private func row(_ approval: ApprovalInfo, answered: Bool) -> some View {
        let summary = model.summary(approval)
        let subtitle =
            answered
            ? [approval.status == "approved" ? "approved by you" : approval.status, approval.reply].compactMap { $0 }
                .joined(separator: " · ")
            : summary.subtitle
        return AinkradListRow(
            isSelected: selected?.id == approval.id, onTap: { store.selectedApproval = approval.id },
            leading: { TypeGlyph(glyph: answered ? "✓" : summary.glyph, tone: answered ? .success : summary.tone) },
            title: summary.title, subtitle: subtitle.isEmpty ? nil : subtitle, trailing: { EmptyView() })
    }
}

/// The type's glyph on a tinted rounded square (the mockup's `.ty`).
struct TypeGlyph: View {
    let glyph: String
    let tone: AinkradChartTone
    /// The detail head's larger square.
    var isLarge = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let color = tone.tint(skin)
        let size = isLarge ? skin.size.s36 : skin.size.s28
        Text(glyph).citadelFont(isLarge ? "t16" : "t13", weight: "semibold")
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s8))
            .accessibilityHidden(true)
    }
}
