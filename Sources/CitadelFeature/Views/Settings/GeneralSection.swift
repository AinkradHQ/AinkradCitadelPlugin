import AinkradAppKit
import CitadelClient
import SwiftUI

/// Company settings › General (`settings.js` General): identity (logo, name, kind, colour, the CEO), time, defaults
/// for new agents, this Mac's connection, and the danger zone. From API minor 17 the profile is stored (colour, time
/// zone, working hours and days, logo); on an older server those stay "not stored yet". From API minor 18 the
/// fallback chain default is the chain preset marked default. Sprint approval, sandbox and the budget default have
/// no server field yet.
struct GeneralSection: View {
    let store: CitadelStore
    @State private var name = ""
    @State private var kind: Components.Schemas.CompanyKind.Value1Payload = .own
    @State private var color: String?
    @State private var timezone: String?
    @State private var start = SettingsCompanyDefaults.start
    @State private var end = SettingsCompanyDefaults.end
    @State private var days = SettingsCompanyDefaults.days
    @State private var saving: Bool?
    @Environment(\.ainkradSkin) private var skin

    private var company: Components.Schemas.Company? { store.company }
    private var supported: Bool { store.serverSupports(minor: CitadelStore.structureMinor) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Whether a value differs from what the company stores; the fields an older server does not store never count.
    private var changed: Bool {
        guard let company else { return false }
        if trimmedName != company.name || kind != (company.kind.value1 ?? .own) { return true }
        guard supported else { return false }
        return color != company.color || timezone != company.timezone
            || start != (company.workStart ?? SettingsCompanyDefaults.start)
            || end != (company.workEnd ?? SettingsCompanyDefaults.end)
            || days != (company.workDays ?? SettingsCompanyDefaults.days)
    }

    var body: some View {
        SettingsScroll {
            SettingsHero(
                section: .general,
                subtitle: company.map {
                    "\($0.name) · \($0.kind.value1 == .client ? "client company" : "your own company")"
                }
            ) {
                AinkradDockButton(
                    saving == true ? "Saving…" : saving == false ? "Saved ✓" : "Save changes", systemImage: "checkmark",
                    tone: .primary,
                    isEnabled: changed && saving == nil && !trimmedName.isEmpty
                ) { save() }
            }
            if let company { identity(company) }
            time
            defaults
            connection
            SettingsCard(title: "Danger zone", danger: true) {
                SettingsRow(
                    label: "Archive company",
                    hint: "Stops every run, keeps history read-only, frees its accounts and runners."
                ) {
                    ServerSoonChip()
                    AinkradDockButton("Archive…", tone: .danger, isEnabled: false) {}
                }
            }
        }
        .onAppear(perform: reset)
        .task { store.loadChainPresets() }
        .onChange(of: company?.name) { _, _ in if saving == nil { reset() } }
    }

    private func reset() {
        name = company?.name ?? ""
        kind = company?.kind.value1 ?? .own
        color = company?.color
        timezone = company?.timezone
        start = company?.workStart ?? SettingsCompanyDefaults.start
        end = company?.workEnd ?? SettingsCompanyDefaults.end
        days = company?.workDays ?? SettingsCompanyDefaults.days
    }

    private func save() {
        saving = true
        let change = Components.Schemas.CompanyChange(
            color: color, kind: .init(value1: kind), name: trimmedName, timezone: timezone, workDays: days,
            workEnd: end, workStart: start)
        store.saveCompany(change) { ok in
            saving = ok ? false : nil
            guard ok else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                saving = nil
            }
        }
    }

    // MARK: Identity

    private func identity(_ company: Components.Schemas.Company) -> some View {
        SettingsCard(title: "Identity") {
            HStack(spacing: skin.size.s18) {
                logoTile(company)
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    AinkradTextField(text: $name, placeholder: "Company name").fieldHeight(skin.size.s40)
                    AinkradSegmentedPicker(
                        items: [Components.Schemas.CompanyKind.Value1Payload.own, .client], selection: $kind,
                        label: { $0 == .own ? "Own company" : "Client" }
                    )
                    .controlSize(.small)
                    .fixedSize()
                    SettingsColorSwatches(color: $color, enabled: supported)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let model = store.model, let ceo = model.ceo { ceoTile(ceo, model) }
            }
            .padding(.top, skin.size.s16)
            .padding(.bottom, skin.size.s10)
        }
    }

    /// The mark as the draft reads, with the chosen colour; the logo or the initial, as the other screens draw it.
    private func logoTile(_ company: Components.Schemas.Company) -> some View {
        var preview = company
        preview.name = trimmedName.isEmpty ? company.name : trimmedName
        preview.color = color
        return VStack(spacing: skin.size.s6) {
            CompanyMark(
                company: preview, size: skin.size.s80, live: false, radius: skin.size.s24, fontKey: "t34",
                logo: store.logos.images[company.id])
            if supported {
                AinkradTapArea(help: "A PNG, JPEG or WebP up to 2 MB") {
                    uploadLogo()
                } label: {
                    Text(company.logoUrl == nil ? "Upload logo" : "Change logo").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.palette.accentPrimary))
                }
                if company.logoUrl != nil {
                    AinkradTapArea(help: "Back to the colour and the initial") {
                        store.removeCompanyLogo()
                    } label: {
                        Text("Remove logo").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            } else {
                Text("Upload logo").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .help("The server stores no company logo yet")
            }
        }
    }

    private func uploadLogo() {
        guard let picked = SettingsLogoFile.choose(for: company?.name ?? "the company", store: store) else { return }
        store.setCompanyLogo(picked.data, type: picked.type)
    }

