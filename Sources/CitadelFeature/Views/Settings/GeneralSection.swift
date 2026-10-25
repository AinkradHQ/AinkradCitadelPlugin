import AinkradAppKit
import CitadelClient
import SwiftUI

/// Company settings › General (`settings.js` General): identity (logo, name, kind, colour, the CEO), time, defaults
/// for new agents, this Mac's connection, and the danger zone. Only name and kind are stored by the API today; the
/// rest is drawn disabled with "not stored yet" until the server grows the fields.
struct GeneralSection: View {
    let store: CitadelStore
    @State private var name = ""
    @State private var kind: Components.Schemas.CompanyKind.Value1Payload = .own
    @State private var saving: Bool?
    @Environment(\.ainkradSkin) private var skin

    private var company: Components.Schemas.Company? { store.company }
    private var changed: Bool {
        guard let company else { return false }
        return name.trimmingCharacters(in: .whitespaces) != company.name || kind != (company.kind.value1 ?? .own)
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
                    isEnabled: changed && saving == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
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
        .onChange(of: company?.name) { _, _ in if saving == nil { reset() } }
    }

    private func reset() {
        name = company?.name ?? ""
        kind = company?.kind.value1 ?? .own
    }

    private func save() {
        saving = true
        store.saveCompany(name: name.trimmingCharacters(in: .whitespaces), kind: kind) { ok in
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
                VStack(spacing: skin.size.s6) {
                    CompanyMark(
                        company: Components.Schemas.Company(
                            accountIds: company.accountIds, id: company.id, kind: company.kind,
                            name: name.isEmpty ? company.name : name),
                        size: skin.size.s80, live: false, radius: skin.size.s24, fontKey: "t34")
                    Text("Upload logo").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .help("The server stores no company logo yet")
                }
                VStack(alignment: .leading, spacing: skin.size.s10) {
                    AinkradTextField(text: $name, placeholder: "Company name").fieldHeight(skin.size.s40)
                    AinkradSegmentedPicker(
                        items: [Components.Schemas.CompanyKind.Value1Payload.own, .client], selection: $kind,
                        label: { $0 == .own ? "Own company" : "Client" }
                    )
                    .controlSize(.small)
                    .fixedSize()
                    swatches(company)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let model = store.model, let ceo = model.ceo { ceoTile(ceo, model) }
            }
            .padding(.top, skin.size.s16)
            .padding(.bottom, skin.size.s10)
        }
    }

    /// The prototype's seven colours; the company's (derived from its id until the server stores one) is ringed.
    private func swatches(_ company: Components.Schemas.Company) -> some View {
        let tokens: [AinkradColorToken] = [
            skin.palette.accentPrimary, skin.palette.success, skin.palette.accentViolet, skin.palette.warning,
            skin.palette.danger, skin.palette.accentSecondary,
        ]
        let current = Int(company.id.magnitude % 6)
        return HStack(spacing: skin.size.s8) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous).fill(skin.color(token))
                    .frame(width: skin.size.s24, height: skin.size.s24)
                    .padding(skin.size.s2)
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                            .strokeBorder(skin.color(token), lineWidth: index == current ? skin.size.s2 : 0))
            }
            ServerSoonChip()
        }
        .help("The server stores no company colour yet")
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
                ServerSoonChip()
                AinkradDockButton("—", systemImage: "globe", isEnabled: false) {}
            }
            SettingsRow(
                label: "Working hours", hint: "drag the ends · agents run 24/7 · approvals wait for these hours"
            ) {
                DayTrack()
            }
            SettingsRow(label: "Working days") {
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
        }
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
                ServerSoonChip()
                AinkradDockButton("Claude first", systemImage: "chevron.down", isEnabled: false) {}
            }
            SettingsRow(label: "Agent figures have eyes", hint: "decision 63 · always on in this build") {
                AinkradToggle(isOn: .constant(true)).disabled(true)
            }
            SettingsRow(label: "Monthly budget", hint: "per new agent · warn at 80%") {
                ServerSoonChip()
                ValPill(text: "—", isEditable: false)
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
// ponytail: static; the draggable two-handle bar (snaps 30 min, keeps ≥1 h) comes with `work_start/work_end`.
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
