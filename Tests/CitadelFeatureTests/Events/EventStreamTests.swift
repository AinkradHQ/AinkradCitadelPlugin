import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

@MainActor
final class EventStreamTests: XCTestCase {
    private var statuses: [EventStream.Status] = []
    private var events: [Int64] = []
    private let waits = Recorder()

    override func setUp() {
        statuses = []
        events = []
        FakeServer.serve { _ in .init(json: Wire.page([])) }
    }

    private func stream(cursor: Int64?, sockets: FakeSockets, pingTimeout: TimeInterval = 10) throws -> EventStream {
        let server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 7,
            session: FakeServer.session())
        var timing = EventStream.Timing()
        timing.pingTimeout = pingTimeout
        timing.wait = { [waits] in
            waits.append($0)
            try await Task.sleep(for: .milliseconds(20))
        }
        return EventStream(
            server: server, cursor: cursor, connect: sockets.connector, timing: timing,
            onStatus: { [weak self] in self?.statuses.append($0) },
            onEvent: { [weak self] event in self?.events.append(event.seq) }, onCursor: { _ in })
    }

    // MARK: - Decoding

    func testAnUnknownEventTypeIsSkippedButItsSeqStillCounts() throws {
        let known = try EventFrame.decode(Data(Wire.wake(5).utf8))
        XCTAssertEqual(known.seq, 5)
        guard case .wake(let wake)? = known.event?.payload else { return XCTFail("not a wake") }
        XCTAssertEqual(wake.agentId, 3)

        let unknown = try EventFrame.decode(Data(Wire.unknown(6).utf8))
        XCTAssertEqual(unknown.seq, 6)
        XCTAssertNil(unknown.event)

        let page = try EventFrame.decoder.decode(
            EventPage.self, from: Data(Wire.page([Wire.wake(1), Wire.unknown(2), Wire.wake(3)], nextAfter: 3).utf8))
        XCTAssertEqual(page.items.map(\.seq), [1, 2, 3], "one unknown event never fails the page")
        XCTAssertEqual(page.items.compactMap(\.event).map(\.seq), [1, 3])
        XCTAssertEqual(page.nextAfter, 3)
    }

    func testTheStreamDeliversKnownEventsAndSkipsUnknownOnes() async throws {
        FakeServer.serve { _ in .init(json: Wire.page([])) }
        let sockets = FakeSockets()
        let stream = try stream(cursor: nil, sockets: sockets)
        stream.start()
        await eventually { !sockets.sockets.isEmpty }
        let socket = try XCTUnwrap(sockets.sockets.first)
        socket.send(Wire.wake(10))
        socket.send(Wire.unknown(11))
        socket.send("not json")
        socket.send(Wire.wake(12))
        await eventually { stream.cursor == 12 }
        stream.stop()
        XCTAssertEqual(events, [10, 12])
        XCTAssertEqual(statuses.first, .live)
    }

    // MARK: - Resume

    func testResumeCatchesUpOverHTTPThenSendsLastEventIDNeverInTheURL() async throws {
        FakeServer.serve { request in
            switch request.query["after"] {
            case "41": .init(json: Wire.page([Wire.wake(42), Wire.wake(43)], nextAfter: 43))
            default: .init(json: Wire.page([]))
            }
        }
        let sockets = FakeSockets()
        let stream = try stream(cursor: 41, sockets: sockets)
        stream.start()
        await eventually { !sockets.sockets.isEmpty }

        XCTAssertEqual(FakeServer.requests.map { $0.query["after"] }, ["41", "43"])
        XCTAssertEqual(events, [42, 43])
        let upgrade = try XCTUnwrap(sockets.sockets.first?.request)
        XCTAssertEqual(upgrade.value(forHTTPHeaderField: "Last-Event-ID"), "43")
        XCTAssertEqual(upgrade.url?.absoluteString, "wss://citadel.example.com/api/v1/events/ws")
        XCTAssertNil(upgrade.url?.query, "the resume point is a header, never the URL")
        XCTAssertTrue(statuses.contains(.catchingUp(replayed: 2)))
        XCTAssertEqual(stream.replayed, 2)

        // A drop resumes from the last seq read on the socket.
        sockets.sockets.first?.send(Wire.wake(44))
        await eventually { stream.cursor == 44 }
        sockets.sockets.first?.drop()
        await eventually { sockets.sockets.count == 2 }
        XCTAssertEqual(sockets.sockets[1].request.value(forHTTPHeaderField: "Last-Event-ID"), "44")
        stream.stop()
    }

    func testAFirstConnectStreamsOnlyNewEvents() async throws {
        let sockets = FakeSockets()
        let stream = try stream(cursor: nil, sockets: sockets)
        stream.start()
        await eventually { !sockets.sockets.isEmpty }
        stream.stop()
        XCTAssertNil(sockets.sockets.first?.request.value(forHTTPHeaderField: "Last-Event-ID"))
        // Only the replay counts: another test's late reload may still land on the shared fake server.
        XCTAssertFalse(
            FakeServer.requests.contains { $0.url?.path == "/api/v1/events" }, "no replay without a resume point")
    }

    // MARK: - Reconnect

    func testReconnectBacksOffWhileTheServerIsUnreachable() async throws {
        FakeServer.serve { _ in nil }
        let sockets = FakeSockets()
        sockets.make = { request in
            let socket = FakeSocket(request: request)
            socket.drop()
            return socket
        }
        let stream = try stream(cursor: 5, sockets: sockets)
        stream.start()
        await eventually { self.waits.values.count >= 3 }
        stream.stop()
        XCTAssertEqual(Array(waits.values.prefix(3)), [1, 2, 4])
        guard case .offline(let attempt, _, _) = statuses.last else { return XCTFail("expected offline") }
        XCTAssertGreaterThanOrEqual(attempt, 3)
        XCTAssertTrue(sockets.sockets.isEmpty, "HTTP failed first, so no socket was tried")
    }

    func testHTTPReplayIsTheFallbackWhileTheSocketCannotOpen() async throws {
        FakeServer.serve { request in
            request.query["after"] == "5" ? .init(json: Wire.page([Wire.wake(6)])) : .init(json: Wire.page([]))
        }
        let sockets = FakeSockets()
        sockets.make = { request in
            let socket = FakeSocket(request: request)
            socket.drop(EventSocketClosed(httpStatus: 502, reason: "bad gateway"))
            return socket
        }
        let stream = try stream(cursor: 5, sockets: sockets)
        stream.start()
        await eventually { sockets.sockets.count >= 2 }
        stream.stop()
        XCTAssertEqual(events, [6], "the missed event still arrived over HTTP")
        guard case .polling(let attempt, _) = statuses.last else { return XCTFail("expected polling, got \(statuses)") }
        XCTAssertGreaterThanOrEqual(attempt, 1)
    }

    func testASilentSocketIsDroppedAfterThePingTimeout() async throws {
        let sockets = FakeSockets()
        sockets.make = { FakeSocket(request: $0, answersPings: false) }
        let stream = try stream(cursor: nil, sockets: sockets, pingTimeout: 0.05)
        stream.start()
        await eventually { sockets.sockets.count >= 2 }
        stream.stop()
        guard case .offline(_, _, let reason) = statuses.first else {
            return XCTFail("expected offline, got \(statuses)")
        }
        XCTAssertTrue(reason.contains("ping"), reason)
    }

    func testAFallingBehindCloseResumesAtOnce() async throws {
        let sockets = FakeSockets()
        let stream = try stream(cursor: nil, sockets: sockets)
        stream.start()
        await eventually { !sockets.sockets.isEmpty }
        sockets.sockets[0].send(Wire.wake(8))
        await eventually { stream.cursor == 8 }
        sockets.sockets[0].drop(EventSocketClosed(closeCode: 1013, reason: "too slow, at most 9"))
        await eventually { sockets.sockets.count == 2 }
        stream.stop()
        XCTAssertTrue(waits.values.isEmpty, "1013 resumes without a back-off")
        XCTAssertEqual(sockets.sockets[1].request.value(forHTTPHeaderField: "Last-Event-ID"), "8")
    }

    func testA401OnTheUpgradeStopsTheStream() async throws {
        let sockets = FakeSockets()
        sockets.make = { request in
            let socket = FakeSocket(request: request)
            socket.drop(EventSocketClosed(httpStatus: 401, reason: "unauthorized"))
            return socket
        }
        let stream = try stream(cursor: nil, sockets: sockets)
        stream.start()
        await eventually { self.statuses.last == .rejected }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sockets.sockets.count, 1, "no retry with a rejected key")
    }
}
