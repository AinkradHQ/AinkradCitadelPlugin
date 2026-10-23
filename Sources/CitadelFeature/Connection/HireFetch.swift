import CitadelClient
import Foundation

/// Hiring from the app (11 A, 03): a template's agents or one proposed agent, each a hire approval to decide —
/// never a running agent until it is approved.
extension CitadelServer {
    /// Applies a company template (`engineering`): the hire approvals it opened (none on a re-apply).
    func applyTemplate(company: Int64, _ template: String) async -> Result<Int, ServerAnswer> {
        await attempt({ try await client.applyTemplate(path: .init(id: company, template: template)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.hireApprovalIds.count
        }
    }

    /// Proposes one agent; its hire approval's id.
    func proposeAgent(company: Int64, _ draft: AgentDraft) async -> Result<Int64, ServerAnswer> {
        await attempt({ try await client.proposeAgent(path: .init(id: company), body: .json(draft.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.hireApprovalId
        }
    }
}

/// "Propose an agent…" as typed.
struct AgentDraft: Equatable, Sendable {
    var name = ""
    var role = ""
    var harness = "claude"
    var model = ""
    var justification = ""
    var reportsTo: Int64?
    /// Space-separated (`macos xcode-27`).
    var runnerTags = ""

    static let harnesses = ["claude", "codex", "opencode", "agy"]

    /// Why it cannot be sent yet, or `nil`.
    var problem: String? {
        func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
        if blank(name) { return "Name the agent." }
        if blank(role) { return "Give it a role (QA, Designer…)." }
        if blank(model) { return "Pick its model." }
        if blank(justification) { return "Say why the company needs it — the hire approval shows it." }
        return nil
    }

    var body: Schemas.AgentProposal {
        let tags = runnerTags.split(whereSeparator: \.isWhitespace).map(String.init)
        return Schemas.AgentProposal(
            harness: .init(value1: .init(rawValue: harness), value2: harness),
            justification: justification.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces),
            reportsTo: reportsTo, role: role.trimmingCharacters(in: .whitespaces),
            runnerTags: tags.isEmpty ? nil : tags)
    }
}
