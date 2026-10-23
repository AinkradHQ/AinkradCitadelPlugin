import AinkradAppKit
import CitadelClient
import Foundation
import Observation

/// The connection to one Citadel server and its live event stream: what every screen binds to.
///
/// Connect runs three visible steps (mockup 01 note 3): the key check (`GET /companies`, which also proves TLS),
/// the company, then the event stream. The key reaches `host.secrets` only once the server has accepted it, so a
/// 401 stores nothing.
@MainActor
@Observable
final class CitadelStore {
    enum Phase: Equatable {
        /// The form: no server or key yet, or the person is changing them.
        case setup
        case connecting(step: Int, label: String, since: Date)
        case connected
        /// 401: the key was revoked or never existed.
        case rejected
        /// No answer; retried by itself at `retryAt`.
        case offline(attempt: Int, retryAt: Date, reason: String)
    }

    static let steps = 3
    static let recentLimit = 200

    // The form.
    var serverDraft = ""
    var keyDraft = ""
    /// Why the typed address was refused, or the key is missing.
    private(set) var formProblem: String?
    /// "How keys work" on the 401 card.
    var showsKeyHelp = false

    // Set only by the store; internal so previews and the screenshot sweep can stage a state.
    var phase: Phase = .setup
    var companies: [Components.Schemas.Company] = []
    var agentCount: Int?
    var latency: Duration?
    var streamStatus: EventStream.Status?
    /// Events replayed over HTTP since the stream started ("Replayed 312 events since you were last here").
    var replayed = 0
    /// The newest events, oldest first, at most `recentLimit`.
    private(set) var recentEvents: [Components.Schemas.Event] = []
    /// After a first-run connect the card stays up as "Connected" until Open Home.
    var hasOpenedHome: Bool
    /// The window's main pane shows Settings.
    var isShowingSettings = false
    /// The sidebar's screen, and the agent or run opened from it (screens 04 and 05).
    var screen: Screen = .home
    var detail: Detail?
    /// The selected company's data, once loaded; kept current by the event stream.
    var model: CompanyModel?

    let settings: SettingsStore
    private let keys: DeviceKeyStore
    private let session: URLSession
    private let connector: EventSocketConnector
    private let timing: EventStream.Timing
    @ObservationIgnored var server: CitadelServer?
    @ObservationIgnored var pendingReloads: Set<Reload> = []
    @ObservationIgnored var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var stream: EventStream?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var connectAttempt = 0
    @ObservationIgnored private var waiting: Task<Void, Error>?
    @ObservationIgnored private var lastSaved = Date.distantPast

    init(
        settings: SettingsStore, secrets: PluginSecretStore, session: URLSession = CitadelServer.makeSession(),
        connector: EventSocketConnector? = nil, timing: EventStream.Timing = .init()
    ) {
        self.settings = settings
        self.keys = DeviceKeyStore(secrets: secrets)
        self.session = session
        self.connector = connector ?? URLSessionEventSocket.connector(session: session)
        self.timing = timing
        self.serverDraft = settings.document.server ?? ""
        self.hasOpenedHome = settings.document.hasConnected
    }

    // MARK: - Reading

    var address: ServerAddress? { try? ServerAddress(settings.document.server ?? serverDraft) }
    var host: String { address?.host ?? serverDraft }
    var company: Components.Schemas.Company? {
        companies.first { $0.id == settings.document.companyID } ?? companies.first
    }
    var storedKey: String? { address.flatMap { keys.key(for: $0) } }
    var cursor: Int64? { cursorKey.flatMap { settings.document.cursors[$0] } }

    /// The connect card (first run, a rejected key, or Connected until Open Home); otherwise the shell.
    var showsConnectCard: Bool {
        switch phase {
        case .setup, .rejected: true
        case .connecting, .connected, .offline: !hasOpenedHome || !settings.document.hasConnected
        }
    }

    // MARK: - Actions

    /// Connects with the stored server and key, if both exist (window open).
    func start() {
        guard work == nil, phase == .setup, settings.document.server != nil,
            storedKey != nil
        else { return }
        connect()
    }

    /// Connect ↵: checks the form, then runs the three steps.
    func connect() {
        stop()
        formProblem = nil
        let address: ServerAddress
        do {
            address = try ServerAddress(serverDraft.isEmpty ? (settings.document.server ?? "") : serverDraft)
        } catch {
            formProblem = ServerAddress.message(for: error)
            return
        }
        let typed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = typed.isEmpty ? keys.key(for: address) : typed else {
            formProblem = "Paste the device key."
            return
        }
        work = Task { await runConnect(address: address, key: key) }
    }

    /// Cancel: back to the form.
    func cancel() {
        stop()
        phase = .setup
    }

    /// Retry now: skips the rest of the back-off.
    func retryNow() {
        connectAttempt = 0
        if let stream {
            stream.retryNow()
        } else {
            waiting?.cancel()
        }
    }

