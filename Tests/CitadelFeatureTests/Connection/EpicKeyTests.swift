import Foundation
import XCTest

@testable import CitadelFeature

/// The plan rail names each epic by its key (API minor 9), read from its project's epics.
@MainActor
final class EpicKeyTests: XCTestCase {
    func testThePlanCarriesEachEpicsKey() async throws {
        let cost =
            #"{"runs":0,"priced_runs":0,"unpriced_runs":0,"subscription_runs":0,"cost_usd_micros":0,"input_tokens":0,"output_tokens":0,"cache_tokens":0,"unpriced_tokens":0,"subscription_tokens":0}"#
        let requirement =
            #"{"id":12,"company_id":1,"key":"REQ-12","number":12,"title":"Devices","body":"","requested_by_user_id":1,"state":"in_progress","plan_version":1,"created_at":"2026-10-20T10:00:00.000Z"}"#
        let tree =
            #"{"requirement":\#(requirement),"epics":[{"epic_id":5,"project_id":1,"title":"Device keys","status":"in_progress","points":8,"done_points":3,"tasks":[]}],"other":[],"points":8,"done_points":3,"percent_done":37,"tasks":0,"done_tasks":0,"burndown":[],"points_per_day":1.5,"cost":\#(cost)}"#
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/requirements/12/tree": .init(json: tree)
            case "/api/v1/projects/1/epics":
                .init(
                    json:
                        #"[{"id":5,"key":"CIT-E3","number":3,"project_id":1,"title":"Device keys","status":"in_progress"}]"#
                )
            default: .init(status: 404, json: Wire.refusal("not_found", "no"))
            }
        }
        let server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let read = await server.plan(requirement: 12)
        let plan = try XCTUnwrap(read)
        XCTAssertEqual(plan.epics.map(\.key), ["CIT-E3"])
    }
}
