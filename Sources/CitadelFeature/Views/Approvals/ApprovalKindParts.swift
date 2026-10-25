import AinkradAppKit
import SwiftUI

/// One PR of a merge approval (`.ap-pr`): a checks ring, the repo and "PR #61 → development · checks", the diff bar
/// and "+214 −38 · 7 files · merges 1st". The diff and checks come from the issue's PR and diff reads when loaded.
struct MergePRCard: View {
    let model: CompanyModel
    let approval: ApprovalInfo
    let row: [String: String]
    let order: Int
    @Environment(\.ainkradSkin) private var skin

    private var pr: IssuePRInfo? {
        let prs = approval.issueID.flatMap { model.issuePRs[$0] } ?? []
        return prs.first { $0.repo == row["repo"] || $0.number.map(String.init) == row["pr"] }
    }

    private var diff: RepoDiffInfo? {
        let diffs = approval.issueID.flatMap { model.issueDiffs[$0] } ?? []
        return diffs.first { $0.repo == row["repo"] } ?? (diffs.count == 1 ? diffs.first : nil)
    }

    /// The forge's checks state; an open merge approval means QA saw them pass.
    private var checks: (value: Double, tint: Color, mark: String, word: String) {
        switch pr?.checks {
        case "failure": (1, skin.color(skin.palette.danger), "✕", "checks failing")
        case "pending": (0.5, skin.color(skin.palette.warning), "…", "checks running")
        default:
            (
                1, skin.color(skin.palette.success), "✓",
                row["checks_note"].map { _ in "checks partly read" } ?? "checks passed"
            )
        }
    }

    var body: some View {
        let green = skin.color(skin.palette.success)
        let red = skin.color(skin.palette.danger)
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack(spacing: skin.size.s10) {
                AinkradRingGauge(
                    value: checks.value, tint: checks.tint, diameter: skin.size.s38, lineWidth: skin.size.s4
                ) {
                    Text(checks.mark).citadelFont("t12", weight: "bold").foregroundStyle(checks.tint)
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(row["repo"] ?? pr?.repo ?? "repo").citadelFont("t12_5", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Text(
                        "PR #\(row["pr"] ?? pr?.number.map(String.init) ?? "?") → \(pr?.base ?? "base") · \(checks.word)"
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
            }
            if let diff {
                GeometryReader { geo in
                    let total = max(Double(diff.insertions + diff.deletions), 1)
                    HStack(spacing: skin.size.s2) {
                        Capsule().fill(green).frame(width: geo.size.width * Double(diff.insertions) / total)
                        Capsule().fill(red)
                    }
                }
                .frame(height: skin.size.s8)
            }
            HStack(spacing: skin.size.s8) {
                if let diff {
                    (Text("+\(diff.insertions)").foregroundStyle(green)
                        + Text(" −\(diff.deletions)").foregroundStyle(red))
                        .citadelFont("t11")
                    Spacer(minLength: 0)
                    Text(Wording.count(Int(diff.files), "file")).citadelFont("t11")
                }
                Spacer(minLength: 0)
                Text("merges \(ApprovalDetail.ordinal(order))").citadelFont("t11")
            }
            .foregroundStyle(skin.color(skin.text.faint))
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s16)
        )
        .overlay(RoundedRectangle(cornerRadius: skin.size.s16).strokeBorder(green.opacity(skin.opacity.o20)))
    }
}

/// The command card (`.ap-term`): a bar with three dots and its title, then the command in amber mono after `$`.
struct TerminalCard: View {
    let title: String
    let command: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(skin.color(.palette("foreground", skin.opacity.o12)))
                        .frame(width: skin.size.s9, height: skin.size.s9)
                }
                Text(title).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).padding(
                    .leading, skin.size.s6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s8)
            .background(skin.color(.palette("foreground", skin.opacity.o03)))
            (Text("$ ").foregroundStyle(skin.color(skin.text.faint))
                + Text(command).foregroundStyle(skin.color(skin.palette.warning)))
                .citadelFont("t12_5", mono: true)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(skin.size.s14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(skin.color(skin.palette.black).opacity(skin.opacity.o35)))
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(skin.palette.warning).opacity(skin.opacity.o25), lineWidth: 1))
    }
}

extension CompanyModel {
    /// "Marketing › Launch": the department and team an agent sits in.
    func teamPath(of agent: Int64?) -> String? {
        guard let agent else { return nil }
        for department in departments {
            if let team = department.teams.first(where: { $0.seats.contains { $0.agentID == agent } }) {
                return "\(department.name) › \(team.name)"
            }
        }
        return nil
    }
}
