import CitadelClient
import Foundation

/// A project's harness permission policy (API minor 11): its mode and what goes ahead without asking.
struct PolicyInfo: Equatable, Sendable {
    /// `ask`, `accept_edits`, `sandboxed`, or a newer server's word.
    var mode: String
    /// A tool (`Edit`) or `<tool>:<command prefix>` (`Bash:npm run`).
    var allow: [String]
    var sandboxed: Bool
}

/// One version of a company skill: what runs are given, attached to the company, a department, a role or a project.
struct SkillInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var version: Int64
    var attachedTo: String
    var attachedID: Int64?
    var attachedRole: String?
    var bytes: Int64
}

/// API minor 11 from the app: a project's permission policy (read, replace whole) and the company's skills (list,
/// publish a new version).
extension CitadelServer {
    func policy(project: Int64) async -> PolicyInfo? {
        await read("getProjectPolicy") {
            guard case .ok(let ok) = try await client.getProjectPolicy(path: .init(id: project)) else { return nil }
            return PolicyInfo(try ok.body.json)
        }
    }

    /// Replaces the policy whole (audited as `project.policy_set`); a blank allowlist entry is refused.
    func setPolicy(project: Int64, _ policy: PolicyInfo) async -> Result<PolicyInfo, ServerAnswer> {
        let body = Schemas.ProjectPolicy(
            allow: policy.allow, mode: .init(value1: .init(rawValue: policy.mode), value2: policy.mode),
            sandboxed: policy.sandboxed)
        return await attempt({ try await client.setProjectPolicy(path: .init(id: project), body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return PolicyInfo(try ok.body.json)
        }
    }

    /// Every version of the company's skills, by name then version.
    func skills(company: Int64) async -> [SkillInfo]? {
        await read("listSkills") {
            guard case .ok(let ok) = try await client.listSkills(path: .init(id: company)) else { return nil }
            return try ok.body.json.map(SkillInfo.init)
        }
    }

    /// Publishes a new version of `name` (1 for a new name); an old version is never edited.
    func publishSkill(
        company: Int64, name: String, body: String, attachTo: String, attachID: Int64?, attachRole: String?
    ) async -> ServerAnswer? {
        await act {
            try await client.publishSkill(
                path: .init(id: company),
                body: .json(
                    .init(attachId: attachID, attachRole: attachRole, attachTo: attachTo, body: body, name: name)))
        }
    }
}

extension PolicyInfo {
    init(_ policy: Schemas.ProjectPolicy) {
        self.init(mode: policy.mode.word, allow: policy.allow ?? [], sandboxed: policy.sandboxed ?? false)
    }
}

extension SkillInfo {
    init(_ skill: Schemas.AgentSkill) {
        self.init(
            id: skill.id, name: skill.name, version: skill.version, attachedTo: skill.attachedTo,
            attachedID: skill.attachedId, attachedRole: skill.attachedRole, bytes: skill.bytes)
    }
}
