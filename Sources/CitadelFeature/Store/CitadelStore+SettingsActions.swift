import AinkradAppKit
import CitadelClient
import Foundation

/// Company settings' writes with their toasts: the profile (General) and limits set by the gauge or the value pill,
/// each with Undo where the server can take it back.
extension CitadelStore {
    /// "Save changes": the name and kind the API stores; `done(true)` once saved.
    func saveCompany(
        name: String, kind: Components.Schemas.CompanyKind.Value1Payload, undoable: Bool = true,
        done: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard let server, let company else { return done(false) }
        let before = (company.name, company.kind.value1 ?? .own)
        Task {
            if let answer = await server.updateCompany(company.id, name: name, kind: kind) {
                actionFailure = ActionFailure(
                    title: "Couldn't save \(company.name)", answer: answer, outcome: "Nothing was changed.")
                return done(false)
            }
            if let index = companies.firstIndex(where: { $0.id == company.id }) {
                companies[index].name = name
                companies[index].kind = .init(value1: kind)
            }
            done(true)
            toast(
                AinkradRichToast(
                    title: "Company settings saved", body: "Audited · effective now", status: .success,
                    actions: undoable
                        ? [
                            AinkradRichToastAction("Undo") {
                                self.saveCompany(name: before.0, kind: before.1, undoable: false)
                            }
                        ] : []))
        }
    }

    /// A limit set from its gauge or value pill: the row flashes and a toast offers Undo (back to the old value, or
    /// to inheriting it).
    func commitLimit(_ setting: ScopedSetting, scope: String, value: Int64) {
        guard let server, let model else { return }
        let wasSet = setting.isSet(at: scope)
        let old = setting.value
        Task {
            guard let saved = await server.setSetting(scope: scope, key: setting.key, value: value) else {
                toast(AinkradRichToast(title: "Couldn't set \(LimitNames.name(setting.key))", status: .danger))
                return
            }
            model.storeSetting(saved, scope: scope)
            flashLimit(setting.key)
            toast(
                AinkradRichToast(
                    title: "\(LimitNames.name(setting.key)) → \(saved.text)",
                    body: "\(company?.name ?? "Company") · effective for new runs · audited", status: .success,
                    actions: [
                        AinkradRichToastAction("Undo") {
                            if wasSet {
                                self.commitLimit(saved, scope: scope, value: old)
                            } else {
                                self.resetLimitWithToast(saved, scope: scope, undoable: false)
                            }
                        }
                    ]))
        }
    }

    /// ↺ on a company value: it inherits the server's again.
    func resetLimitWithToast(_ setting: ScopedSetting, scope: String, undoable: Bool = true) {
        guard let server, let model else { return }
        let old = setting.value
        Task {
            guard let saved = await server.resetSetting(scope: scope, key: setting.key) else { return }
            model.storeSetting(saved, scope: scope)
            flashLimit(setting.key)
            toast(
                AinkradRichToast(
                    title: "\(LimitNames.name(setting.key)) reset",
                    body: "Inherits the server default \(saved.text) · audited",
                    actions: undoable
                        ? [AinkradRichToastAction("Undo") { self.commitLimit(saved, scope: scope, value: old) }] : []))
        }
    }

    private func flashLimit(_ key: String) {
        guard let page = model?.limitsPage else { return }
        page.flashed = key
        Task {
            try? await Task.sleep(for: .seconds(1.7))
            if page.flashed == key { page.flashed = nil }
        }
    }
}
