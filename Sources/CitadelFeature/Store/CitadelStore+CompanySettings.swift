import Foundation

/// Company settings' Devices, Account assignment and Audit log sections; a refusal becomes `actionFailure`.
extension CitadelStore {
    func loadDevices() {
        guard let server, let page = model?.limitsPage else { return }
        Task { page.devices = await server.devices() ?? page.devices ?? [] }
    }

    /// Revokes a device's key: that device can no longer reach the server.
    func revoke(_ device: DeviceInfo) {
        perform("Couldn't revoke \(device.name)", outcome: "Its key still works.", done: { self.loadDevices() }) {
            await $0.revokeDevice(device.id)
        }
    }

    /// Lets (or stops letting) this company's runs use the account; the pool is read again.
    func setAccount(_ account: PoolAccount, assigned: Bool) {
        guard let company = model?.companyID else { return }
        perform(
            assigned ? "Couldn't assign \(account.label)" : "Couldn't unassign \(account.label)",
            outcome: "Its assignment is unchanged.", done: { self.loadAccountsPage() }
        ) { await $0.setAccount(account.id, assigned: assigned, company: company) }
    }

    /// The audit log's newest page, with the section's filters: the type chip's prefix and, from API minor 17, the
    /// actor chip's kind (an older server gets every actor and the section filters them).
    func loadAuditLog() {
        guard let server, let page = model?.limitsPage else { return }
        let kind = page.auditKind
        let actor = auditActorParameter(page)
        Task {
            guard let (lines, next) = await server.auditLog(kind: kind, actor: actor) else {
                page.auditLog = page.auditLog ?? []
                return
            }
            guard kind == page.auditKind, actor == auditActorParameter(page) else { return }
            page.auditLog = lines
            page.auditNext = next
        }
    }

    /// "Load more": the next older page, appended.
    func loadMoreAudit() {
        guard let server, let page = model?.limitsPage, let before = page.auditNext else { return }
        let kind = page.auditKind
        let actor = auditActorParameter(page)
        Task {
            guard let (lines, next) = await server.auditLog(before: before, kind: kind, actor: actor),
                kind == page.auditKind, actor == auditActorParameter(page), page.auditNext == before
            else { return }
            page.auditLog = (page.auditLog ?? []) + lines
            page.auditNext = next
        }
    }

    /// The actor chip as the API's `actor` (`user`, `agent`, `system`); nil for everyone, and for an older server.
    private func auditActorParameter(_ page: LimitsPage) -> String? {
        guard serverSupports(minor: Self.structureMinor) else { return nil }
        return switch page.auditActor {
        case "you": "user"
        case "agents": "agent"
        case "system": "system"
        default: nil
        }
    }

    func loadSkills() {
        guard let server, let model else { return }
        Task {
            model.limitsPage.skills = await server.skills(company: model.companyID) ?? model.limitsPage.skills ?? []
        }
    }

    /// Publishes a new version of a skill; `done` closes the sheet once the server took it.
    func publishSkill(
        name: String, body: String, attachTo: String, attachID: Int64?, attachRole: String?,
        done: @escaping @MainActor () -> Void
    ) {
        guard let company = model?.companyID else { return }
        perform(
            "Couldn't publish \(name)", outcome: "No new version was made.",
            done: {
                done()
                self.loadSkills()
            }
        ) {
            await $0.publishSkill(
                company: company, name: name, body: body, attachTo: attachTo, attachID: attachID, attachRole: attachRole
            )
        }
    }
}
