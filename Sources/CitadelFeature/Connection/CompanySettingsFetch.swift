import CitadelClient
import Foundation

/// A device key, never the key: its name, when it was made and last used, and whether it is revoked.
struct DeviceInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var createdAt: Date
    var lastUsedAt: Date?
    var revokedAt: Date?
}

/// One audited change: what happened (`issue.in_review`), to what, by whom, when.
struct AuditLine: Identifiable, Equatable, Sendable {
    var id: Int64 { seq }
    let seq: Int64
    var at: Date
    var action: String
    var actor: String
    var entity: String?
    var details: [String: String]
}

extension AuditLine {
    init(_ entry: Schemas.AuditEntry) {
        let actor: String =
            switch entry.actor {
            case .agent(let a): "agent:\(a.agentId)"
            case .runner(let r): "runner:\(r.runnerId)"
            case .user: "you"
            case .system: "Citadel"
            }
        self.init(
            seq: entry.seq, at: entry.at, action: entry.action, actor: actor,
            entity: entry.entityKind.map { kind in entry.entityId.map { "\(kind) \($0)" } ?? kind },
            details: flatFields(entry.details.value))
    }
}

/// Company settings' sections backed by the API: devices (list, revoke), account assignment (assign, unassign —
/// the admin's), and the audit log (`listAudit`, paged).
extension CitadelServer {
    func devices() async -> [DeviceInfo]? {
        await read("listDevices") {
            guard case .ok(let ok) = try await scoped(to: nil).client.listDevices() else { return nil }
            return try ok.body.json.map {
                DeviceInfo(
                    id: $0.id, name: $0.name, createdAt: $0.createdAt, lastUsedAt: $0.lastUsedAt,
                    revokedAt: $0.revokedAt)
            }
        }
    }

    func revokeDevice(_ id: Int64) async -> ServerAnswer? {
        await act { try await scoped(to: nil).client.revokeDevice(path: .init(id: id)) }
    }

    /// Lets (or stops letting) the company's runs use the account.
    func setAccount(_ account: Int64, assigned: Bool, company: Int64) async -> ServerAnswer? {
        let pool = scoped(to: nil).client
        return await act {
            if assigned { return try await pool.assignAccount(path: .init(id: account, companyId: company)) }
            return try await pool.unassignAccount(path: .init(id: account, companyId: company))
        }
    }

    /// A page of the company's audit log (API minor 16), newest first: rows below `before` (the previous page's
    /// `next`), only actions starting with `kind` when set, only rows by `actor` (`user`, `agent`, `system`; API minor
    /// 17) when set. `next` is absent on the last page.
    func auditLog(before: Int64? = nil, kind: String? = nil, actor: String? = nil) async -> (
        lines: [AuditLine], next: Int64?
    )? {
        await read("listAudit") {
            guard
                case .ok(let ok) = try await client.listAudit(
                    query: .init(before: before, limit: 100, kind: kind.nonEmpty, actor: actor.nonEmpty))
            else { return nil }
            let page = try ok.body.json
            return (page.items.map(AuditLine.init), page.nextBefore)
        }
    }
}
