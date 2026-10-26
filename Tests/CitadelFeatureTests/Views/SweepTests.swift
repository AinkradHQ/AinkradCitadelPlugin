import AinkradAppKit
import AppKit
import CitadelClient
import SwiftUI
import XCTest

@testable import CitadelFeature

/// Citadel's screens under Neon and Liquid Glass, written as `<dir>/<name>-neon.png` / `-glass.png` for
/// screen-by-screen review against `Designs/citadel/_renders`. A tool, not a check: it runs only with
/// AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR (the catalog's `themes/`) set. Live window captures — off-screen
/// `cacheDisplay` cannot draw Liquid Glass. XCTest, not Swift Testing: a Swift Testing `@MainActor` test runs on
/// the main queue, so the window's own main-queue work never runs while it waits.
@MainActor
final class SweepTests: XCTestCase {
    private let server = "https://citadel.ainkrad.io"
    private let key = "ck_dev_FAKE_fixture_0000007Q2m"

    func testShootConnectAndSharedStates() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["AINKRAD_SWEEP_DIR"], let themes = env["AINKRAD_THEMES_DIR"] else {
            throw XCTSkip("set AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR to shoot the screens")
        }
        let glass = try Self.glassSkin(themes: URL(fileURLWithPath: themes))
        Self.registerHostFonts()
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        for (theme, skin) in [("glass", glass)] {  // Liquid Glass only (Ahmed, 2026-10-24)
            let hostTheme = HostTheme(HostThemeTokens(skin: skin))
            hostTheme.updateStatusColors(
                HostStatusColors(
                    success: skin.color(skin.palette.success), warning: skin.color(skin.palette.warning),
                    danger: skin.color(skin.palette.danger)))
            let only = env["AINKRAD_SWEEP_ONLY"].flatMap {
                $0.isEmpty ? nil : $0.split(separator: ",").map(String.init)
            }
            for (name, store, size) in screens() where only?.contains(where: name.hasPrefix) ?? true {
                try LiveCapture.shoot(
                    RootView(store: store, theme: hostTheme)
                        .ainkradSheet(isPresented: .constant(Self.sheet(name, store) != nil)) {
                            Self.sheet(name, store)
                        }
                        .frame(width: size.width, height: size.height)
                        // As the host draws it: the window's glass fill over the workspace sky.
                        .background(skin.color(skin.palette.background).opacity(SettingsDocument.defaultSurfaceOpacity))
                        .background(SweepBackdrop())
                        .ainkradSkin(skin)
                        // As the host: Exo 2 under Neon, the system face under Glass.
                        .environment(
                            \.ainkradTypography, AinkradTypography(fontFamilyName: theme == "neon" ? "Exo 2" : nil)
                        )
                        .environment(\.colorScheme, .dark),
                    size: size,
                    to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(theme).png"))
            }
        }
    }

