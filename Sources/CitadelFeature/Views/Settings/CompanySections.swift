import AinkradAppKit
import SwiftUI

/// Company settings › Members & devices: the owner, and every device key as a card — never the key itself — with
/// Revoke confirmed in place. Pairing and invites wait for the server.
struct DevicesSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var revoking: Int64?
    @Environment(\.ainkradSkin) private var skin

    private var page: LimitsPage { model.limitsPage }

    var body: some View {
        SettingsScroll {
            SettingsHero(section: .devices) {
                AinkradDockButton("Pair a device", systemImage: "plus", tone: .primary, isEnabled: false) {}
                    .help("Pairing with a code needs the server's pairing flow — use citadel key create meanwhile")
            }
            SettingsCard(title: "Members") {
                memberRow(
                    avatar: AnyView(Avatar(initials: initials(store.userName ?? "You"))),
                    title: store.userName ?? "You",
                    chip: "owner", detail: "every approval · admin on the server"
                ) {
                    Text("you").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
                memberRow(
                    avatar: AnyView(Avatar(initials: "＋", ghost: true)), title: "Invite a member", chip: nil,
                    detail: "approvals can route to them per project"
                ) {
                    ServerSoonChip()
                    AinkradDockButton("Invite…", isEnabled: false) {}
                }
            }
            SettingsCard(
                title: "Device keys", hint: page.devices.map { "\($0.filter { $0.revokedAt == nil }.count) keys" }
            ) {
                if page.devices?.isEmpty == true {
                    Text("No devices.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).padding(
                        .vertical, skin.size.s10)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s260), spacing: skin.size.s10)],
                    spacing: skin.size.s10
                ) {
                    ForEach(page.devices ?? []) { device in deviceCard(device) }
                }
                .padding(.top, skin.size.s6)
                .padding(.bottom, skin.size.s10)
                (Text("Keys are created on a device and approved here, or with ")
                    + Text(verbatim: "citadel key create --device \"name\"").monospaced()
                    + Text(". A revoked key is refused on its next request."))
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .padding(.bottom, skin.size.s8)
            }
        }
        .onAppear { store.loadDevices() }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private func memberRow<Trailing: View>(
        avatar: AnyView, title: String, chip: String?, detail: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: skin.size.s12) {
            avatar
            VStack(alignment: .leading, spacing: skin.size.s1) {
                HStack(spacing: skin.size.s6) {
                    Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    if let chip { AinkradStatePill(text: chip, tint: skin.color(skin.palette.accentPrimary)) }
                }
                Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: skin.size.s8)
            trailing()
        }
        .padding(.vertical, skin.size.s12)
    }

    private func deviceCard(_ device: DeviceInfo) -> some View {
        let revoked = device.revokedAt != nil
        let recent = device.lastUsedAt.map { Date().timeIntervalSince($0) < 120 } ?? false
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s10) {
                Image(systemName: "laptopcomputer").citadelFont("t16").foregroundStyle(
                    skin.color(skin.palette.accentViolet)
                )
                .frame(width: skin.size.s40, height: skin.size.s40)
                .background(
                    skin.color(skin.palette.accentViolet).opacity(skin.opacity.o14),
                    in: RoundedRectangle(cornerRadius: skin.size.s12))
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(device.name).citadelFont("t13", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary)
                    ).lineLimit(1)
                    Text("added \(device.createdAt.formatted(date: .abbreviated, time: .omitted))").citadelFont(
                        "t10_5", mono: true
                    )
                    .foregroundStyle(skin.color(skin.text.faint))
                }
                Spacer(minLength: 0)
                if revoked { AinkradStatePill(text: "revoked", tint: skin.color(skin.palette.danger)) }
            }
            HStack(spacing: skin.size.s6) {
                PulseDot(isOn: recent && !revoked)
                Text(footLine(device, recent: recent)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .lineLimit(1)
                Spacer(minLength: skin.size.s4)
                if !revoked {
                    if revoking == device.id {
                        AinkradDockButton("Keep", height: skin.size.s28) { revoking = nil }
                        AinkradDockButton("Revoke key", tone: .danger, height: skin.size.s28) {
                            revoking = nil
                            store.revoke(device)
                        }
                    } else {
                        AinkradDockButton("Revoke", tone: .danger, height: skin.size.s28) { revoking = device.id }
                    }
                }
            }
        }
        .padding(skin.size.s14)
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o18), in: shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
        .opacity(revoked ? skin.opacity.o50 : 1)
    }

    /// "used now" / "last used 12m ago" / "never used".
    private func footLine(_ device: DeviceInfo, recent: Bool) -> String {
        if let revoked = device.revokedAt { return "revoked \(revoked.formatted(date: .abbreviated, time: .omitted))" }
        guard let used = device.lastUsedAt else { return "never used" }
        return recent ? "used now" : "last used \(Fmt.age(Date().timeIntervalSince(used))) ago"
    }
}

