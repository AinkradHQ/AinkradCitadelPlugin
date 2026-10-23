import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// Against a real `citadel-server` (a tool, not a gate): connect, receive a live event over the real WebSocket,
/// disconnect, let events happen, reconnect and get them replayed. Runs only with CITADEL_LIVE_URL
/// (http://127.0.0.1:<port>), CITADEL_LIVE_KEY (a device key) and CITADEL_LIVE_PROJECT (a project of the first
/// company) set — e.g. `citadel-server serve <db> --bind 127.0.0.1:7791` after `company add`, `project add` and
/// `device add`. Events are made by creating issues through the API (each is audited).
@MainActor
final class LiveServerTests: XCTestCase {
    func testConnectsStreamsAndReplaysAfterADisconnect() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["CITADEL_LIVE_URL"], let key = env["CITADEL_LIVE_KEY"],
            let project = env["CITADEL_LIVE_PROJECT"]
        else { throw XCTSkip("set CITADEL_LIVE_URL, _KEY and _PROJECT to run against a real server") }
        func addIssue(_ title: String) async throws {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "\(url)/api/v1/projects/\(project)/issues")))
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["title": title])
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }

        let docs = MemoryDocs()
        let secrets = MemorySecrets()
        let store = CitadelStore(settings: SettingsStore(documents: docs), secrets: secrets)
        store.serverDraft = url
        store.keyDraft = key
        store.connect()
        await eventually(10) { store.phase == .connected }
        XCTAssertEqual(store.streamStatus, .live)

        try await addIssue("Live event over the socket")
        await eventually(10) { !store.recentEvents.isEmpty }
        let seenLive = try XCTUnwrap(store.cursor)

        store.stop()
        try await addIssue("Missed while away 1")
        try await addIssue("Missed while away 2")

        // A second window instance: same documents and Keychain, so it resumes from the saved cursor.
        let again = CitadelStore(settings: SettingsStore(documents: docs), secrets: secrets)
        again.start()
        await eventually(10) { again.phase == .connected }
        await eventually(10) { (again.cursor ?? 0) > seenLive }
        XCTAssertGreaterThanOrEqual(again.replayed, 2, "the missed events came back over the replay")
        XCTAssertEqual(again.recentEvents.map(\.seq), again.recentEvents.map(\.seq).sorted(), "in order")
        try await addIssue("Live again")
        let before = again.recentEvents.count
        await eventually(10) { again.recentEvents.count > before }
        again.stop()
    }
}
