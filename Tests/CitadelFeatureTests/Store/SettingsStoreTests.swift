import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testSettingsRoundTripThroughTheDocumentStore() {
        let docs = MemoryDocs()
        XCTAssertNil(SettingsStore(documents: docs).document.server, "an empty store reads the default")

        SettingsStore(documents: docs).update {
            $0.server = "https://citadel.example.com"
            $0.cursors["https://citadel.example.com|7"] = 42
        }

        let reloaded = SettingsStore(documents: docs).document
        XCTAssertEqual(reloaded.server, "https://citadel.example.com")
        XCTAssertEqual(reloaded.cursors["https://citadel.example.com|7"], 42)
    }

    func testUnreadableSettingsAreSetAsideNotOverwritten() {
        let docs = MemoryDocs()
        let garbage = Data("not json".utf8)
        docs.storage[SettingsStore.key] = garbage

        let settings = SettingsStore(documents: docs)
        XCTAssertEqual(settings.document, SettingsDocument(), "unreadable settings fall back to the default")
        XCTAssertEqual(
            docs.storage.first { $0.key.hasPrefix("\(SettingsStore.key).corrupt-") }?.value, garbage,
            "the unreadable bytes must be kept under a .corrupt- key")

        settings.update { $0.companyID = 7 }
        XCTAssertNotNil(docs.storage[SettingsStore.key], "after setting aside, saving works again")
    }
}
