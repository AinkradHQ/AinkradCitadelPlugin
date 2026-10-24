import CitadelClient
import Foundation

extension Schemas.KnowledgeKind: OpenWord {}
extension Schemas.KnowledgeStatus: OpenWord {}

/// A project knowledge entry (API minor 16): what runs are given once accepted, an agent's proposal until then.
struct KnowledgeInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    /// `decision`, `landmine`, `state`, `retro`, or a newer server's word.
    var kind: String
    /// `proposed`, `accepted`, `rejected`, `retired`, or a newer server's word.
    var status: String
    var title: String
    var body: String
    /// The list cut the body at 16 KiB.
    var bodyTruncated: Bool
    /// The proposing agent; `nil` for an entry the admin added.
    var proposedBy: Int64?
    var rationale: String?
    /// Why it was accepted, rejected or retired.
    var reason: String?
    /// What accepting it applies its body to: `spec` or `profile.<field>`.
    var target: String?
    var supersededBy: Int64?
    var supersedes: Int64?
    var updatedAt: Date
}

extension KnowledgeInfo {
    init(_ entry: Schemas.Knowledge) {
        self.init(
            id: entry.id, kind: entry.kind.word, status: entry.status.word, title: entry.title, body: entry.body,
            bodyTruncated: entry.bodyTruncated, proposedBy: entry.proposedByAgentId, rationale: entry.rationale,
            reason: entry.reason ?? entry.retiredReason, target: entry.target, supersededBy: entry.supersededBy,
            supersedes: entry.supersedes, updatedAt: entry.updatedAt)
    }
}

/// API minor 16's knowledge review: a project's entries (every status), accepting or rejecting a proposal, and
/// retiring or superseding an accepted entry. A write answers `nil` when done, else the server's refusal.
extension CitadelServer {
    func knowledge(project: Int64) async -> [KnowledgeInfo]? {
        await read("listKnowledge") {
            guard case .ok(let ok) = try await client.listKnowledge(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(KnowledgeInfo.init)
        }
    }

    /// Accepts (a spec or profile proposal applies its body) or rejects (`reason` required) a proposal.
    func decide(knowledge id: Int64, accept: Bool, reason: String?) async -> ServerAnswer? {
        let body = Schemas.KnowledgeDecision(reason: reason)
        return await act {
            if accept { return try await client.acceptKnowledge(path: .init(id: id), body: .json(body)) }
            return try await client.rejectKnowledge(path: .init(id: id), body: .json(body))
        }
    }

    /// Retires an accepted entry: kept for history, never given to a run again.
    func retire(knowledge id: Int64, reason: String) async -> ServerAnswer? {
        await act { try await client.retireKnowledge(path: .init(id: id), body: .json(.init(reason: reason))) }
    }

    /// A new version of an accepted entry; the old one is retired.
    func supersede(knowledge id: Int64, title: String?, body: String, reason: String?) async -> ServerAnswer? {
        await act {
            try await client.supersedeKnowledge(
                path: .init(id: id), body: .json(.init(body: body, reason: reason, title: title)))
        }
    }
}
