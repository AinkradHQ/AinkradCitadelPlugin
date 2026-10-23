import AinkradAppKit
import Foundation
import SwiftUI
import Testing

@testable import CitadelFeature

/// Smoke test: the root view builds from a fake host and draws both the first-run card and the shell. It renders
/// to pixels instead of inspecting the view tree; "differs" proves the two are different screens.
@MainActor
@Suite("Root view")
struct RootViewTests {
    @Test func rendersTheConnectCardOnFirstRunAndTheShellAfter() throws {
        let card = try render(host: FakeHost())

        let docs = MemoryDocs()
        docs.storage[SettingsStore.key] = try JSONEncoder().encode(
            SettingsDocument(server: "https://citadel.example.com", hasConnected: true))
        let host = FakeHost(docs: docs)
        let store = CitadelApp.store(host: host)
        #expect(store.showsConnectCard, "not connected yet: the card")
        store.phase = .connected
        #expect(!store.showsConnectCard, "connected before: the shell")
        let shell = try render(host: host)

        #expect(!card.isEmpty && !shell.isEmpty, "the view drew nothing")
        #expect(card != shell)
    }

    /// The root view's pixels at a fixed size, or an error if it cannot render.
    private func render(host: FakeHost) throws -> Data {
        let renderer = ImageRenderer(content: CitadelApp.makeRootView(host: host).frame(width: 900, height: 600))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "the root view did not render")
        let data = try #require(image.dataProvider?.data, "the rendered image has no pixels")
        return data as Data
    }
}
