import AinkradAppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

@MainActor
final class ConnectionTests: XCTestCase {
    private let key = "ck_dev_SECRETSECRETSECRET7Q2m"

    override func setUp() {
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/me": .init(json: Wire.me)
            case "/api/v1/companies/7/agents": .init(json: Wire.agents)
            case "/api/v1/events": .init(json: Wire.page([]))
            default: .init(status: 404, json: #"{"code":"not_found","message":"no"}"#)
            }
        }
    }

    // MARK: - Headers

    func testEveryCallCarriesTheKeyAsABearerHeaderAndTheCompany() async throws {
        let server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: key, company: 7,
            session: FakeServer.session())
        _ = try await server.me()
        _ = try await server.agentCount(company: 7)
        _ = try await server.replay(after: 3)

        XCTAssertEqual(FakeServer.requests.count, 3)
        for request in FakeServer.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Citadel-Company"), "7")
            XCTAssertNil(request.value(forHTTPHeaderField: "Origin"), "the API refuses any Origin")
            XCTAssertFalse(request.url?.absoluteString.contains(key) ?? true, "the key must never ride in a URL")
        }
        let socket = server.socketRequest(after: 12)
        XCTAssertEqual(socket.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(socket.value(forHTTPHeaderField: "X-Citadel-Company"), "7")
    }

    func testNoCompanyHeaderOutsideACompany() async throws {
        let server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: key, company: nil,
            session: FakeServer.session())
        _ = try await server.me()
        XCTAssertNil(FakeServer.requests.first?.value(forHTTPHeaderField: "X-Citadel-Company"))
        XCTAssertEqual(FakeServer.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
    }

    // MARK: - Addresses

    func testPlainHTTPIsRefusedExceptToThisMac() throws {
        XCTAssertThrowsError(try ServerAddress("http://citadel.example.com")) {
            XCTAssertEqual($0 as? ServerAddress.Problem, .plainHTTP(host: "citadel.example.com"))
        }
        XCTAssertThrowsError(try ServerAddress("http://10.0.0.5:8080"))
        XCTAssertThrowsError(try ServerAddress("ftp://citadel.example.com"))
        for loopback in ["http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787"] {
            XCTAssertNoThrow(try ServerAddress(loopback), loopback)
        }
        XCTAssertEqual(
            try ServerAddress("http://127.0.0.1:8787").eventSocketURL.absoluteString,
            "ws://127.0.0.1:8787/api/v1/events/ws")
        XCTAssertEqual(
            try ServerAddress("Citadel.Example.com/").eventSocketURL.absoluteString,
            "wss://citadel.example.com/api/v1/events/ws", "a bare host gets https")
    }

    func testAnAddressCarriesNoPathQueryOrUser() {
        for bad in [
            "https://u:p@citadel.example.com", "https://citadel.example.com/?key=x", "https://citadel.example.com/api",
            "",
        ] {
            XCTAssertThrowsError(try ServerAddress(bad), bad)
        }
    }

    // MARK: - Secrets

    func testTheKeyIsStoredOnlyInTheSecretStoreAndOnlyOnceAccepted() async throws {
        let docs = MemoryDocs()
        let secrets = MemorySecrets()
        let sockets = FakeSockets()
        let store = CitadelStore(
            settings: SettingsStore(documents: docs), secrets: secrets, session: FakeServer.session(),
            connector: sockets.connector)
        store.serverDraft = "https://citadel.example.com"
        store.keyDraft = key
        store.connect()
        await eventually { !sockets.sockets.isEmpty }
        sockets.sockets.first?.send(Wire.wake(1))
        await eventually { store.phase == .connected }
        store.stop()

        XCTAssertEqual(secrets.storage, ["device-key https://citadel.example.com": key])
        XCTAssertEqual(store.keyDraft, "", "the typed key is not kept in memory once stored")
        for (name, data) in docs.storage {
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(key), "the key leaked into document \(name)")
        }
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }
        XCTAssertFalse(defaults.contains { $0.contains(key) }, "the key leaked into UserDefaults")
        XCTAssertEqual(store.company?.name, "Ainkrad")
        XCTAssertEqual(store.agentCount, 0)
        XCTAssertEqual(store.serverVersion, "0.1.0", "GET /me is the key check and names the server")
        XCTAssertTrue(FakeServer.requests.contains { $0.url?.path == "/api/v1/me" })
    }

    func testTheCatchUpKnowsHowFarItHasToGoFromTheNewestSeq() async throws {
        let docs = MemoryDocs()
        let settings = SettingsStore(documents: docs)
        settings.update {
            $0.server = "https://citadel.example.com"
            $0.companyID = 7
            $0.cursors["https://citadel.example.com|7"] = 18_000
        }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.serverDraft = "https://citadel.example.com"
        store.keyDraft = key
        store.connect()
        await eventually { store.serverVersion != nil }
        store.stop()
        XCTAssertEqual(store.catchUpTotal, 442, "latest_seq 18,442 less the saved cursor 18,000")
    }

    func testARejectedKeyStoresNothing() async throws {
        FakeServer.serve { _ in .init(status: 401, json: #"{"code":"unauthorized","message":"no"}"#) }
        let docs = MemoryDocs()
        let secrets = MemorySecrets()
        let store = CitadelStore(
            settings: SettingsStore(documents: docs), secrets: secrets, session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.serverDraft = "https://citadel.example.com"
        store.keyDraft = key
        store.connect()
        await eventually { store.phase == .rejected }

        XCTAssertTrue(secrets.storage.isEmpty)
        XCTAssertNil(docs.storage[SettingsStore.key], "a 401 writes nothing")
        XCTAssertTrue(store.showsConnectCard)
    }

    func testUnreachableServerBacksOffAndRetriesNow() async throws {
        FakeServer.serve { _ in nil }
        let waits = Recorder()
        var timing = EventStream.Timing()
        timing.wait = { delay in
            waits.append(delay)
            try await Task.sleep(for: .seconds(3600))
        }
        let store = CitadelStore(
            settings: SettingsStore(documents: MemoryDocs()), secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector, timing: timing)
        store.serverDraft = "https://citadel.example.com"
        store.keyDraft = key
        store.connect()
        await eventually { waits.values.count == 1 }
        guard case .offline(let attempt, _, _) = store.phase else {
            return XCTFail("expected offline, got \(store.phase)")
        }
        XCTAssertEqual(attempt, 1)
        store.retryNow()
        await eventually { waits.values.count == 2 }
        XCTAssertEqual(waits.values, [1, 1], "Retry now starts the back-off again")
        store.stop()
    }

    func testBackoffDoublesToAMinute() {
        XCTAssertEqual((1...9).map(Backoff.delay(attempt:)), [1, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    func testMaskShowsOnlyThePrefixAndLastFour() {
        XCTAssertEqual(DeviceKeyStore.masked("ck_dev_abcdefgh7Q2m"), "ck_dev_••••7Q2m")
        XCTAssertEqual(DeviceKeyStore.masked("abcdefgh"), "••••efgh")
    }
}

/// Values appended from any thread.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [TimeInterval] = []
    var values: [TimeInterval] { lock.withLock { stored } }
    func append(_ value: TimeInterval) { lock.withLock { stored.append(value) } }
}
