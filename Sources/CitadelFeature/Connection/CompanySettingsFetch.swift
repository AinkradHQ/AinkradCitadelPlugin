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

/// Company settings' sections backed by the API: devices (list, revoke), account assignment (assign, unassign —
/// the admin's), and the audit log (the audited changes the event feed carries).
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

    /// The company's newest audited changes, newest first: the audit entries among its last `window` events.
    func auditLog(window: Int64 = 1000) async -> [AuditLine]? {
        let latest: Int64? = await read("latestEvent") {
            guard case .ok(let ok) = try await client.latestEvent() else { return nil }
            return try ok.body.json.seq
        }
        guard let latest, let page = try? await replay(after: max(0, latest - window), limit: Int(window)) else {
            return nil
        }
        return page.items.compactMap { frame -> AuditLine? in
            guard let event = frame.event, case .audit(let audit) = event.payload else { return nil }
            let actor: String =
                switch audit.actor {
                case .agent(let a): "agent:\(a.agentId)"
                case .runner(let r): "runner:\(r.runnerId)"
                case .user: "you"
                case .system: "Citadel"
                }
            return AuditLine(
                seq: event.seq, at: event.at, action: audit.action, actor: actor,
                entity: audit.entityKind.map { kind in audit.entityId.map { "\(kind) \($0)" } ?? kind },
                details: flatFields(audit.details.value))
        }
        .reversed()
    }
}
