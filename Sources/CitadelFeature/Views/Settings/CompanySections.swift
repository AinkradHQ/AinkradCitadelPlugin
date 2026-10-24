import AinkradAppKit
import SwiftUI

/// Company settings › Devices: every device key (never the key itself), and Revoke.
struct DevicesSection: View {
    let store: CitadelStore
    let page: LimitsPage
    @State private var revoking: DeviceInfo?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Devices", crumb: Text("each Mac or CLI that holds a key to this server"))
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    if page.devices?.isEmpty == true {
                        Text("No devices.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                    ForEach(page.devices ?? []) { device in
                        AinkradListRow(
                            leading: {
                                Image(systemName: "laptopcomputer").foregroundStyle(skin.color(skin.text.muted))
                            },
                            title: device.name, subtitle: line(device),
                            trailing: {
                                if device.revokedAt != nil {
                                    AinkradBadge(text: "revoked")
                                } else {
                                    AinkradButton(title: "Revoke…", style: .danger) { revoking = device }
                                        .outlined().compact().fixedSize()
                                }
                            })
                    }
                }
                .padding(.horizontal, skin.size.s14)
            }
        }
        .onAppear { store.loadDevices() }
        .ainkradConfirmDialog(
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            title: "Revoke \(revoking?.name ?? "this device")?",
            message: "Its key stops working at once; that device has to be paired again with a new key.",
            confirmTitle: "Revoke"
        ) { if let revoking { store.revoke(revoking) } }
    }

    /// "added Oct 3 · last used 4 min ago".
    private func line(_ device: DeviceInfo) -> String {
        var parts = ["added \(device.createdAt.formatted(date: .abbreviated, time: .omitted))"]
        if let used = device.lastUsedAt { parts.append("last used \(Fmt.age(Date().timeIntervalSince(used))) ago") }
        if let revoked = device.revokedAt {
            parts.append("revoked \(revoked.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Company settings › Account assignment: which provider accounts of the pool this company's runs may use.
/// Assigning is the admin's; another device sees the company's own accounts, read-only.
struct AccountAssignmentSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(
                title: "Account assignment",
                crumb: Text(
                    page.canSeeWholePool
                        ? "the pool's accounts this company's runs may use"
                        : "this company's accounts · only the admin's device assigns them"))
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    ForEach(page.accounts) { account in
                        let assigned = account.companyIDs.contains(model.companyID)
                        AinkradListRow(
                            leading: { EmptyView() },
                            title: account.label,
                            subtitle: [AgentLook.harnessName(account.harness), account.billing, account.status]
                                .joined(separator: " · "),
                            trailing: {
                                if page.canSeeWholePool {
                                    AinkradToggle(
                                        isOn: Binding(
                                            get: { assigned }, set: { store.setAccount(account, assigned: $0) }))
                                } else {
                                    AinkradBadge(text: "assigned", status: .success)
                                }
                            })
                    }
                }
                .padding(.horizontal, skin.size.s14)
            }
        }
        .onAppear { store.loadAccountsPage() }
    }
}

/// Company settings › Audit log: every audited change at this company, newest first — who did what to which
/// entity, when. Read from the event feed, which carries each audit entry.
struct AuditLogSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let lines = model.limitsPage.auditLog
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Audit log", crumb: Text("the newest audited changes, newest first")) {
                AinkradIconButton(systemName: "arrow.clockwise", size: skin.size.s30, tooltip: "Read it again") {
                    store.loadAuditLog()
                }
                .outlineBox()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s6) {
                    if lines?.isEmpty == true {
                        Text("Nothing audited yet.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                    ForEach(lines ?? []) { line in
                        HStack(alignment: .firstTextBaseline, spacing: skin.size.s12) {
                            Text(line.at.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                                .frame(width: skin.size.s110, alignment: .leading)
                            Text(line.action).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
                            Text(describe(line)).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s14)
            }
        }
        .onAppear { store.loadAuditLog() }
    }

    /// "by Mira · issue 42" — agents by name.
    private func describe(_ line: AuditLine) -> String {
        let actor =
            line.actor.hasPrefix("agent:")
            ? Int64(line.actor.dropFirst(6)).flatMap { model.agent($0)?.name } ?? line.actor : line.actor
        return ["by \(actor)", line.entity].compactMap { $0 }.joined(separator: " · ")
    }
}