    /// Change server / Paste new key: back to the form, keeping what was typed.
    func editConnection() {
        stop()
        serverDraft = settings.document.server ?? serverDraft
        phase = .setup
    }

    /// Cancel on the form after a first connect: back to the saved server and key.
    func resume() {
        serverDraft = settings.document.server ?? ""
        keyDraft = ""
        connect()
    }

    /// Forget the key for this server and stop (Settings).
    func disconnect() {
        stop()
        if let address { keys.setKey(nil, for: address) }
        settings.update { $0.hasConnected = false }
        hasOpenedHome = false
        companies = []
        model = nil
        phase = .setup
    }

    func openHome() { hasOpenedHome = true }

    func select(company id: Int64) {
        guard id != settings.document.companyID, let server else { return }
        saveCursor(force: true)
        settings.update { $0.companyID = id }
        recentEvents = []
        agentCount = nil
        model = nil
        detail = nil
        stream?.stop()
        startStream(server.scoped(to: id))
        Task { agentCount = try? await server.scoped(to: id).agentCount(company: id) }
    }

    func stop() {
        work?.cancel()
        work = nil
        waiting?.cancel()
        stream?.stop()
        stream = nil
        saveCursor(force: true)
    }

    // MARK: - Connecting

    private func runConnect(address: ServerAddress, key: String) async {
        let started = ContinuousClock.now
        phase = .connecting(step: 1, label: "Checking key", since: Date())
        let base = CitadelServer(address: address, deviceKey: key, company: nil, session: session)
        do {
            let companies = try await base.companies()
            guard !Task.isCancelled else { return }
            latency = ContinuousClock.now - started
            // Accepted: only now does the key reach the secret store.
            keys.setKey(key, for: address)
            keyDraft = ""
            connectAttempt = 0
            settings.update {
                $0.server = address.origin.absoluteString
                $0.lastSeen = Date()
            }
            serverDraft = address.origin.absoluteString
            self.companies = companies
            guard let company = self.company else {
                phase = .connected
                return
            }
            settings.update { $0.companyID = company.id }
            phase = .connecting(step: 2, label: "Loading \(company.name)", since: Date())
            let scoped = base.scoped(to: company.id)
            agentCount = try await scoped.agentCount(company: company.id)
            guard !Task.isCancelled else { return }
            phase = .connecting(step: 3, label: "Opening the event stream", since: Date())
            startStream(scoped)
        } catch .rejected {
            phase = .rejected
        } catch {
            guard !Task.isCancelled else { return }
            await waitAndRetry(address: address, key: key, reason: EventStream.describe(error))
        }
    }

    private func waitAndRetry(address: ServerAddress, key: String, reason: String) async {
        connectAttempt += 1
        let delay = Backoff.delay(attempt: connectAttempt)
        phase = .offline(attempt: connectAttempt, retryAt: Date().addingTimeInterval(delay), reason: reason)
        let wait = timing.wait
        waiting = Task { try await wait(delay) }
        _ = try? await waiting?.value
        guard !Task.isCancelled else { return }
        await runConnect(address: address, key: key)
    }

    private func startStream(_ server: CitadelServer) {
        self.server = server
        let stream = EventStream(
            server: server, cursor: cursor, connect: connector, timing: timing,
            onStatus: { [weak self] in self?.streamChanged($0) },
            onEvent: { [weak self] in self?.received($0) },
            onCursor: { [weak self] _ in self?.saveCursor(force: false) })
        self.stream = stream
        stream.start()
    }

    private func streamChanged(_ status: EventStream.Status) {
        streamStatus = status
        replayed = stream?.replayed ?? replayed
        switch status {
        case .live, .polling:
            if model?.companyID != company?.id { loadCompany() }
            if phase != .connected {
                phase = .connected
                settings.update {
                    $0.hasConnected = true
                    $0.lastSeen = Date()
                }
            }
        case .catchingUp:
            break
        case .offline(let attempt, let retryAt, let reason):
            phase = .offline(attempt: attempt, retryAt: retryAt, reason: reason)
        case .rejected:
            stream = nil
            phase = .rejected
        }
    }

    func received(_ event: Components.Schemas.Event) {
        if let model { schedule(model.apply(event)) }
        recentEvents.append(event)
        if recentEvents.count > Self.recentLimit { recentEvents.removeFirst(recentEvents.count - Self.recentLimit) }
    }

    // MARK: - The resume point

    /// `server|company`: a seq means nothing on another server or in another company's stream.
    private var cursorKey: String? {
        guard let origin = settings.document.server else { return nil }
        return "\(origin)|\(settings.document.companyID ?? 0)"
    }

    /// Persists the stream's cursor at most once a second (and at once on `force`).
    private func saveCursor(force: Bool) {
        guard let seq = stream?.cursor, let key = cursorKey else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSaved) >= 1 else { return }
        lastSaved = now
        settings.update {
            $0.cursors[key] = seq
            $0.lastSeen = now
        }
    }
}
