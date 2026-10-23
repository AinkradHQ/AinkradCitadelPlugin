import AinkradAppKit
import Foundation
import Observation

/// Citadel's small persisted state through the host's key→data store (`HostServices.documents`). Observable, so
/// the settings page and the window see the same values. Each setter persists at once.
@MainActor
@Observable
final class SettingsStore {
    static let key = "settings"

    private let documents: PluginDocumentStore
    private(set) var document: SettingsDocument
    /// False only when unreadable settings could not be set aside — then no save may overwrite the user's only
    /// copy (see `loadDocument`).
    private let canSave: Bool

    /// Reads the saved document and nothing else; no work starts here.
    init(documents: PluginDocumentStore) {
        self.documents = documents
        let loaded = loadDocument(SettingsDocument.self, key: Self.key, from: documents)
        self.document = loaded.value ?? SettingsDocument()
        self.canSave = loaded.canSave
    }

    func update(_ change: (inout SettingsDocument) -> Void) {
        var next = document
        change(&next)
        guard next != document else { return }
        document = next
        save()
    }

    private func save() {
        guard canSave else { return }
        do {
            documents.setData(try JSONEncoder().encode(document), forKey: Self.key)
        } catch {
            Log.persistence.error("settings were not saved: \(error)")
        }
    }
}
