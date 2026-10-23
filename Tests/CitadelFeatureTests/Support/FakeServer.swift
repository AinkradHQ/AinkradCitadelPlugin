import Foundation
import XCTest

@testable import CitadelFeature

/// A stand-in Citadel for the HTTP side: a `URLProtocol` that answers from `FakeServer.route` and records every
/// request it saw. One test at a time (XCTest runs a class's tests serially).
final class FakeServer: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var json = "{}"
    }

    nonisolated(unsafe) private static var lock = NSLock()
    nonisolated(unsafe) private static var _requests: [URLRequest] = []
    nonisolated(unsafe) private static var _route: (URLRequest) -> Reply? = { _ in nil }

    static var requests: [URLRequest] { lock.withLock { _requests } }

    /// Answers `route`; `nil` is a dropped connection (`URLError.cannotConnectToHost`).
    static func serve(_ route: @escaping (URLRequest) -> Reply?) {
        lock.withLock {
            _requests = []
            _route = route
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeServer.self]
        return CitadelServer.makeSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (reply, url) = Self.lock.withLock { () -> (Reply?, URL?) in
            Self._requests.append(request)
            return (Self._route(request), request.url)
        }
        guard let reply, let url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// JSON the real server writes.
enum Wire {
    static let companies =
        #"[{"id":7,"name":"Ainkrad","kind":"own","account_ids":[]},{"id":9,"name":"AutomotiveAi","kind":"client","account_ids":[1]}]"#
    static let agents = "[]"
    static let me =
        #"{"device":{"id":1,"name":"ahmed-mbp"},"user":{"id":1,"name":"Ahmed"},"versions":{"server":"0.1.0","git_sha":"3c51e1c","api":{"major":"v1","minor":1},"runner_protocol":"1.17"},"companies":\#(companies),"latest_seq":18442}"#

    static func wake(_ seq: Int64) -> String {
        #"{"seq":\#(seq),"at":"2026-10-21T12:00:00.250Z","payload":{"type":"wake","wake_id":\#(seq),"agent_id":3,"source":"timer","reason":"tick"}}"#
    }

    /// An event type this client was generated without.
    static func unknown(_ seq: Int64) -> String {
        #"{"seq":\#(seq),"at":"2026-10-21T12:00:01.000Z","payload":{"type":"hologram","shimmer":true}}"#
    }

    static func page(_ items: [String], nextAfter: Int64? = nil) -> String {
        #"{"items":[\#(items.joined(separator: ","))]\#(nextAfter.map { #","next_after":\#($0)"# } ?? "")}"#
    }
}

/// A scripted WebSocket: frames pushed by the test, pings answered (or not), and a way to drop it.
final class FakeSocket: EventSocket, @unchecked Sendable {
    /// Read by one loop at a time, as the stream does.
    private var frames: AsyncThrowingStream<Data, Error>.Iterator
    private let push: AsyncThrowingStream<Data, Error>.Continuation
    private let answersPings: Bool
    let request: URLRequest

    init(request: URLRequest, answersPings: Bool = true) {
        let (stream, push) = AsyncThrowingStream<Data, Error>.makeStream()
        frames = stream.makeAsyncIterator()
        self.push = push
        self.request = request
        self.answersPings = answersPings
    }

    func send(_ json: String) { push.yield(Data(json.utf8)) }
    func drop(_ closed: EventSocketClosed = EventSocketClosed(reason: "dropped")) { push.finish(throwing: closed) }

    func receive() async throws -> Data {
        if let frame = try await frames.next() { return frame }
        throw EventSocketClosed(reason: "closed")
    }

    func ping() async throws {
        if !answersPings { try await Task.sleep(for: .seconds(3600)) }
    }

    func close() { push.finish(throwing: EventSocketClosed(reason: "closed by client")) }
}

/// Hands out sockets and remembers each upgrade request.
final class FakeSockets: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [FakeSocket] = []
    /// What each new socket does; the default answers pings and waits for frames.
    var make: @Sendable (URLRequest) -> FakeSocket = { FakeSocket(request: $0) }

    var sockets: [FakeSocket] { lock.withLock { made } }

    var connector: EventSocketConnector {
        { [self] request in
            let socket = make(request)
            lock.withLock { made.append(socket) }
            return socket
        }
    }
}

/// Polls `condition` on the main actor until it holds or `seconds` pass.
@MainActor
func eventually(
    _ seconds: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(condition(), "condition not met in \(seconds) s", file: file, line: line)
}

extension URLRequest {
    var query: [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }
}
