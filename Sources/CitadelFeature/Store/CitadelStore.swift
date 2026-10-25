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
    /// The companies' uploaded logos (API minor 17), loaded like the agents' avatars.
    let logos = CompanyLogos()
    /// The projects' uploaded logos (API minor 18).
    let projectLogos = ProjectLogos()
    var agentCount: Int?
    var latency: Duration?
    /// The server's version (`GET /me`), shown on the connected card.
    var serverVersion: String?
    /// How many events a catch-up has to replay: the newest seq (`GET /me`) less the saved cursor.
    var catchUpTotal: Int?
    var streamStatus: EventStream.Status?
    /// Events replayed over HTTP since the stream started ("Replayed 312 events since you were last here").
    var replayed = 0
    /// The newest events, oldest first, at most `recentLimit`.
    private(set) var recentEvents: [Components.Schemas.Event] = []
    /// After a first-run connect the card stays up as "Connected" until Open Home.
    var hasOpenedHome: Bool
    /// The window's main pane shows Settings.
    var isShowingSettings = false {
        willSet { if newValue != isShowingSettings { navDirection = .fade } }
        didSet { recordRoute() }
    }
    /// The ⌘K search panel is open.
    var isSearching = false
    /// What ⌘K opens with typed in (a deep link, a sweep shot); empty normally.
    var searchSeed = ""
    /// The New requirement sheet is open (Home dock, ⌘N, ⌘K action).
    var isComposingRequirement = false
    /// The company menu (⌘⇧O) and the keyboard sheet (?) are open.
    var isSwitchingCompany = false
    /// The New company wizard is open (switcher menu, ⌘K), and what it has collected.
    var isCreatingCompany = false
    var newCompany = NewCompanySession()
    var isShowingShortcuts = false
    /// The window's toasts (top-right), shown after an action lands.
    let toasts = AinkradRichToastCenter()

    func toast(_ toast: AinkradRichToast) { toasts.show(toast) }
    /// Who the key acts as (`/me` user), for Home's greeting; the server's API minor, for Connect.
    var userName: String?
    var apiMinor: Int?
    /// The sidebar's screen, and the agent or run opened from it (screens 04 and 05).
    var screen: Screen = .home {
        willSet { if newValue != screen { navDirection = .fade } }
        didSet { recordRoute() }
    }
    var detail: Detail? {
        willSet { if let newValue, newValue != detail { navDirection = .push } }
        didSet { recordRoute() }
    }
    /// How the next screen change animates, and the back/forward history (⌘[ ⌘]).
    var navDirection: NavDirection = .fade
    var history: [Route] = []
    var historyIndex = -1
    @ObservationIgnored var isTravelling = false
    @ObservationIgnored var routePending = false
    /// The approval open in the inbox (06) and the agent thread open on screen 07; `nil` is the first.
    var selectedApproval: Int64?
    var selectedThread: ThreadKey?
    /// An action the server refused (mockup 11 G), shown until dismissed.
    var actionFailure: ActionFailure?
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

    func openHome() {
        hasOpenedHome = true
        let who = [company?.name, agentCount.map { "\($0) agents" }].compactMap { $0 }.joined(separator: " · ")
        toast(
            AinkradRichToast(
                title: "Connected to \(host)", body: "\(who) · replayed \(replayed) events", status: .success))
    }

    func select(company id: Int64, announce: Bool = true) {
        guard id != settings.document.companyID, let server else { return }
        saveCursor(force: true)
        remember(company: id)
        recentEvents = []
        agentCount = nil
        model = nil
        detail = nil
        stream?.stop()
        startStream(server.scoped(to: id))
        Task { agentCount = try? await server.scoped(to: id).agentCount(company: id) }
        if announce, let name = companies.first(where: { $0.id == id })?.name {
            toast(
                AinkradRichToast(
                    title: "Switched to \(name)", body: "Accounts, runners and cost are per company — nothing is mixed."
                ))
        }
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
        // A retry while offline stays offline until it succeeds: the bar and its Retry never blink away.
        if case .offline = phase {} else { phase = .connecting(step: 1, label: "Checking key", since: Date()) }
        let base = CitadelServer(address: address, deviceKey: key, company: nil, session: session)
        let previousServer = settings.document.server
        do {
            let me = try await base.me()
            let companies = me.companies
            guard !Task.isCancelled else { return }
            serverVersion = me.version
            userName = me.userName
            apiMinor = me.apiMinor
            catchUpTotal = cursor.map { Int(max(0, me.latestSeq - $0)) }
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
            loadCompanyLogos(using: base)
            let pick = await startingCompany(
                companies, origin: address.origin.absoluteString, sameServer: previousServer == serverDraft,
                server: base)
            guard !Task.isCancelled else { return }
            guard let company = companies.first(where: { $0.id == pick }) else {
                phase = .connected
                return
            }
            remember(company: company.id)
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

    /// The company to open: the one last chosen on this server; else the one already open (a document from
    /// before per-server memory); else, on a first connect, the company with the most agents — the one with work —
    /// rather than whichever the server lists first.
    private func startingCompany(
        _ companies: [Components.Schemas.Company], origin: String, sameServer: Bool, server: CitadelServer
    ) async -> Int64? {
        let known = Set(companies.map(\.id))
        if let id = settings.document.companyByServer?[origin], known.contains(id) { return id }
        if sameServer, let id = settings.document.companyID, known.contains(id) { return id }
        guard companies.count > 1 else { return companies.first?.id }
        var best: (id: Int64, agents: Int)?
        for company in companies {
            let agents = (try? await server.scoped(to: company.id).agentCount(company: company.id)) ?? 0
            if agents > (best?.agents ?? -1) { best = (company.id, agents) }
        }
        return best?.id
    }

    /// The company the window works in, remembered for this server.
    private func remember(company id: Int64) {
        settings.update {
            $0.companyID = id
            if let origin = $0.server { $0.companyByServer = ($0.companyByServer ?? [:]).merging([origin: id]) { $1 } }
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
                if case .offline = phase {
                    toast(
                        AinkradRichToast(
                            title: "Back online", body: "Replayed \(replayed) events — nothing was missed.",
                            status: .success))
                }
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
