import AinkradAppKit
import SwiftUI

/// "Add runner" (`addRunner`): Machine → Install → Connect. Step 1 names it, picks the machine (its default tags) and
/// the tags; "Generate install command" registers it, and step 2 shows its start command with the key, once. Step 3
/// watches the stream until it calls home and reports its harnesses.
struct AddRunnerDrawer: View {
    let store: CitadelStore
    let page: RunnersPage
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var machine: (id: String, title: String, mac: Bool, tags: [String]) {
        AddRunnerDraft.machines.first { $0.id == page.addDraft.machine } ?? AddRunnerDraft.machines[0]
    }

    /// The registered runner as the stream last reported it.
    private var joined: RunnerInfo? {
        guard let id = page.registered?.runner.id else { return nil }
        return page.runners.first { $0.id == id }
    }

    var body: some View {
        rail
        switch page.addStep {
        case 0:
            preview(tint: skin.color(skin.palette.accentPrimary))
            machineStep
        case 1:
            preview(tint: skin.color(skin.palette.accentPrimary))
            installStep
        default: connectStep
        }
    }

    // MARK: Rail and preview

    private var rail: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(Array(["Machine", "Install", "Connect"].enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Capsule().fill(skin.color(.palette("foreground", skin.opacity.o08))).frame(height: skin.size.s2)
                }
                let on = index == page.addStep
                let done = index < page.addStep
                HStack(spacing: skin.size.s8) {
                    Text(verbatim: done ? "✓" : "\(index + 1)").citadelFont("t12", weight: "bold", mono: true)
                        .foregroundStyle(skin.color(done ? .palette("background", 1) : .palette("foreground", 1)))
                        .frame(width: skin.size.s28, height: skin.size.s28)
                        .background(
                            done
                                ? AnyShapeStyle(status.success)
                                : on
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [
                                                skin.color(skin.palette.accentPrimary),
                                                skin.color(skin.palette.accentViolet),
                                            ],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(skin.color(.palette("foreground", skin.opacity.o10))), in: Circle()
                        )
                        .overlay(
                            Circle().stroke(
                                skin.color(skin.palette.accentPrimary).opacity(on ? skin.opacity.o20 : 0),
                                lineWidth: skin.size.s4))
                    Text(title).citadelFont("t12_5").foregroundStyle(
                        skin.color(on ? skin.text.primary : skin.text.faint))
                }
                .fixedSize()
            }
        }
        .padding(.bottom, skin.size.s2)
    }

    private func preview(tint: Color) -> some View {
        let draft = page.addDraft
        let tags = draft.allTags.isEmpty ? "no tags" : draft.allTags.joined(separator: " · ")
        return AinkradDrawerHero(
            tint: tint, title: draft.trimmedName.isEmpty ? "—" : draft.trimmedName,
            subtitle: "\(machine.title) · \(tags)"
        ) {
            Image(systemName: machine.mac ? "laptopcomputer" : "server.rack").citadelFont("t21")
                .foregroundStyle(tint)
                .frame(width: skin.size.s56, height: skin.size.s56)
                .background(
                    tint.opacity(skin.opacity.o14),
                    in: RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous))
        }
    }

    // MARK: Step 1

    @ViewBuilder private var machineStep: some View {
        @Bindable var page = page
        AinkradDrawerSection(title: "Name", hint: "how it shows up everywhere") {
            AinkradTextField(text: $page.addDraft.name, placeholder: "hetzner-3").monospaced()
        }
        AinkradDrawerSection(title: "Machine") {
            HStack(spacing: skin.size.s8) {
                ForEach(AddRunnerDraft.machines, id: \.id) { option in
                    SettingsChoiceCard(
                        title: option.title, detail: option.tags.joined(separator: " · "),
                        tint: skin.color(skin.palette.accentPrimary), isOn: page.addDraft.machine == option.id
                    ) {
                        page.addDraft.machine = option.id
                        page.addDraft.tags = option.tags
                    } leading: {
                        Image(systemName: option.mac ? "laptopcomputer" : "server.rack").citadelFont("t18")
                            .foregroundStyle(skin.color(skin.palette.accentPrimary))
                            .frame(width: skin.size.s44, height: skin.size.s44)
                            .background(
                                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o14),
                                in: RoundedRectangle(cornerRadius: skin.size.s13, style: .continuous))
                    }
                }
            }
        }
        AinkradDrawerSection(title: "Parallel slots", hint: "the runner reports its own when it connects") {
            Text("Set on the machine: each runner reports how many runs it holds at once.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        }
        AinkradDrawerSection(title: "Tags", hint: "jobs route by tag") {
            AinkradFlowLayout(spacing: skin.size.s8) {
                ForEach(AddRunnerDraft.tagChoices, id: \.tag) { choice in tagChip(choice.tag, choice.title) }
            }
            AinkradTextField(text: $page.addDraft.extraTags, placeholder: "more tags, comma-separated").compact()
        }
        if let failure = page.registerFailure { RefusalLine(failure: failure) }
    }

    private func tagChip(_ tag: String, _ title: String) -> some View {
        let on = page.addDraft.tags.contains(tag)
        let cyan = skin.color(skin.palette.accentSecondary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        return AinkradTapArea {
            if on { page.addDraft.tags.removeAll { $0 == tag } } else { page.addDraft.tags.append(tag) }
        } label: {
            HStack(spacing: skin.size.s8) {
                Text(verbatim: "#").citadelFont("t11", weight: "bold").foregroundStyle(
                    skin.color(.palette("foreground", 1))
                )
                .frame(width: skin.size.s22, height: skin.size.s22)
                .background(cyan.opacity(on ? 1 : skin.opacity.o50), in: RoundedRectangle(cornerRadius: skin.size.s7))
                Text(title).citadelFont("t12").foregroundStyle(skin.color(on ? skin.text.primary : skin.text.faint))
            }
            .padding(.leading, skin.size.s6).padding(.trailing, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                on ? cyan.opacity(skin.opacity.o12) : skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    on ? cyan.opacity(skin.opacity.o55) : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2

    @ViewBuilder private var installStep: some View {
        if let registered = page.registered {
            let command = store.address.map { registered.command(server: $0.origin) } ?? registered.key
            AinkradDrawerSection(
                title: "Run this on \(registered.runner.name)", hint: "the key rides in the environment"
            ) {
                CommandStrip(command: command.replacingOccurrences(of: " \\\n  ", with: " "))
            }
            AinkradDrawerSection {
                HStack(spacing: skin.size.s14) {
                    Image(systemName: "key").citadelFont("t21").foregroundStyle(skin.color(skin.palette.accentPrimary))
                        .frame(width: skin.size.s64, height: skin.size.s64)
                        .background(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o12), in: Circle())
                    VStack(alignment: .leading, spacing: skin.size.s3) {
                        Text("Its key, shown this once").citadelFont("t13", weight: "bold")
                        Text(
                            "The server keeps only its hash · it works until you remove the runner · copy it before you close"
                        )
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
            VStack(spacing: skin.size.s6) {
                NumberedRow(
                    number: 1, title: "Connects with its key",
                    detail: "a WebSocket to this server; the key never goes on a command line")
                NumberedRow(
                    number: 2, title: "Reports what it has",
                    detail: machine.mac
                        ? "its slots and harnesses · a launchd agent reconnects on wake"
                        : "its slots and harnesses · run it as a service to restart on failure")
                NumberedRow(number: 3, title: "Takes work by tag", detail: "then probes every harness it finds")
            }
        }
    }

    // MARK: Step 3

    @ViewBuilder private var connectStep: some View {
        if let joined, joined.status != "offline" {
            preview(tint: status.success)
            VStack(spacing: skin.size.s6) {
                checkRow(true, "Registered", "\(joined.name)\(joined.slots.map { " · \($0) slots" } ?? "")")
                checkRow(
                    true, "Heartbeat",
                    joined.lastSeenAt.map { "\(Fmt.age(Date().timeIntervalSince($0))) ago" } ?? "live")
                ForEach(joined.harnessRows, id: \.name) { row in
                    let out = row.login == "logged_out"
                    checkRow(
                        !out, "\(AgentLook.harnessName(row.name)) \(row.version)",
                        out ? "not logged in" : row.login == "logged_in" ? "logged in" : "found")
                }
                if joined.harnessRows.isEmpty {
                    HStack(spacing: skin.size.s10) {
                        ProgressView().controlSize(.small)
                        Text("Probing harnesses…").citadelFont("t12_5", weight: "semibold")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(skin.size.s10)
                }
            }
            if !joined.loggedOut.isEmpty {
                Text(
                    "Log the missing harnesses in on the box to route their work to it — Re-login on its card walks you through it."
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        } else {
            RadarWait(title: "Waiting for \(page.registered?.runner.name ?? "it") to call home…")
        }
    }

    private func checkRow(_ ok: Bool, _ title: String, _ detail: String) -> some View {
        let tint = ok ? status.success : status.warning
        return HStack(spacing: skin.size.s10) {
            Text(verbatim: ok ? "✓" : "!").citadelFont("t12", weight: "bold").foregroundStyle(tint)
                .frame(width: skin.size.s26, height: skin.size.s26)
                .background(tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s8))
            Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            Spacer(minLength: skin.size.s8)
            Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(tint.opacity(skin.opacity.o07), in: RoundedRectangle(cornerRadius: skin.size.s12))
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
    }
}

/// The radar (`ar-radar`): three rings pinging out 0.8 s apart around the device, and what it waits for.
struct RadarWait: View {
    let title: String
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var ping = false

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        VStack(spacing: skin.size.s10) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle().stroke(blue.opacity(skin.opacity.o50), lineWidth: skin.size.s2)
                        .scaleEffect(ping ? 1 : 0.35)
                        .opacity(ping ? 0 : 1)
                        .animation(
                            reduceMotion
                                ? nil
                                : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 2.4))
                                    .repeatForever(autoreverses: false).delay(Double(index) * 0.8), value: ping)
                }
                Image(systemName: "server.rack").citadelFont("t21").foregroundStyle(blue)
                    .frame(width: skin.size.s56, height: skin.size.s56)
                    .background(
                        blue.opacity(skin.opacity.o14),
                        in: RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous))
            }
            .frame(width: skin.size.s150, height: skin.size.s150)
            Text(title).citadelFont("t14", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            Text("Run the command on the machine — this updates by itself.").citadelFont("t12")
                .foregroundStyle(skin.color(skin.text.faint))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s30)
        .onAppear { ping = true }
    }
}

/// Cancel · Generate install command → I've run it → Done.
struct AddRunnerFoot: View {
    let store: CitadelStore
    let page: RunnersPage
    let close: () -> Void

    var body: some View {
        switch page.addStep {
        case 0:
            Spacer()
            AinkradDockButton("Cancel", action: close)
            AinkradDockButton("Generate install command", tone: .primary, isEnabled: !page.addDraft.trimmedName.isEmpty)
            {
                store.registerRunner(name: page.addDraft.trimmedName, tags: page.addDraft.allTags)
            }
        case 1:
            Spacer()
            AinkradDockButton("I've run it", tone: .primary) { page.addStep = 2 }
        default:
            let joined = page.runners.contains { $0.id == page.registered?.runner.id && $0.status != "offline" }
            Spacer()
            AinkradDockButton(joined ? "Done" : "Close", tone: joined ? .primary : .plain, action: close)
        }
    }
}
