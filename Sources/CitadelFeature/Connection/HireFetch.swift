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
    /// What API minor 17 lets a proposal carry; the wizard fills them only for a server that has it.
    var description: String?
    var effort: String?
    var sandbox: String?
    var instructions: String?
    var guidelines: [String]?
    var teamID: Int64?
    var teamRole: String?
    var paletteID: String?

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

    /// At most 50 rules of 1-500 characters, as the server takes them.
    static func cleanGuidelines(_ rules: [String]) -> [String] {
        Array(rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(50))
            .map { String($0.prefix(500)) }
    }

    var body: Schemas.AgentProposal {
        let tags = runnerTags.split(whereSeparator: \.isWhitespace).map(String.init)
        var proposal = Schemas.AgentProposal(
            harness: .init(value1: .init(rawValue: harness), value2: harness),
            justification: justification.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces),
            reportsTo: reportsTo, role: role.trimmingCharacters(in: .whitespaces),
            runnerTags: tags.isEmpty ? nil : tags)
        proposal.description = description.flatMap { $0.isEmpty ? nil : String($0.prefix(4000)) }
        proposal.effort = effort.map { Schemas.Effort(value1: .init(rawValue: $0), value2: $0) }
        proposal.sandbox = sandbox.map { Schemas.Sandbox(value1: .init(rawValue: $0), value2: $0) }
        proposal.instructions = instructions.flatMap { $0.isEmpty ? nil : String($0.prefix(20_000)) }
        proposal.guidelines = guidelines.map { Self.cleanGuidelines($0) }
        proposal.teamId = teamID
        proposal.teamRole = teamRole.map { Schemas.TeamRole(value1: .init(rawValue: $0), value2: $0) }
        proposal.paletteId = paletteID
        return proposal
    }
}
