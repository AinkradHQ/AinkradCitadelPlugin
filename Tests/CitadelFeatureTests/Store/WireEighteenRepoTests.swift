import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B1: a repo's stack and who is using it, and the staged check before it is added.
@MainActor
final class WireEighteenRepoTests: XCTestCase {
    nonisolated static let repo =
        #"{"id":4,"project_id":1,"name":"citadel","url":"https://github.com/AinkradHQ/citadel","default_branch":"development","position":0,"primary":true,"commands":{"build":"make build"},"stack":"Rust · Node","in_use_by":["CIT-12","CIT-14"]}"#
    nonisolated static let probed =
        #"{"reachable":true,"can_push":true,"default_branch":"main","stack":"Rust","commands":{"build":"cargo build","test":"cargo test"},"note":"push and PR checked"}"#

    private func make(minor: Int?) throws -> (CitadelStore, CompanyModel) {
        let store = try Wire17.store(minor: minor)
        return (store, try XCTUnwrap(store.model))
    }

    func testARepoReadsItsStackAndWhoUsesItAndSurvivesTheirAbsence() throws {
        let full = RepoInfo(try JSONDecoder().decode(Schemas.Repo.self, from: Data(Self.repo.utf8)))
        XCTAssertEqual(full.stack, "Rust · Node")
        XCTAssertEqual(full.inUseBy, ["CIT-12", "CIT-14"])
        let bare = RepoInfo(
            try JSONDecoder().decode(
                Schemas.Repo.self,
                from: Data(
                    #"{"id":5,"project_id":1,"name":"web","url":"u","default_branch":"main","position":1,"primary":false,"commands":{}}"#
                        .utf8)))
        XCTAssertNil(bare.stack)
        XCTAssertEqual(bare.inUseBy, [])
    }

    func testTheStagedCheckSendsTheUrlAndTokenAndNothingIsSaved() async throws {
        let (store, _) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.probed) }
        var result: Result<RepoProbe, ServerAnswer>?
        store.probeRepo(
            project: 1, name: "AinkradHQ/web", url: "https://github.com/AinkradHQ/web", forge: "github",
            tokenFile: "github-ainkradhq"
        ) { result = $0 }
        let body = try await Wire17.sent("POST", "/api/v1/projects/1/repos/probe")
        XCTAssertEqual(body["url"] as? String, "https://github.com/AinkradHQ/web")
        let forge = try XCTUnwrap(body["forge"] as? [String: Any])
        XCTAssertEqual(forge["token_file"] as? String, "github-ainkradhq")
        XCTAssertEqual(forge["kind"] as? String, "github")
        await eventually { result != nil }
        let probe = try XCTUnwrap(try? result?.get())
        XCTAssertTrue(probe.passes)
        XCTAssertEqual(probe.stack, "Rust")
        XCTAssertEqual(probe.defaultBranch, "main")
        XCTAssertEqual(probe.test, "cargo test")
        XCTAssertFalse(Wire17.didSend("POST", "/api/v1/projects/1/repos"), "a check saves nothing")
    }

    func testARepoThatCannotPushOrIsUnreachableDoesNotPass() {
        let base = RepoProbe(reachable: true, canPush: true, defaultBranch: nil, stack: "")
        XCTAssertTrue(base.passes)
        XCTAssertTrue(
            RepoProbe(reachable: true, canPush: nil, defaultBranch: nil, stack: "").passes, "no token to check")
        XCTAssertFalse(RepoProbe(reachable: true, canPush: false, defaultBranch: nil, stack: "").passes)
        XCTAssertFalse(RepoProbe(reachable: false, canPush: nil, defaultBranch: nil, stack: "").passes)
    }

    func testAddingAfterTheCheckSavesTheStackAndCommandsItRead() async throws {
        let (store, _) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.repo) }
        let probe = RepoProbe(
            reachable: true, canPush: true, defaultBranch: "main", stack: "Rust", build: "cargo build",
            test: "cargo test")
        store.addRepo(
            project: 1, name: "web", url: "https://github.com/AinkradHQ/web", branch: "main", forge: "github",
            tokenFile: "", probe: probe)
        let body = try await Wire17.sent("POST", "/api/v1/projects/1/repos")
        XCTAssertEqual(body["stack"] as? String, "Rust")
        let commands = try XCTUnwrap(body["commands"] as? [String: Any])
        XCTAssertEqual(commands["build"] as? String, "cargo build")
        XCTAssertEqual(commands["test"] as? String, "cargo test")
    }

    func testAnOlderServerIsNeitherProbedNorSentWhatTheCheckFound() async throws {
        let (store, _) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: Self.repo) }
        store.probeRepo(project: 1, name: "web", url: "u", forge: "github", tokenFile: "t") { _ in
            XCTFail("an older server has no check")
        }
        store.addRepo(
            project: 1, name: "web", url: "u", branch: "main", forge: "github", tokenFile: "",
            probe: RepoProbe(reachable: true, canPush: true, defaultBranch: nil, stack: "Rust", build: "cargo build"))
        let body = try await Wire17.sent("POST", "/api/v1/projects/1/repos")
        XCTAssertNil(body["stack"])
        XCTAssertNil(body["commands"])
        XCTAssertFalse(Wire17.didSend("POST", "/api/v1/projects/1/repos/probe"))
    }
}