    private func ceoTile(_ ceo: AgentInfo, _ model: CompanyModel) -> some View {
        AinkradTapArea(help: "Open \(ceo.name)") {
            store.open(.agent(ceo.id))
        } label: {
            VStack(spacing: skin.size.s4) {
                AgentFigure(agent: ceo, model: model, size: skin.size.s56)
                Text(ceo.name).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Text("CEO · \(ceo.harnessName) · \(ceo.model)").citadelFont("t10_5").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s12)
            .background(
                skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
                in: RoundedRectangle(cornerRadius: skin.size.s16)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradHoverLift(skin.size.s2, cornerRadius: skin.size.s16)
    }

    // MARK: Time and defaults

    private var time: some View {
        SettingsCard(title: "Time") {
            SettingsRow(label: "Time zone", hint: "approvals and quiet hours use it") {
                if supported {
                    SettingsTimeZoneMenu(zone: $timezone)
                } else {
                    ServerSoonChip()
                    AinkradDockButton("—", systemImage: "globe", isEnabled: false) {}
                }
            }
            SettingsRow(
                label: "Working hours", hint: "drag the ends · agents run 24/7 · approvals wait for these hours"
            ) {
                if supported { SettingsWorkTrack(start: $start, end: $end) } else { DayTrack() }
            }
            SettingsRow(label: "Working days") {
                if supported {
                    SettingsWorkDays(days: $days)
                } else {
                    unstoredDays
                }
            }
        }
    }

    /// The day letters with no server behind them yet.
    private var unstoredDays: some View {
        HStack(spacing: skin.size.s4) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                Text(day).citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
                    .frame(width: skin.size.s28, height: skin.size.s28)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s8))
            }
        }
        .help("The server stores no working days yet")
    }

    private var defaults: some View {
        SettingsCard(title: "Defaults for new agents") {
            SettingsRow(label: "Sprint approval", hint: "who commits a sprint") {
                ServerSoonChip()
                disabledSegment(["You approve", "PO alone"])
            }
            SettingsRow(label: "Sandbox", hint: "what a new agent may touch") {
                ServerSoonChip()
                disabledSegment(["workspace-write", "read-only", "full"])
            }
            SettingsRow(label: "Fallback chain", hint: "preset a new hire starts with") {
                if store.chainPresetsOn, let model = store.model {
                    AinkradMenuButton(
                        items: model.chainPresets.map { preset in
                            AinkradMenuItem(title: preset.name, systemName: preset.isDefault ? "checkmark" : nil) {
                                if !preset.isDefault { store.makeDefaultChainPreset(preset) }
                            }
                        }
                    ) {
                        HStack(spacing: skin.size.s6) {
                            Text(model.defaultChainPreset?.name ?? "None").citadelFont("t12")
                            Image(systemName: "chevron.down")
                        }
                        .foregroundStyle(skin.color(skin.text.primary))
                        .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s6)
                        .background(skin.color(.palette("foreground", skin.opacity.o05)), in: Capsule())
                    }
                    .disabled(model.chainPresets.isEmpty)
                    .fixedSize()
                } else {
                    ServerSoonChip()
                    AinkradDockButton("Claude first", systemImage: "chevron.down", isEnabled: false) {}
                }
            }
            SettingsRow(label: "Agent figures have eyes", hint: "decision 63 · always on in this build") {
                AinkradToggle(isOn: .constant(true)).disabled(true)
            }
            SettingsRow(label: "Monthly budget", hint: "per new agent · warn at 80%") {
                ServerSoonChip()
                AinkradValuePill(text: "—") { _ in }.editable(false)
                AinkradDockButton("Limits") { store.model?.limitsPage.section = .limits }
            }
        }
    }

    private func disabledSegment(_ options: [String]) -> some View {
        AinkradSegmentedPicker(items: options, selection: .constant(options[0]), label: { $0 })
            .controlSize(.small).fixedSize().disabled(true)
    }

    // MARK: Connection

    private var connection: some View {
        SettingsCard(title: "Connection", hint: "this Mac") {
            SettingsRow(label: "Server", hint: "Plain http is accepted only for a server on this Mac.") {
                Text(store.settings.document.server ?? "Not set").citadelFont("t12", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).textSelection(.enabled)
            }
            SettingsRow(label: "Device key", hint: "Kept in your Keychain; sent only as a bearer header.") {
                Text(store.storedKey.map { DeviceKeyStore.masked($0) } ?? "Not set").citadelFont("t12", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
            }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradDockButton("Change server or key…", systemImage: "arrow.left.arrow.right") {
                    store.editConnection()
                }
                AinkradDockButton("Forget this key", tone: .danger, isEnabled: store.storedKey != nil) {
                    store.disconnect()
                }
            }
            .padding(.bottom, skin.size.s8)
        }
    }
}

/// The 24 h working-hours track (`sx-range`), drawn without a range until the server stores one.
// ponytail: static; the draggable track (SettingsWorkTrack) takes over from API minor 17, this is the older server's.
private struct DayTrack: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(spacing: skin.size.s4) {
            Text("not stored yet").citadelFont("t11", weight: "semibold", mono: true)
                .foregroundStyle(skin.color(skin.text.faint))
                .frame(width: skin.size.s380, height: skin.size.s34)
                .background(
                    skin.color(.palette("background", 1)).opacity(skin.opacity.o25),
                    in: RoundedRectangle(cornerRadius: skin.size.s11)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s11).strokeBorder(
                        skin.color(.palette("foreground", skin.opacity.o05)), lineWidth: 1))
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { tick in
                    Text(tick)
                    if tick != "24" { Spacer() }
                }
            }
            .citadelFont("t9_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
            .frame(width: skin.size.s380)
        }
        .help("The server stores no working hours yet")
    }
}
