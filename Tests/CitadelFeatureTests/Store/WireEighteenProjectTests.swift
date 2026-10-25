import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B1: a project's identity, teams, runtime, rules, context text and cumulative flow.
@MainActor
final class WireEighteenProjectTests: XCTestCase {
    nonisolated static let project =
        ##"{"id":1,"company_id":1,"name":"Citadel","key":"CIT","mode":"scrum","sprint_approval":"owner","icon":"✦","color":"#a78bfa","team_ids":[2,1],"team_id":2,"runner_tags":["linux"],"max_parallel_runs":6,"run_timeout_secs":1800,"worktree_keep_days":5}"##
    nonisolated static let profile =
        #"{"project_id":1,"profile":{"stack":"Rust","definition_of_done_rules":[{"text":"Tests pass","on":true},{"text":"Docs","on":false}],"network_hosts":["crates.io"]},"sprint_approval":"owner","permission_mode":"ask","injected_bytes":10,"budget_bytes":4096,"dropped":[],"proposals":[]}"#

    private func make(minor: Int?) throws -> (CitadelStore, CompanyModel) {
        let store = try Wire17.store(minor: minor)
        return (store, try XCTUnwrap(store.model))
    }

    func testAProjectReadsItsIdentityAndSurvivesItsAbsence() throws {
        let full = ProjectInfo(try JSONDecoder().decode(Schemas.Project.self, from: Data(Self.project.utf8)))
        XCTAssertEqual(full.icon, "✦")
        XCTAssertEqual(full.color, "#a78bfa")
        XCTAssertEqual(full.teamIDs, [2, 1])
        XCTAssertEqual(full.allTeamIDs, [2, 1])
        XCTAssertEqual(full.runnerTags, ["linux"])
        XCTAssertEqual(full.maxParallelRuns, 6)
        XCTAssertEqual(full.runTimeoutSecs, 1800)
        XCTAssertEqual(full.worktreeKeepDays, 5)
        let bare = ProjectInfo(
            try JSONDecoder().decode(
                Schemas.Project.self,
                from: Data(
                    #"{"id":2,"company_id":1,"name":"A","key":"AMC","mode":"kanban","sprint_approval":"owner","team_id":3}"#
                        .utf8)))
        XCTAssertNil(bare.icon)
        XCTAssertEqual(bare.allTeamIDs, [3], "the owner alone from a server without team_ids")
    }

    func testAStoredColourTintsTheProjectAndAnUnknownOneStillHasADeepShade() throws {
        let known = try XCTUnwrap(ProjectIdentity.pair("#A78BFA"))
        XCTAssertNotEqual(known.0, known.1)
        XCTAssertNotNil(ProjectIdentity.pair("#123456"))
        XCTAssertNil(ProjectIdentity.pair("violet"))
        XCTAssertNil(ProjectIdentity.pair(nil))
    }