    /// Every state, staged on a store that never touches the network.
    private func screens() -> [(String, CitadelStore, CGSize)] {
        let companies = [
            Components.Schemas.Company(
                accountIds: [], description: "", id: 1, industries: [], kind: .init(value1: .own), name: "Ainkrad"),
            Components.Schemas.Company(
                accountIds: [], description: "", id: 2, industries: [], kind: .init(value1: .client),
                name: "AutomotiveAi"),
            Components.Schemas.Company(
                accountIds: [], description: "", id: 3, industries: [], kind: .init(value1: .client), name: "Optimus"),
        ]
        func store(connectedBefore: Bool, _ stage: (CitadelStore) -> Void) -> CitadelStore {
            let docs = MemoryDocs()
            let secrets = MemorySecrets()
            let settings = SettingsStore(documents: docs)
            settings.update {
                $0.server = server
                $0.companyID = 1
                $0.hasConnected = connectedBefore
                $0.lastSeen = Date().addingTimeInterval(-180)
                $0.cursors["\(server)|1"] = 18_442
            }
            if connectedBefore { secrets.storage["device-key \(server)"] = key }
            let store = CitadelStore(
                settings: settings, secrets: secrets, session: FakeServer.session(), connector: FakeSockets().connector)
            store.companies = companies
            stage(store)
            return store
        }
        func company(
            _ screen: Screen, detail: Detail? = nil, _ stage: (CompanyModel) -> Void = { _ in }
        ) -> CitadelStore {
            store(connectedBefore: true) {
                $0.agentCount = 18
                $0.phase = .connected
                $0.streamStatus = .live
                $0.userName = "Ahmed"
                $0.apiMinor = 18
                let model = CompanyFixture.model()
                stage(model)
                CompanyFixture.trancheB(model)
                $0.model = model
                $0.screen = screen
                $0.detail = detail
            }
        }
        let small = CGSize(width: 1200, height: 720)
        let shots: [(String, CitadelStore)] = [
            ("01-connect-setup", store(connectedBefore: false) { _ in }),
            (
                "01-connect-connecting",
                store(connectedBefore: false) {
                    $0.keyDraft = key
                    $0.phase = .connecting(step: 2, label: "Checking key", since: Date().addingTimeInterval(-0.18))
                }
            ),
            (
                "01-connect-connected",
                store(connectedBefore: false) {
                    $0.phase = .connected
                    $0.agentCount = 18
                    $0.latency = .milliseconds(42)
                    $0.serverVersion = "0.1.0"
                    $0.replayed = 312
                }
            ),
            (
                "01-connect-rejected",
                store(connectedBefore: false) {
                    $0.keyDraft = key
                    $0.phase = .rejected
                }
            ),
            (
                "01-connect-offline",
                store(connectedBefore: false) {
                    $0.phase = .offline(attempt: 4, retryAt: Date().addingTimeInterval(8), reason: "timed out")
                }
            ),
            (
                "11-b-offline-with-cache",
                store(connectedBefore: true) {
                    $0.agentCount = 18
                    $0.phase = .offline(attempt: 5, retryAt: Date().addingTimeInterval(12), reason: "timed out")
                }
            ),
            (
                "11-c-catching-up",
                store(connectedBefore: true) {
                    $0.agentCount = 18
                    $0.phase = .connected
                    $0.streamStatus = .catchingUp(replayed: 312)
                    $0.catchUpTotal = 1_204
                }
            ),
            (
                "11-d-first-load",
                store(connectedBefore: true) {
                    $0.phase = .connecting(step: 2, label: "Loading Ainkrad", since: Date())
                }
            ),
            (
                "shell-live",
                store(connectedBefore: true) {
                    $0.agentCount = 18
                    $0.phase = .connected
                    $0.streamStatus = .live
                }
            ),
        ]
        // The mockups' window sizes (Designs/citadel/base.css `.window`, and each screen's override).
        let wide = CGSize(width: 1280, height: 800)
        var all: [(String, CitadelStore, CGSize)] = shots.map { ($0.0, $0.1, small) }
        all.append(("02-home", company(.home), CGSize(width: 1400, height: 1060)))
        let offline = company(.home)
        offline.phase = .offline(attempt: 4, retryAt: Date().addingTimeInterval(8), reason: "timed out")
        all.append(("11-b-offline-home", offline, CGSize(width: 1400, height: 900)))
        all.append(("11-e-empty-company", company(.home) { $0.agents = [:] }, CGSize(width: 1400, height: 900)))
        let search = company(.home)
        search.isSearching = true
        all.append(("01-search", search, CGSize(width: 1400, height: 900)))
        let searchQuery = company(.home)
        searchQuery.isSearching = true
        searchQuery.searchSeed = "kes"
        all.append(("01-search-query", searchQuery, CGSize(width: 1400, height: 900)))
        all.append(("03-org", company(.org), wide))
        all.append(("04-agent", company(.org, detail: .agent(4), CompanyFixture.agentPage), wide))
        all.append(
            ("05-run", company(.runs, detail: .run(418), CompanyFixture.runPage), CGSize(width: 1280, height: 1180)))
        let inbox = company(.approvals, CompanyFixture.inboxPage)
        inbox.selectedApproval = 21
        all.append(("06-approvals", inbox, wide))
        for (id, kind) in [(Int64(22), "merge"), (24, "budget"), (25, "hire"), (23, "permission")] {
            let store = company(.approvals, CompanyFixture.inboxPage)
            store.selectedApproval = id
            all.append(("06-approvals-\(kind)", store, wide))
        }
        all.append(("07-chat", company(.threads, CompanyFixture.threadsParity), wide))
        all.append(
            (
                "08-stuck",
                company(.stuck) {
                    CompanyFixture.stuckPage($0)
                    CompanyFixture.runnersPage($0)
                }, wide
            ))
        all.append(("09-cost", company(.cost, CompanyFixture.costPage), CGSize(width: 1280, height: 1100)))
        let stage: SweepStage = { company($0, detail: $1, $2) }
        all += Self.requirementsShots(stage)
        all += Self.threadsShots(stage)
        all += Self.settingsShots(stage)
        all += Self.runnersShots(stage)
        all += Self.approvalsShots(stage)
        all += Self.projectsShots(stage)
        all += Self.orgShots(stage)
        all += Self.costShots(stage)
        all += Self.runsShots(stage)
        all += Self.newCompanyShots(stage)
        return all
    }

