import Foundation

@testable import CitadelFeature

/// Company settings' sections as the prototype stages them (`settings.js`): devices, audit, skills.
@MainActor
extension CompanyFixture {
    static func companySettingsPage(_ model: CompanyModel, section: CompanySettingsSection) {
        limitsPage(model)
        accountsPage(model)
        let page = model.limitsPage
        page.section = section
        page.selected = "run.stall_after_secs"
        page.refused = [:]
        page.devices = [
            DeviceInfo(
                id: 1, name: "Ahmed's MacBook Pro", createdAt: now.addingTimeInterval(-40 * 86_400), lastUsedAt: now),
            DeviceInfo(
                id: 2, name: "Ahmed's iPhone 17", createdAt: now.addingTimeInterval(-20 * 86_400),
                lastUsedAt: now.addingTimeInterval(-720)),
            DeviceInfo(
                id: 3, name: "CI · release workflow", createdAt: now.addingTimeInterval(-9 * 86_400),
                lastUsedAt: now.addingTimeInterval(-2 * 86_400)),
            DeviceInfo(
                id: 4, name: "Old Mac mini", createdAt: now.addingTimeInterval(-90 * 86_400),
                lastUsedAt: now.addingTimeInterval(-30 * 86_400), revokedAt: now.addingTimeInterval(-86_400)),
        ]
        func line(
            _ seq: Int64, _ hoursAgo: Double, _ action: String, _ actor: String, _ entity: String?,
            _ details: [String: String]
        )
            -> AuditLine
        {
            AuditLine(
                seq: seq, at: now.addingTimeInterval(-hoursAgo * 3600), action: action, actor: actor, entity: entity,
                details: details)
        }
        page.auditLog = [
            line(
                18_440, 1, "approval.requested", "agent:3", "approval 21",
                ["kind": "sprint_commit", "sprint": "CIT S5"]),
            line(18_431, 3, "account.limited", "Citadel", "account 2", ["old": "running", "new": "at limit · 5 h"]),
            line(
                18_420, 4, "approval.approved", "you", "issue 58", ["kind": "pr_merge", "old": "open", "new": "merged"]),
            line(18_402, 14, "device.revoked", "you", "device 4", ["old": "active", "new": "revoked"]),
            line(
                18_390, 26, "setting.set", "agent:7", "setting run.token_cap",
                ["key": "run.token_cap", "scope": "project:1", "old": "200000", "new": "300000"]),
            line(
                18_377, 27, "setting.set", "you", "setting workspace.idle_secs",
                ["key": "workspace.idle_secs", "scope": "runner:3", "old": "86400", "new": "43200"]),
            line(
                18_350, 28, "setting.set", "you", "setting artifact.company_quota_bytes",
                [
                    "key": "artifact.company_quota_bytes", "scope": "company:1", "old": "20000000000",
                    "new": "50000000000",
                ]),
            line(
                18_301, 44, "setting.set", "you", "setting run.stall_after_secs",
                ["key": "run.stall_after_secs", "scope": "project:1", "old": "900", "new": "600"]),
        ]
        page.auditNext = 18_300
        page.skills = [
            SkillInfo(
                id: 1, name: "rust-review", version: 3, attachedTo: "role", attachedID: nil, attachedRole: "dev",
                bytes: 2_400),
            SkillInfo(
                id: 2, name: "release-notes", version: 1, attachedTo: "company", attachedID: nil, attachedRole: nil,
                bytes: 1_100),
            SkillInfo(
                id: 3, name: "swiftui-design-lint", version: 2, attachedTo: "project", attachedID: 2, attachedRole: nil,
                bytes: 3_800),
        ]
    }
}
