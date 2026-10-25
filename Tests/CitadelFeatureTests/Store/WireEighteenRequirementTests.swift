import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B1: pausing, resuming and finishing a requirement, and a new one naming its project,
/// priority and criteria.
@MainActor
final class WireEighteenRequirementTests: XCTestCase {
    nonisolated static let requirement =
        #"{"id":12,"company_id":1,"key":"R-12","number":12,"title":"Phone alerts","body":"","requested_by_user_id":1,"state":"in_progress","plan_version":1,"created_at":"2026-10-22T09:00:00.000Z","paused_at":"2026-10-25T10:00:00.000Z"}"#

    private func make(minor: Int?) throws -> (CitadelStore, CompanyModel, RequirementInfo) {
        let store = try Wire17.store(minor: minor)
        let model = try XCTUnwrap(store.model)
        CompanyFixture.requirementsPage(model)
        return (store, model, try XCTUnwrap(model.requirements.first { $0.id == 12 }))
    }

    func testPauseThenResumeCallTheServerAndTheHeroFollows() async throws {
        let (store, model, requirement) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.requirement) }
        store.pause(requirement: requirement)
        _ = try await Wire17.sent("POST", "/api/v1/requirements/12/pause")
        await eventually { model.requirements.first { $0.id == 12 }?.pausedAt != nil }
        store.resume(requirement: requirement)
        _ = try await Wire17.sent("POST", "/api/v1/requirements/12/resume")
        await eventually { model.requirements.first { $0.id == 12 }?.pausedAt == nil }
    }

    func testMarkDoneFinishesItAndARefusalKeepsItInProgressWithTheServersReason() async throws {
        let (store, model, requirement) = try make(minor: 18)
        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "3 of its issues are still open")) }
        store.markDone(requirement: requirement)
        _ = try await Wire17.sent("POST", "/api/v1/requirements/12/done")
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.answer.message, "3 of its issues are still open")
        XCTAssertEqual(model.requirements.first { $0.id == 12 }?.state, "in_progress")

        FakeServer.serve { _ in .init(json: Self.requirement.replacingOccurrences(of: "in_progress", with: "done")) }
        store.markDone(requirement: requirement)
        await eventually { model.requirements.first { $0.id == 12 }?.state == "done" }
    }

    func testAnOlderServerGetsNoPauseResumeOrDone() async throws {
        let (store, _, requirement) = try make(minor: 17)
        FakeServer.serve { _ in .init(status: 404) }
        store.pause(requirement: requirement)
        store.resume(requirement: requirement)
        store.markDone(requirement: requirement)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(FakeServer.requests.filter { $0.httpMethod != "GET" }.isEmpty)
        XCTAssertNil(store.actionFailure)
    }

    func testTheRequirementReadsWhenItWasPausedAndSurvivesItsAbsence() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom {
            let text = try $0.singleValueContainer().decode(String.self)
            return try Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        let paused = RequirementInfo(try decoder.decode(Schemas.Requirement.self, from: Data(Self.requirement.utf8)))
        XCTAssertNotNil(paused.pausedAt)
        let running = RequirementInfo(
            try decoder.decode(
                Schemas.Requirement.self,
                from: Data(
                    Self.requirement.replacingOccurrences(of: #","paused_at":"2026-10-25T10:00:00.000Z""#, with: "")
                        .utf8)))
        XCTAssertNil(running.pausedAt)
    }

    func testANewRequirementCarriesItsProjectPriorityAndCriteriaAsFieldsFromMinor18() async throws {
        let (store, _, _) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: Self.requirement) }
        store.sendNewRequirement(
            title: "Weekly cost report", body: "Per project, Mondays",
            extras: RequestExtras(project: 2, priority: "urgent", criteria: ["Arrives Monday 9:00", "Per project"]))
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/requests")
        XCTAssertEqual(body["project_id"] as? Int, 2)
        XCTAssertEqual(body["priority"] as? String, "urgent")
        XCTAssertEqual(body["criteria"] as? [String], ["Arrives Monday 9:00", "Per project"])
        XCTAssertEqual(body["body"] as? String, "Per project, Mondays")
    }

    func testAnOlderServerGetsTheRequestAsTitleAndBodyOnly() async throws {
        let (store, _, _) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: Self.requirement) }
        store.sendNewRequirement(
            title: "Weekly cost report", body: "Per project\n\nPriority: urgent",
            extras: RequestExtras(project: 2, priority: "urgent", criteria: ["x"]))
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/requests")
        XCTAssertNil(body["project_id"])
        XCTAssertNil(body["priority"])
        XCTAssertNil(body["criteria"])
        XCTAssertEqual(body["body"] as? String, "Per project\n\nPriority: urgent")
    }
}