    func testAttachingATeamKeepsTheOwnerFirstAndMakeOwnerMovesOne() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.project) }
        let teams = model.departments.flatMap(\.teams)
        let project = try XCTUnwrap(model.projects.first)  // owner team 1
        store.toggleTeam(try XCTUnwrap(teams.first { $0.id == 2 }), project: project)
        var body = try await Wire17.sent("PUT", "/api/v1/projects/1")
        XCTAssertEqual(body["team_ids"] as? [Int], [1, 2])
        await eventually { model.projects.first?.teamIDs == [2, 1] }

        FakeServer.serve { _ in .init(json: Self.project) }
        var two = project
        two.teamIDs = [1, 2]
        store.makeOwner(try XCTUnwrap(teams.first { $0.id == 2 }), project: two)
        body = try await Wire17.sent("PUT", "/api/v1/projects/1")
        XCTAssertEqual(body["team_ids"] as? [Int], [2, 1])
    }

    func testAnOlderServerStillMakesTheTappedTeamTheOnlyOwner() async throws {
        let (store, model) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: Self.project) }
        let team = try XCTUnwrap(model.departments.flatMap(\.teams).first { $0.id == 2 })
        store.toggleTeam(team, project: try XCTUnwrap(model.projects.first))
        let body = try await Wire17.sent("PUT", "/api/v1/projects/1")
        XCTAssertEqual(body["team_id"] as? Int, 2)
        XCTAssertNil(body["team_ids"])
    }

    func testRuntimeFieldsGoAsSecondsAndDaysAndNotBelowMinor18() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.project) }
        let project = try XCTUnwrap(model.projects.first)
        store.setRuntime(project, tags: ["linux", "docker"], parallel: 6, timeoutSecs: 1800, keepDays: 5)
        let body = try await Wire17.sent("PUT", "/api/v1/projects/1")
        XCTAssertEqual(body["runner_tags"] as? [String], ["linux", "docker"])
        XCTAssertEqual(body["max_parallel_runs"] as? Int, 6)
        XCTAssertEqual(body["run_timeout_secs"] as? Int, 1800)
        XCTAssertEqual(body["worktree_keep_days"] as? Int, 5)

        let (old, oldModel) = try make(minor: 17)
        FakeServer.serve { _ in .init(status: 404) }
        old.setRuntime(try XCTUnwrap(oldModel.projects.first), parallel: 3)
        old.setNetworkHosts(project: 1, ["crates.io"])
        old.setDoneRules(project: 1, [DodRuleInfo(text: "x")])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(FakeServer.requests.filter { $0.httpMethod != "GET" }.isEmpty)
    }

    func testNetworkHostsAndDoneRulesRideTheProfile() async throws {
        let (store, _) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.profile) }
        store.setNetworkHosts(project: 1, ["crates.io", "npmjs.org"])
        var body = try await Wire17.sent("PUT", "/api/v1/projects/1/profile")
        XCTAssertEqual(body["network_hosts"] as? [String], ["crates.io", "npmjs.org"])
        FakeServer.serve { _ in .init(json: Self.profile) }
        store.setDoneRules(project: 1, [DodRuleInfo(text: "Tests pass"), DodRuleInfo(text: "Docs", on: false)])
        body = try await Wire17.sent("PUT", "/api/v1/projects/1/profile")
        let rules = try XCTUnwrap(body["definition_of_done_rules"] as? [[String: Any]])
        XCTAssertEqual(rules.map { $0["text"] as? String }, ["Tests pass", "Docs"])
        XCTAssertEqual(rules.map { $0["on"] as? Bool }, [true, false])
        let profile = ProfileInfo(
            try JSONDecoder().decode(Schemas.ProjectProfile.self, from: Data(Self.profile.utf8)))
        XCTAssertEqual(profile.dodRules, [DodRuleInfo(text: "Tests pass"), DodRuleInfo(text: "Docs", on: false)])
        XCTAssertEqual(profile.networkHosts, ["crates.io"])
    }

    func testANewProjectSendsItsIdentityAndTeamsOnlyFromMinor18() async throws {
        let (store, _) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.project) }
        store.createProject(name: "Ops", key: "OPS", mode: "kanban", icon: "⚙", color: "#22d3ee", teams: [2, 1]) { _ in
        }
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/projects")
        XCTAssertEqual(body["icon"] as? String, "⚙")
        XCTAssertEqual(body["color"] as? String, "#22d3ee")
        XCTAssertEqual(body["team_ids"] as? [Int], [2, 1])
        XCTAssertEqual(body["team_id"] as? Int, 2, "the first team owns it")

        let (old, _) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: Self.project) }
        old.createProject(name: "Ops", key: "OPS", mode: "kanban", icon: "⚙", color: "#22d3ee", teams: [2, 1]) { _ in }
        let sent = try await Wire17.sent("POST", "/api/v1/companies/1/projects")
        XCTAssertNil(sent["icon"])
        XCTAssertNil(sent["team_ids"])
    }

    func testTheContextTextAndCumulativeFlowLoadFromMinor18() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/projects/1/profile/preview":
                return .init(
                    json: ##"{"text":"# Project\nStack: Rust","bytes":21,"budget_bytes":4096,"dropped":["docs"]}"##)
            case "/api/v1/projects/1/cfd":
                return .init(
                    json:
                        #"[{"day":"2026-10-20","counts":{"todo":5,"backlog":2,"in_progress":3,"blocked":1,"in_review":1,"done":4,"cancelled":9}},{"day":"2026-10-21","counts":{"todo":4,"in_progress":3,"in_review":2,"done":6}}]"#
                )
            default: return .init(json: "[]")
            }
        }
        store.loadWork(1)
        store.selectProject(1)
        await eventually { model.projectsPage.cfd[1]?.count == 2 && model.projectsPage.preview[1] != nil }
        XCTAssertEqual(
            model.projectsPage.cfd[1]?.first,
            CfdPoint(day: try XCTUnwrap(ProjectLogic.day("2026-10-20")), done: 4, review: 1, active: 4, todo: 7))
        XCTAssertEqual(model.projectsPage.preview[1]?.text, "# Project\nStack: Rust")
        XCTAssertEqual(model.projectsPage.preview[1]?.dropped, ["docs"])

        let (old, oldModel) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: "[]") }
        old.loadWork(1)
        old.selectProject(1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(Wire17.didSend("GET", "/api/v1/projects/1/cfd"))
        XCTAssertFalse(Wire17.didSend("GET", "/api/v1/projects/1/profile/preview"))
        XCTAssertNil(oldModel.projectsPage.cfd[1])
    }

    func testALogoIsUploadedAsItsImageTypeAndRemoved() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.project) }
        let project = try XCTUnwrap(model.projects.first)
        store.setProjectLogo(Data([0x89, 0x50, 0x4e, 0x47]), type: "image/png", project: project)
        await eventually { Wire17.didSend("PUT", "/api/v1/projects/1/logo") }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/projects/1/logo" })
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
        store.removeProjectLogo(project)
        await eventually { Wire17.didSend("DELETE", "/api/v1/projects/1/logo") }
    }
}
