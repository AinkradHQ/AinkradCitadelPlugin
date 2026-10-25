import AinkradAppKit
import SwiftUI

/// 11 E (prototype `_emptyCompany`): a company with no agents yet, on every screen — what the team will look like,
/// what is already set up, and the one next step.
struct NoAgentsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var proposing = false
    @State private var confirming = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    /// The templates the server serves. ponytail: only `engineering` exists server-side; Marketing and Solo builder
    /// join this list once `applyTemplate` knows them.
    private static let engineering = ["CTO", "PO", "Lead", "Dev", "Dev", "QA", "Ops"]

    private struct Step {
        let done: Bool
        let now: Bool
        let locked: Bool
        let title: String
        let detail: String
        let button: String
        let action: () -> Void
    }

    private var steps: [Step] {
        let accounts = model.accounts.values.map(\.label).sorted()
        return [
            Step(
                done: !accounts.isEmpty, now: false, locked: false, title: "Assign a provider account",
                detail: accounts.isEmpty
                    ? "Agents need an account to run on" : "\(accounts.joined(separator: ", ")) · shared from the pool",
                button: "Accounts"
            ) { store.go(to: .accounts) },
            Step(
                done: model.runnersOnline > 0, now: false, locked: false, title: "Pick a runner",
                detail: model.runners.isEmpty
                    ? "No runner has called home yet" : "\(model.runnersOnline) of \(model.runners.count) online",
                button: "Runners"
            ) { store.go(to: .runners) },
            Step(
                done: false, now: true, locked: false, title: "Hire your first team",
                detail: "Start from a template or propose agents one by one", button: "Use template"
            ) { confirming = true },
            Step(
                done: false, now: false, locked: true, title: "Give the CEO a requirement",
                detail: "Unlocks once the team is hired", button: "New requirement"
            ) {},
        ]
    }

    var body: some View {
        let done = steps.filter(\.done).count
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                header
                hero(done: done)
                HStack(alignment: .top, spacing: skin.size.s14) {
                    setup(done: done)
                    templates
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.vertical, skin.size.s14)
        }
        .scrollIndicators(.never)
        .ainkradPanelModal(isPresented: $proposing, contentWidth: skin.size.s440) {
            ProposeAgentSheet(store: store, model: model, isPresented: $proposing)
        }
        .ainkradConfirmDialog(
            isPresented: $confirming, title: "Hire the Engineering template?",
            message:
                "\(Self.engineering.count) hires: \(Self.engineering.joined(separator: ", ")) — each lands in Approvals for you to confirm.",
            confirmTitle: "Propose \(Self.engineering.count) hires"
        ) {
            store.useTemplate()
            store.toast(
                AinkradRichToast(
                    title: "\(Self.engineering.count) hires proposed",
                    body: "They wait in Approvals — nothing runs until you hire.",
                    status: .success))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text(store.company?.name ?? CitadelApp.displayName).citadelFont("t15", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            (Text("New company · \(store.company?.kind.value1 == .client ? "client" : "own") · No agents yet · ")
                .foregroundStyle(skin.color(skin.text.muted)) + Text("● live").foregroundStyle(status.success))
                .citadelFont("t11")
        }
    }

    private func hero(done: Int) -> some View {
        BentoTile(padding: skin.size.s26) {
            HStack(alignment: .center, spacing: skin.size.s24) {
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    Text("Getting started · \(done) of \(steps.count)").citadelFont("t10_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.muted))
                    Text("Build the \(store.company?.name ?? "") team").citadelFont("t21", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(
                        "A company is a CEO, its agents and their budgets. Hire a team, hand the CEO a requirement, and it plans the sprint — every hire and every spend above a cap waits for you."
                    )
                    .citadelFont("t13").foregroundStyle(skin.color(skin.text.muted)).frame(
                        maxWidth: skin.size.s520, alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: skin.size.s8) {
                        AinkradDockButton("Use Engineering template", tone: .primary) { confirming = true }
                        AinkradDockButton("Propose one agent…") { proposing = true }
                    }
                    .padding(.top, skin.size.s10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                orgPreview.frame(width: skin.size.s380)
            }
        }
    }

    private var orgPreview: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        return VStack(spacing: 0) {
            seat("CEO", size: skin.size.s56, solid: true, index: 0)
            Rectangle().fill(blue.opacity(skin.opacity.o30)).frame(width: skin.size.s1, height: skin.size.s14)
            seat(Self.engineering[0], size: skin.size.s44, solid: false, index: 1)
            Rectangle().fill(blue.opacity(skin.opacity.o30)).frame(width: skin.size.s1, height: skin.size.s14)
            Rectangle().fill(blue.opacity(skin.opacity.o30)).frame(width: skin.size.s300, height: skin.size.s1)
                .padding(.bottom, skin.size.s14)
            HStack(spacing: skin.size.s8) {
                ForEach(Array(Self.engineering.dropFirst().enumerated()), id: \.offset) { index, role in
                    seat(role, size: skin.size.s44, solid: false, index: index + 2)
                }
            }
        }
    }

    private func seat(_ role: String, size: CGFloat, solid: Bool, index: Int) -> some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        return Text(role).citadelFont("t10", weight: "semibold", mono: true).foregroundStyle(
            blue.opacity(skin.opacity.o90)
        )
        .frame(width: size, height: size)
        .background(shape.fill(blue.opacity(solid ? skin.opacity.o16 : skin.opacity.o06)))
        .overlay(
            shape.strokeBorder(
                blue.opacity(solid ? skin.opacity.o50 : skin.opacity.o35),
                style: StrokeStyle(lineWidth: 1, dash: solid ? [] : [skin.size.s3, skin.size.s3]))
        )
        .modifier(SeatEntrance(index: index))
    }

    private func setup(done: Int) -> some View {
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack(spacing: skin.size.s8) {
                    Text("Setup").citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                    AinkradBudgetBar(
                        label: "Setup", value: Double(done), limit: Double(steps.count), warnFraction: nil,
                        showsHardLimit: false,
                        tone: .progress(Double(done), of: Double(steps.count)))
                    Text("\(done)/\(steps.count)").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.text.faint))
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(step, number: index + 1)
                }
            }
        }
    }

    private func stepRow(_ step: Step, number: Int) -> some View {
        let tint =
            step.done ? status.success : step.now ? skin.color(skin.palette.accentPrimary) : skin.color(skin.text.muted)
        return HStack(spacing: skin.size.s10) {
            Text(step.done ? "✓" : "\(number)").citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(tint)
                .frame(width: skin.size.s30, height: skin.size.s30)
                .background(
                    tint.opacity(step.now ? skin.opacity.o25 : skin.opacity.o12),
                    in: RoundedRectangle(cornerRadius: skin.size.s9))
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(step.title).citadelFont("t13", weight: "medium")
                    .foregroundStyle(skin.color(step.done ? skin.text.muted : skin.text.primary))
                Text(step.detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !step.locked {
                AinkradDockButton(
                    step.done ? "Review" : step.button, tone: step.now ? .primary : .plain, height: skin.size.s26,
                    action: step.action)
            }
        }
        .padding(.vertical, skin.size.s8)
        .padding(.horizontal, skin.size.s6)
        .opacity(step.locked ? skin.opacity.o50 : 1)
    }

    private var templates: some View {
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                Text("Team templates").citadelFont("t10_5", weight: "semibold").foregroundStyle(
                    skin.color(skin.text.muted))
                templateRow(
                    count: "\(Self.engineering.count)", name: "Engineering", tag: "Recommended",
                    detail: Self.engineering.joined(separator: " · "), trailing: "at default budgets"
                ) { confirming = true }
                templateRow(
                    count: "＋", name: "Start blank", tag: nil,
                    detail: "Propose agents one by one · each is a hire you approve",
                    trailing: "you pick"
                ) { proposing = true }
            }
        }
    }

    private func templateRow(
        count: String, name: String, tag: String?, detail: String, trailing: String, action: @escaping () -> Void
    ) -> some View {
        let blue = skin.color(skin.palette.accentPrimary)
        return AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s10) {
                Text(count).citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
                    blue.opacity(skin.opacity.o90)
                )
                .frame(width: skin.size.s30, height: skin.size.s30)
                .background(blue.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s9))
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    HStack(spacing: skin.size.s6) {
                        Text(name).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                        if let tag {
                            Text(tag).citadelFont("t9_5", weight: "semibold").foregroundStyle(
                                blue.opacity(skin.opacity.o90)
                            )
                            .padding(.horizontal, skin.size.s6)
                            .background(
                                blue.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s5))
                        }
                    }
                    Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(trailing).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.vertical, skin.size.s8)
            .padding(.horizontal, skin.size.s6)
            .contentShape(Rectangle())
        }
    }
}

/// Seats pop in one after another (translate up 6 pt, scale .9 → 1), 120 ms apart.
private struct SeatEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.9)
            .offset(y: shown || reduceMotion ? 0 : skin.size.s6)
            .onAppear {
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.5)).delay(Double(index) * 0.12)
                ) {
                    shown = true
                }
            }
    }
}