    /// The host registers its bundled faces (Exo 2, JetBrains Mono) at launch; the test runner doesn't, so borrow
    /// the installed app's for true-to-app shots.
    static func registerHostFonts() {
        let resources = URL(fileURLWithPath: "/Applications/Ainkrad.app/Contents/Resources")
        let fonts = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        for font in fonts where font.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
    }

    /// `glass-dark.theme` on the standard skin, coloured by `glass-dark.scheme`, composed the way the host's
    /// `ThemeCatalog.compose` does.
    static func glassSkin(themes: URL) throws -> AinkradSkin {
        let dir = themes.appendingPathComponent("glass")
        let base = try JSONEncoder().encode(AinkradSkin.standard)
        let theme = try Data(contentsOf: dir.appendingPathComponent("glass-dark.theme"))
        let variant = try XCTUnwrap(ainkradLoadThemes([base, theme]).themes["glass.dark"])
        var scheme = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("glass-dark.scheme")))
                as? [String: Any])
        scheme.removeValue(forKey: "appearance")
        scheme.removeValue(forKey: "host")
        scheme["base"] = "glass.dark"
        return try AinkradThemeFile(
            decoding: JSONSerialization.data(withJSONObject: scheme), bases: ["glass.dark": variant]
        ).skin
    }
}

/// A connected company store on `screen`, its model staged by the closure.
typealias SweepStage = (Screen, Detail?, (CompanyModel) -> Void) -> CitadelStore

/// Captures a desktop-level window by id (`screencapture -l`): never the user's screen, never focus.
@MainActor
enum LiveCapture {
    private final class KeyAppearancePanel: NSPanel {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        override var canBecomeKey: Bool { false }
        @objc var hasKeyAppearance: Bool { true }
        @objc var hasMainAppearance: Bool { true }
        @objc var _hasActiveAppearance: Bool { true }
        @objc var _hasActiveAppearanceIgnoringKeyFocus: Bool { true }
    }

    static func shoot(_ view: some View, size: CGSize, to url: URL) throws {
        let panel = KeyAppearancePanel(
            contentRect: NSRect(origin: CGPoint(x: 200, y: 200), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(
            rootView: view.environment(\.ainkradMotionBudget, .frozen).environment(\.controlActiveState, .key))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(panel.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0, "no capture for \(url.lastPathComponent)")
    }
}

/// The prototype page's sky (`base.css` body): three soft colour fields over near-black, standing in for the host's
/// blurred workspace behind a translucent pane.
struct SweepBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.02, green: 0.027, blue: 0.047)
                RadialGradient(
                    colors: [Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.35), .clear],
                    center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: geo.size.width * 0.55)
                RadialGradient(
                    colors: [Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.25), .clear],
                    center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: geo.size.width * 0.45)
                RadialGradient(
                    colors: [Color(red: 0.659, green: 0.333, blue: 0.969).opacity(0.25), .clear],
                    center: UnitPoint(x: 0.7, y: 0.2), startRadius: 0, endRadius: geo.size.width * 0.38)
            }
        }
    }
}
