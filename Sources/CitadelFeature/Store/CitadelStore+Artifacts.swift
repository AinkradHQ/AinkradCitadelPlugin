import AppKit
import Foundation

/// Screen 13: the artifacts list, previews and the save panel.
extension CitadelStore {
    /// The screen opened: the list and the storage use, once.
    func loadArtifacts() {
        guard let model, let server, !model.artifactsPage.isLoaded else { return }
        model.artifactsPage.isLoaded = true
        Task { await fetchArtifacts(model, server: server) }
    }

    /// Reads the artifacts list and storage use again after an artifact event (once the screen loaded it), and
    /// the open requirement thread, where published artifacts appear too.
    func reloadArtifacts(_ model: CompanyModel, server: CitadelServer) async {
        if model.artifactsPage.isLoaded { await fetchArtifacts(model, server: server) }
        if let open = model.requirementsPage.selectedID ?? model.requirementsPage.threads.keys.first {
            await reloadThread(open, model: model, server: server)
        }
    }

    private func fetchArtifacts(_ model: CompanyModel, server: CitadelServer) async {
        async let items = server.artifacts()
        async let usage = server.artifactUsage(company: model.companyID)
        if let items = await items { model.artifactsPage.items = items }
        model.artifactsPage.usage = await usage ?? model.artifactsPage.usage
        let issues = Set(model.artifactsPage.items.compactMap(\.issueID))
        for issue in issues where model.issues[issue] == nil { model.issues[issue] = await server.issue(issue) }
    }

    /// A card's or the pane's preview, fetched once: text or an image, never anything else.
    func loadPreview(_ artifact: ArtifactInfo) {
        guard let model, let server else { return }
        let page = model.artifactsPage
        guard artifact.isText || artifact.isImage, page.texts[artifact.id] == nil, page.images[artifact.id] == nil
        else { return }
        Task {
            guard let data = await server.artifactPreview(artifact.id) else { return }
            if artifact.isImage {
                page.images[artifact.id] = NSImage(data: data)
            } else {
                page.texts[artifact.id] = String(decoding: data, as: UTF8.self)
            }
        }
    }

    /// Download: a save panel with a safe suggested name, then the bytes written there — never opened or run.
    /// The file is marked quarantined, as a browser download is.
    func download(_ artifact: ArtifactInfo) {
        guard let server else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.safeFileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let limit = Int(max(artifact.size, 1)) + 1024
        Task {
            guard let data = await server.artifactContent(artifact.id, upTo: limit) else { return }
            do {
                try data.write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.quarantineProperties = [
                    kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload,
                    kLSQuarantineAgentNameKey as String: "Ainkrad Citadel",
                ]
                var marked = url
                try? marked.setResourceValues(values)
            } catch {
                Log.connection.error("artifact save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Copy link: the file's address on the server (it needs a device key to open).
    func copyLink(_ artifact: ArtifactInfo) {
        guard let address else { return }
        let link = address.origin.appendingPathComponent("api/v1/artifacts/\(artifact.id)/content")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }
}
