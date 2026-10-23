import AinkradAppKit
import SwiftUI

/// "+ Add runner": a name and the tags of the work it takes, then its start command with its key — shown this once
/// (the server keeps only its hash).
struct AddRunnerSheet: View {
    let store: CitadelStore
    let page: RunnersPage
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var tags = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Add runner").citadelFont("t15", weight: "semibold")
            if let registered = page.registered {
                Text(
                    "Run this on \(registered.runner.name)'s host. The key is shown only now; copy it before you close."
                )
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                .fixedSize(horizontal: false, vertical: true)
                let command = store.address.map { registered.command(server: $0.origin) } ?? registered.key
                AinkradCodeBlock(command, language: "sh")
                HStack(spacing: skin.size.s8) {
                    Spacer()
                    AinkradButton(title: "Copy command", style: .secondary) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .secondaryAccent().fixedSize()
                    AinkradButton(title: "Done") { close() }.fixedSize()
                }
            } else {
                AinkradFormRow(title: "Name") { AinkradTextField(text: $name, placeholder: "hetzner-3") }
                AinkradFormRow(title: "Tags", help: "The work it takes, comma-separated: linux, docker, macos…") {
                    AinkradTextField(text: $tags, placeholder: "linux, docker")
                }
                if let failure = page.registerFailure { RefusalLine(failure: failure) }
                HStack(spacing: skin.size.s8) {
                    Spacer()
                    AinkradButton(title: "Cancel", style: .ghost) { close() }.fixedSize()
                    AinkradButton(title: "Register") { store.registerRunner(name: trimmedName, tags: tagList) }
                        .fixedSize().disabled(trimmedName.isEmpty)
                }
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s520)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var tagList: [String] {
        tags.split { $0 == "," || $0 == " " }.map(String.init).filter { !$0.isEmpty }
    }

    private func close() {
        page.registered = nil
        page.registerFailure = nil
        isPresented = false
    }
}

/// "Re-login on server…": the exact command for each login the runner reports logged out, run on its host —
/// Citadel never handles the login secret.
struct ReloginSheet: View {
    let runner: RunnerInfo
    @Binding var isPresented: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Re-login on \(runner.name)").citadelFont("t15", weight: "semibold")
            Text("On the runner's host, as the user the runner runs as. The next probe (within 10 min) clears it.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(runner.loggedOut, id: \.dir) { login in
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    Text(login.harness.map(AgentLook.harnessName) ?? login.dir).citadelFont("t12", weight: "semibold")
                    AinkradCodeBlock(login.command, language: "sh")
                }
            }
            HStack {
                Spacer()
                AinkradButton(title: "Done") { isPresented = false }.fixedSize()
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s520)
    }
}

/// "Probe log" / "Show last log": the end of the runner's own log, redacted by the runner and the server.
struct RunnerLogSheet: View {
    let name: String
    let lines: [String]
    let close: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("\(name) · log").citadelFont("t15", weight: "semibold")
            if lines.isEmpty {
                Text("The log is empty.").citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            } else {
                ScrollView { AinkradCodeBlock(lines.joined(separator: "\n")) }
                    .frame(maxHeight: skin.size.s440)
            }
            HStack {
                Spacer()
                AinkradButton(title: "Done", action: close).fixedSize()
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s640)
    }
}
