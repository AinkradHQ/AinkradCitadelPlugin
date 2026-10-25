import AinkradAppKit
import SwiftUI

/// Company settings › Skills (API minor 11): every version of the company's skills — what runs are given, and
/// what each is attached to — and "Publish…", a new version (an old one is never edited).
struct SkillsSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var publishing = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let skills = model.limitsPage.skills
        SettingsScroll {
            SettingsHero(section: .skills) {
                AinkradDockButton("Publish…", systemImage: "plus", tone: .primary) { publishing = true }
            }
            SettingsCard(title: "Skills", hint: skills.map { "\($0.count) versions" }) {
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    if skills?.isEmpty == true {
                        Text("No skills yet.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                    ForEach(skills ?? []) { skill in
                        HStack(spacing: skin.size.s12) {
                            SectionGlyph(icon: "sparkles", tint: skin.color(skin.palette.success), size: skin.size.s30)
                            VStack(alignment: .leading, spacing: skin.size.s1) {
                                Text("\(skill.name) · v\(skill.version)").citadelFont(
                                    "t13", weight: "semibold", mono: true
                                )
                                .foregroundStyle(skin.color(skin.text.primary))
                                Text("attached to \(attached(skill)) · \(ScopedSetting.bytes(skill.bytes))")
                                    .citadelFont("t11")
                                    .foregroundStyle(skin.color(skin.text.faint))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, skin.size.s12)
                        .padding(.vertical, skin.size.s10)
                        .background(
                            skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
                            in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous))
                    }
                }
                .padding(.top, skin.size.s6)
                .padding(.bottom, skin.size.s10)
            }
        }
        .onAppear { store.loadSkills() }
        .ainkradPanelModal(isPresented: $publishing, contentWidth: skin.size.s440) {
            PublishSkillSheet(store: store, model: model, isPresented: $publishing)
        }
    }

    /// "the company", "role Developer", "department Engineering", "project CIT".
    private func attached(_ skill: SkillInfo) -> String {
        switch skill.attachedTo {
        case "company": "the company"
        case "role": "role \(skill.attachedRole ?? "?")"
        case "department": "department \(model.departments.first { $0.id == skill.attachedID }?.name ?? "?")"
        case "project": "project \(model.projects.first { $0.id == skill.attachedID }?.key ?? "?")"
        default: skill.attachedTo
        }
    }
}

/// Name, what it attaches to, and its Markdown body.
private struct PublishSkillSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var attachTo = "company"
    @State private var attachID: Int64?
    @State private var role = ""
    @State private var text = ""
    @Environment(\.ainkradSkin) private var skin

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !text.trimmingCharacters(in: .whitespaces).isEmpty
            && (attachTo == "company" || (attachTo == "role" ? !role.isEmpty : attachID != nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Publish a skill").citadelFont("t15", weight: "semibold")
            Text("A new name starts at version 1; publishing an existing name adds its next version.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            AinkradFormRow(title: "Name") { AinkradTextField(text: $name, placeholder: "rust-style") }
            AinkradFormRow(title: "Attach to") {
                AinkradSegmentedPicker(items: ["company", "department", "role", "project"], selection: $attachTo) {
                    $0.capitalized
                }
                .fixedSize()
            }
            switch attachTo {
            case "role":
                AinkradFormRow(title: "Role") { AinkradTextField(text: $role, placeholder: "Developer") }
            case "department":
                AinkradFormRow(title: "Department") {
                    AinkradMenuButton(
                        items: model.departments.map { d in
                            AinkradMenuItem(title: d.name, systemName: nil) { attachID = d.id }
                        }
                    ) { Text(model.departments.first { $0.id == attachID }?.name ?? "Pick one") }
                }
            case "project":
                AinkradFormRow(title: "Project") {
                    AinkradMenuButton(
                        items: model.projects.map { p in
                            AinkradMenuItem(title: "\(p.key) \(p.name)", systemName: nil) { attachID = p.id }
                        }
                    ) { Text(model.projects.first { $0.id == attachID }?.key ?? "Pick one") }
                }
            default: EmptyView()
            }
            AinkradTextArea(text: $text, placeholder: "The skill, in Markdown")
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Publish") {
                    store.publishSkill(
                        name: name.trimmingCharacters(in: .whitespaces), body: text, attachTo: attachTo,
                        attachID: ["department", "project"].contains(attachTo) ? attachID : nil,
                        attachRole: attachTo == "role" ? role : nil
                    ) { isPresented = false }
                }
                .fixedSize().disabled(!ready)
            }
        }
        .onChange(of: attachTo) { attachID = nil }
    }
}
