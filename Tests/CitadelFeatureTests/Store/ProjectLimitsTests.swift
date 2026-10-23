import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 14 and 16: the profile and repos as the server sends them, the proposals' diffs, the repo order sent,
/// the limits table's groups, filters, refusals and scope chips — and what is overridden below the company.
@MainActor
final class ProjectLimitsTests: XCTestCase {
    private func connectedStore() throws -> (CitadelStore, CompanyModel) {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        store.model = model
        return (store, model)
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                bytes.append(buffer, count: n)
            }
            stream.close()
            data = bytes
        }
        return (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    nonisolated private static func repo(_ id: Int, _ name: String, primary: Bool = false) -> String {
        #"{"id":\#(id),"project_id":1,"name":"\#(name)","url":"https://github.com/AinkradHQ/\#(name).git","default_branch":"development","position":\#(id),"primary":\#(primary),"commands":{"build":"make build","lint":""},"forge":{"kind":"github","repo":"AinkradHQ/\#(name)","token_file":"/vault/github-tap.token"}}"#
    }

    nonisolated private static func setting(
        _ key: String, _ value: Int, source: String?, scopes: String = #""server","company","project""#
    )
        -> String
    {
        let source = source.map { #""\#($0)""# } ?? "null"
        return
            #"{"key":"\#(key)","description":"","value":\#(value),"default":900,"min":60,"max":7200,"unit":"seconds","scopes":[\#(scopes)],"source":\#(source)}"#
    }

    // MARK: - Screen 14

    func testTheProfileAndReposMapFromTheWire() async throws {
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/projects/1/profile":
                return .init(
                    json:
                        #"{"project_id":1,"profile":{"stack":"Rust","definition_of_done":["Tests pass"],"merge_method":"squash","merged_by":"lead","network":"ask","environments":[{"name":"Production","url":"citadel.ainkrad.io","deploy":"owner"}],"models":[{"role":"Dev","model":"gpt-5.5","small":"mini"}]},"sprint_approval":"product_owner","permission_mode":"accept_edits","injected_bytes":2100,"budget_bytes":4096,"dropped":[],"proposals":[{"id":5,"field":"definition_of_done","title":"DoD","body":"[\"Tests pass\",\"Diff the spec\"]","proposed_by":9}],"updated_at":"2026-10-22T09:00:00.000Z"}"#
                )
            case "/api/v1/projects/1/repos": return .init(json: "[\(Self.repo(1, "citadel", primary: true))]")
            default: return .init(status: 404)
            }
        }
        let (store, _) = try connectedStore()
        let server = try XCTUnwrap(store.server)
        let fetched = await server.profile(project: 1)
        let profile = try XCTUnwrap(fetched)
        XCTAssertEqual(profile.mergeMethod, "squash")
        XCTAssertEqual(profile.mergedBy, "lead")
        XCTAssertEqual(profile.sprintApproval, "product_owner", "plan approval follows the project's policy (#40)")
        XCTAssertEqual(profile.environments.first?.deploy, "owner")
        XCTAssertEqual(profile.models.first?.small, "mini")
        XCTAssertEqual(profile.injectedBytes, 2_100)
        XCTAssertEqual(profile.diff(profile.proposals[0]).new, "Diff the spec", "a list proposal shows what it adds")
        XCTAssertNil(profile.diff(profile.proposals[0]).old)

        let repos = await server.repos(project: 1)
        let repo = try XCTUnwrap(repos?.first)
        XCTAssertEqual(repo.shortURL, "github.com/AinkradHQ/citadel")
        XCTAssertEqual(repo.vaultLine, "vault: github-tap", "a reference into the vault, never the token")
        XCTAssertNil(repo.lint, "an empty command reads as none")
        XCTAssertTrue(repo.isPrimary)
    }

    func testATextProposalStrikesTheOldValueAndTheListReadsItsRepos() {
        let model = CompanyFixture.model()
        CompanyFixture.projectsPage(model)
        let page = model.projectsPage
        let profile = try? XCTUnwrap(page.profiles[1])
        let diff = profile?.diff(ProposalInfo(id: 9, field: "branch_pattern", title: "", body: "\"<key>-<slug>\""))
        XCTAssertEqual(diff?.old, "<type>/<key>-<slug>")
        XCTAssertEqual(diff?.new, "<key>-<slug>")
        XCTAssertEqual(page.subtitle(model.projects[0]), "CIT Scrum · S4 · 3 repos")
        XCTAssertEqual(page.subtitle(model.projects[2]), "MKT Scrum · L2 · no repo")
        XCTAssertEqual(page.overriddenCount(1), 2)
    }

    func testDraggingARepoSendsTheNewMergeOrderByName() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/projects/1/repo-order" else { return .init(status: 404) }
            return .init(json: "[\(Self.repo(2, "plugin")),\(Self.repo(1, "citadel", primary: true))]")
        }
        let (store, model) = try connectedStore()
        CompanyFixture.projectsPage(model)
        let repos = try XCTUnwrap(model.projectsPage.repos[1])
        store.reorderRepos(project: 1, [repos[1], repos[0], repos[2]])
        await eventually { model.projectsPage.repos[1]?.map(\.name) == ["plugin", "citadel"] }
        let request = try XCTUnwrap(FakeServer.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            body(request)["repos"] as? [String], ["ainkrad-citadel-plugin", "citadel", "homebrew-ainkrad"])
    }

    func testARefusedRepoChangeKeepsTheServersOrderAndSaysWhy() async throws {
        FakeServer.serve { _ in
            .init(status: 400, json: Wire.refusal("repo_in_use", "CIT-62 still touches citadel"))
        }
        let (store, model) = try connectedStore()
        CompanyFixture.projectsPage(model)
        let before = try XCTUnwrap(model.projectsPage.repos[1])
        store.reorderRepos(project: 1, before.reversed())
        await eventually { model.projectsPage.problem != nil }
        XCTAssertEqual(model.projectsPage.problem?.message, "CIT-62 still touches citadel")
        XCTAssertEqual(model.projectsPage.problem?.errorID, "err_01JTEST")
        XCTAssertEqual(model.projectsPage.repos[1], before)
        store.removeRepo(before[0])
        await eventually { FakeServer.requests.contains { $0.httpMethod == "DELETE" } }
    }

    func testAProjectOverrideNamesTheCompanyValueItShadows() {
        let model = CompanyFixture.model()
        CompanyFixture.projectsPage(model)
        let page = model.projectsPage
        let stall = try? XCTUnwrap(page.limits(1).first { $0.key == "run.stall_after_secs" })
        XCTAssertEqual(
            stall?.chip(at: "project:1", inherited: page.inherited("run.stall_after_secs")),
            .overridden(at: "project", inheritedValue: "company 15 min"))
        let cap = page.limits(1).first { $0.key == "run.token_cap" }
        XCTAssertEqual(cap?.chip(at: "project:1"), .inherited(from: "company"))
        let profileBudget = page.limits(1).first { $0.key == "profile.budget_bytes" }
        XCTAssertEqual(profileBudget?.chip(at: "project:1"), .inherited(from: "server"))
    }

    // MARK: - Screen 16

    func testTheLimitsTableGroupsFiltersAndSaysWhyACompanyCannotSetIt() {
        let model = CompanyFixture.model()
        CompanyFixture.limitsPage(model)
        let page = model.limitsPage
        let sections = page.sections(1)
        XCTAssertEqual(sections.groups.map(\.0), ["Runs", "Disk & storage", "Cost & usage", "Approvals & knowledge"])
        XCTAssertFalse(sections.more.isEmpty, "the rest waits behind + N more")
        let rows = Dictionary(uniqueKeysWithValues: page.rows.map { ($0.id, $0) })
        XCTAssertEqual(rows["runner.disk_cap_bytes"]?.companyNote, "runners are server-wide")
        XCTAssertEqual(rows["account.warn_percent"]?.companyNote, "accounts are pool-wide")
        XCTAssertEqual(rows["dispatch.fallback_poll_ms"]?.companyNote, "server-wide only")
        XCTAssertNil(rows["run.token_cap"]?.companyNote)

        XCTAssertEqual(page.setHere(1), 4)
        XCTAssertEqual(page.overriddenBelow, 7)
        page.filter = .setHere
        XCTAssertEqual(
            Set(page.sections(1).groups.flatMap { $0.1.map(\.id) }),
            ["run.token_cap", "artifact.company_quota_bytes", "approval.deadline.pr_merge", "knowledge.budget_bytes"])
        page.filter = .overridden
        XCTAssertEqual(page.sections(1).groups.flatMap { $0.1 }.count, 7)
        page.filter = .all
        page.search = "idle"
        XCTAssertEqual(page.sections(1).groups.flatMap { $0.1.map(\.id) }, ["workspace.idle_secs"])
    }

    func testAnOutOfBoundsValueIsRefusedWithItsBoundNeverClamped() {
        let model = CompanyFixture.model()
        CompanyFixture.limitsPage(model)
        let page = model.limitsPage
        page.refused = [:]
        let quota = try? XCTUnwrap(page.company.first { $0.key == "artifact.company_quota_bytes" })
        XCTAssertEqual(quota.map { page.check($0, "900 GB") }, false)
        XCTAssertEqual(page.refused["artifact.company_quota_bytes"], "max 500 GB")
        XCTAssertEqual(quota.map { page.check($0, "100 MB") }, false)
        XCTAssertEqual(page.refused["artifact.company_quota_bytes"], "min 1 GB")
        XCTAssertEqual(quota.map { page.check($0, "40 GB") }, true)
        XCTAssertNil(page.refused["artifact.company_quota_bytes"])
    }

    func testOverridesBelowComeFromTheCompanysOneOverriddenCall() async throws {
        FakeServer.serve { request in
            let stall = "run.stall_after_secs"
            switch request.url?.path {
            case "/api/v1/settings": return .init(json: "[\(Self.setting(stall, 900, source: nil))]")
            case "/api/v1/settings/company:1": return .init(json: "[\(Self.setting(stall, 900, source: "server"))]")
            case "/api/v1/companies/1/settings/overridden":
                return .init(
                    json:
                        #"[{"key":"run.stall_after_secs","description":"","unit":"seconds","default":900,"scope":"project:1","value":600,"set_by":{"kind":"agent","agent_id":7},"set_at":"2026-10-22T08:02:00.000Z"}]"#
                )
            case "/api/v1/settings/company:1/run.stall_after_secs/history",
                "/api/v1/settings/project:1/run.stall_after_secs/history":
                return .init(json: "[]")
            case let path? where path.hasPrefix("/api/v1/settings/project:1/"):
                return .init(
                    json:
                        #"[{"actor":{"kind":"agent","agent_id":7},"at":"2026-10-22T08:02:00.000Z","old":900,"new":600,"scope":"project:1","seq":12}]"#
                )
            default: return .init(json: "[]")
            }
        }
        let (store, model) = try connectedStore()
        store.loadLimitsPage()
        await eventually(5) { model.limitsPage.isLoaded }
        XCTAssertEqual(
            model.limitsPage.below["run.stall_after_secs"],
            [LimitOverride(scope: "project:1", owner: "CIT", value: "10 min")],
            "a scope that only inherits is not an override")
        XCTAssertEqual(model.limitsPage.setHere(1), 0)
        let paths = FakeServer.requests.compactMap(\.url?.path)
        XCTAssertFalse(paths.contains { $0.hasPrefix("/api/v1/settings/project:") && !$0.hasSuffix("/history") })
    }
}
