import AinkradAppKit
import SwiftUI

/// Screen 06: everything waiting on you — a 340 pt list (type strip, cards, "Answered today") beside the selected
/// approval's stage. ↑ ↓ move through the list, R focuses the reply; ⌘↵ / ⌘⌫ live on the stage's dock.
struct ApprovalsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var filter: ApprovalFilter = .all
    @FocusState private var listFocused: Bool
    @State private var replyFocus = 0
    @Environment(\.ainkradSkin) private var skin
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
                .frame(width: skin.size.s340)
                .background(skin.color(.palette("foreground", skin.opacity.o03)).opacity(skin.opacity.o66))
            Group {
                if let failure = store.actionFailure {
                    ActionFailureView(store: store, failure: failure)
                } else if let selected {
                    ApprovalDetail(store: store, model: model, approval: selected, replyFocus: replyFocus)
                        .id(selected.id)
                        .transition(.opacity)
                } else {
                    zero
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: selected?.id)
        }
        .offlineDimmed()
    }

    /// `apZero`: a popping green check tile, "Nothing waits on you", the last decision.
    private var zero: some View {
        let green = skin.color(skin.palette.success)
        return VStack(spacing: skin.size.s8) {
            Image(systemName: "checkmark").citadelFont("t24", weight: "semibold").foregroundStyle(green)
                .frame(width: skin.size.s64, height: skin.size.s64)
                .background(green.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s18))
                .overlay(RoundedRectangle(cornerRadius: skin.size.s18).strokeBorder(green.opacity(skin.opacity.o30)))
                .ainkradRiseIn(delay: 0.1, distance: skin.size.s12)
            Text("Nothing waits on you").citadelFont("t14", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            Text(
                [model.lastDecisionLine(), "New approvals arrive here and as a notification."].compactMap { $0 }
                    .joined(separator: " ")
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).multilineTextAlignment(.center)
            .frame(maxWidth: skin.size.s420)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("Approvals").citadelFont("t17", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Text(subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s4)
            TypeStrip(model: model, filter: $filter)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, approval in
                        card(approval, index: index, answered: false)
                    }
                    if items.isEmpty {
                        Text(filter == .all ? "Nothing waiting" : "No \(filter.title.lowercased()) approvals")
                            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                            .frame(maxWidth: .infinity).padding(.vertical, skin.size.s20)
                    }
                    let answered = model.answeredApprovals.filter(filter.matches)
                    if !answered.isEmpty {
                        AinkradSectionHead(title: "Answered today", count: "\(answered.count)")
                            .padding(.top, skin.size.s10).padding(.horizontal, skin.size.s2)
                        ForEach(Array(answered.enumerated()), id: \.element.id) { index, approval in
                            card(approval, index: items.count + index, answered: true)
                        }
                    }
                }
                .padding(.bottom, skin.size.s14)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
            }
            .scrollIndicators(.never)
        }
        .padding(.top, skin.size.s14)
        .padding(.horizontal, skin.size.s12)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress("r") {
            replyFocus += 1
            return .handled
        }
        .onAppear { listFocused = true }
    }

    /// "5 waiting on you · 2 runs paused", or "all clear".
    private var subtitle: String {
        guard !model.approvals.isEmpty else { return "all clear" }
        let paused = model.approvals.filter(model.holdsRun).count
        return "\(model.approvals.count) waiting on you · \(Wording.count(paused, "run")) paused"
    }

    private func card(_ approval: ApprovalInfo, index: Int, answered: Bool) -> some View {
        ApprovalCard(
            model: model, approval: approval, isSelected: selected?.id == approval.id, answered: answered,
            index: index
        ) { store.selectedApproval = approval.id }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let index = items.firstIndex { $0.id == selected?.id } ?? 0
        store.selectedApproval = items[min(max(index + step, 0), items.count - 1)].id
        return .handled
    }
}

/// The six-cell type strip (`.ap-types`): each type's icon in its colour and its count; tap filters.
private struct TypeStrip: View {
    let model: CompanyModel
    @Binding var filter: ApprovalFilter
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let track = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        HStack(spacing: skin.size.s3) {
            ForEach(ApprovalFilter.allCases, id: \.self) { option in
                cell(option, count: model.approvals.filter(option.matches).count)
            }
        }
        .padding(skin.size.s4)
        .background(track.fill(skin.color(.palette("background", skin.opacity.o72))))
        .overlay(track.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }

    private func cell(_ option: ApprovalFilter, count: Int) -> some View {
        let tint = option.tint(skin)
        let isOn = filter == option
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        return AinkradTapArea(help: option.title, action: { filter = option }) {
            HStack(spacing: skin.size.s5) {
                Image(systemName: option.systemImage).citadelFont("t12", weight: "medium").foregroundStyle(tint)
                Text("\(count)").citadelFont("t11", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(isOn ? skin.text.primary : skin.text.muted))
            }
            .frame(maxWidth: .infinity)
            .frame(height: skin.size.s36)
            .background(shape.fill(isOn ? tint.opacity(skin.opacity.o18) : .clear))
            .overlay(shape.strokeBorder(isOn ? tint.opacity(skin.opacity.o45) : .clear, lineWidth: 1))
            .contentShape(shape)
            .opacity(count == 0 && !isOn ? skin.opacity.o40 : 1)
        }
        .accessibilityLabel("\(option.title), \(count)")
    }
}
