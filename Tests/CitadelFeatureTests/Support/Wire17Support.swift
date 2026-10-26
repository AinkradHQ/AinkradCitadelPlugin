import Foundation
import XCTest

@testable import CitadelFeature

/// Shared set-up for the API minor 17 tests: a store wired to `FakeServer`, and what it sent.
@MainActor
enum Wire17 {
    static func store(minor: Int? = 17) throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_FAKE_fixture", company: 1,
            session: FakeServer.session())
        store.model = CompanyFixture.model()
        store.apiMinor = minor
        return store
    }

    /// The JSON body of the first `method path` request the server saw, once it arrives.
    static func sent(_ method: String, _ path: String) async throws -> [String: Any] {
        await eventually { FakeServer.requests.contains { $0.url?.path == path && $0.httpMethod == method } }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == path && $0.httpMethod == method })
        guard let data = request.body17, !data.isEmpty else { return [:] }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func didSend(_ method: String, _ path: String) -> Bool {
        FakeServer.requests.contains { $0.url?.path == path && $0.httpMethod == method }
    }
}

extension URLRequest {
    /// The body, whether set directly or streamed.
    var body17: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