/// A 42 pt round avatar: initials on the accent gradient, or a dashed ghost.
private struct Avatar: View {
    let initials: String
    var ghost = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(initials).citadelFont("t14", weight: "bold")
            .foregroundStyle(skin.color(ghost ? skin.text.faint : .palette("foreground", 1)))
            .frame(width: skin.size.s42, height: skin.size.s42)
            .background(
                ghost
                    ? AnyShapeStyle(skin.color(.palette("foreground", skin.opacity.o05)))
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)), in: Circle()
            )
            .overlay(
                Circle().strokeBorder(
                    skin.color(.palette("foreground", ghost ? skin.opacity.o20 : 0)),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s3])))
    }
}

/// A 7 pt status dot that pulses green when on.
struct PulseDot: View {
    let isOn: Bool
    @State private var pulse = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let green = skin.color(skin.palette.success)
        Circle().fill(isOn ? green : skin.color(.palette("foreground", skin.opacity.o20)))
            .frame(width: skin.size.s7, height: skin.size.s7)
            .shadow(color: isOn ? green : .clear, radius: skin.size.s8)
            .opacity(isOn && pulse ? skin.opacity.o40 : 1)
            .onAppear {
                guard isOn, !reduceMotion else { return }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.8)).repeatForever())
                { pulse = true }
            }
    }
}

/// Company settings › Accounts: which pool accounts this company's runs may use, with each one's use; the switch
/// assigns or unassigns (Undo). Another device sees the company's own accounts, read-only.
struct AccountAssignmentSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        SettingsScroll {
            SettingsHero(section: .accounts, title: "Account assignment") {
                AinkradDockButton("Account pool", systemImage: "chevron.right") {
                    store.isShowingSettings = false
                    store.screen = .accounts
                }
            }
            SettingsCard(
                title: "Assigned accounts",
                hint: page.canSeeWholePool ? "the pool picks among them" : "only the admin's device assigns them"
            ) {
                VStack(spacing: skin.size.s8) {
                    ForEach(page.accounts) { account in row(account) }
                }
                .padding(.top, skin.size.s6)
                .padding(.bottom, skin.size.s10)
            }
            Text(
                "Window lengths and caps are per account, pool-wide (decision 56). This company may only override the warn % — see Limits."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).padding(.horizontal, skin.size.s6)
        }
        .onAppear { store.loadAccountsPage() }
    }

    private func row(_ account: PoolAccount) -> some View {
        let assigned = account.companyIDs.contains(model.companyID)
        let use = account.windows(warnPercent: 80).map(\.fraction).max()
        let tint = AgentLook.harness(account.harness)?.color ?? skin.color(skin.palette.accentPrimary)
        let ringTint = (use ?? 0) >= 1 ? status.danger : (use ?? 0) >= 0.8 ? status.warning : tint
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        return HStack(spacing: skin.size.s12) {
            HarnessTag(harness: account.harness, size: skin.size.s36)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(account.label).citadelFont("t13", weight: "semibold", mono: true).foregroundStyle(
                    skin.color(skin.text.primary))
                Text(detail(account)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s8)
            if assigned, let use {
                AinkradRingGauge(value: use, tint: ringTint, diameter: skin.size.s40, lineWidth: skin.size.s5) {
                    Text(verbatim: "\(Int((use * 100).rounded()))%").citadelFont("t9_5", weight: "semibold", mono: true)
                }
            } else if !assigned {
                Text("not assigned").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            if page.canSeeWholePool {
                AinkradToggle(isOn: Binding(get: { assigned }, set: { toggle(account, $0) }))
            } else {
                AinkradStatePill(text: "assigned", tint: status.success)
            }
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o18), in: shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
        .opacity(assigned ? 1 : skin.opacity.o50)
    }

    /// "Claude · Max 20× · subscription · at 5 h limit until 13:05".
    private func detail(_ account: PoolAccount) -> String {
        var parts = [AgentLook.harnessName(account.harness)]
        if let tier = account.planTier { parts.append(tier) }
        parts.append(account.billing)
        if account.status == "limited" {
            parts.append(
                "at limit\(account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? "")"
            )
        } else if account.status != "active" {
            parts.append(account.status)
        }
        return parts.joined(separator: " · ")
    }

    private func toggle(_ account: PoolAccount, _ on: Bool) {
        store.setAccount(account, assigned: on)
        let company = store.company?.name ?? "the company"
        store.toast(
            AinkradRichToast(
                title: "\(account.label) \(on ? "assigned to" : "removed from") \(company)",
                body: on
                    ? "New runs may use it from now."
                    : "Runs on it finish; new runs fall back along each agent's chain.",
                actions: [AinkradRichToastAction("Undo") { store.setAccount(account, assigned: !on) }]))
    }
}
