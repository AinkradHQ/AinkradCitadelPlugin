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

    func loadAuditLog() {
        guard let server, let page = model?.limitsPage else { return }
        Task { page.auditLog = await server.auditLog() ?? page.auditLog ?? [] }
    }
}
