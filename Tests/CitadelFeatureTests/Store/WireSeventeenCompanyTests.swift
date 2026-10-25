import AppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, company look: `color` replaces the derived colour and `logo_url` brings the logo.
@MainActor
final class WireSeventeenCompanyTests: XCTestCase {
    private static let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func company(color: String?, logo: String?) throws -> Components.Schemas.Company {
        let extra =
            (color.map { #","color":"\#($0)""# } ?? "") + (logo.map { #","logo_url":"\#($0)""# } ?? "")
        return try JSONDecoder().decode(
            Components.Schemas.Company.self,
            from: Data(#"{"id":7,"name":"Ainkrad","kind":"own","account_ids":[]\#(extra)}"#.utf8))
    }

    func testAStoredColourIsReadAsRGBAndAnythingElseIsIgnored() throws {
        let rgb = try XCTUnwrap(CompanyLook.rgb("#ff8000"))
        XCTAssertEqual(rgb.red, 1, accuracy: 0.001)
        XCTAssertEqual(rgb.green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(rgb.blue, 0, accuracy: 0.001)
        XCTAssertNil(CompanyLook.rgb(nil), "an older server sends no colour")
        XCTAssertNil(CompanyLook.rgb("orange"))
        XCTAssertNil(CompanyLook.rgb("#12345"))
        XCTAssertEqual(try company(color: "#112233", logo: nil).color, "#112233")
    }

    func testALogoIsLoadedWhenTheCompanyHasOne() async throws {
        let store = try Wire17.store()
        store.companies = [try company(color: nil, logo: "/api/v1/companies/7/logo")]
        FakeServer.serve { _ in .init(data: Self.png, contentType: "image/png") }
        store.loadCompanyLogos(using: try XCTUnwrap(store.server))
        await eventually { store.logos.images[7] != nil }
        XCTAssertTrue(Wire17.didSend("GET", "/api/v1/companies/7/logo"))
    }

    func testNoLogoIsAskedForWithoutOneOrOnAnOlderServer() async throws {
        let store = try Wire17.store()
        store.companies = [try company(color: nil, logo: nil)]
        FakeServer.serve { _ in .init(data: Self.png, contentType: "image/png") }
        store.loadCompanyLogos(using: try XCTUnwrap(store.server))
        let old = try Wire17.store(minor: 16)
        old.companies = [try company(color: nil, logo: "/api/v1/companies/7/logo")]
        old.loadCompanyLogos(using: try XCTUnwrap(old.server))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(Wire17.didSend("GET", "/api/v1/companies/7/logo"))
    }

    /// Item 1: the General save writes colour, time zone, working hours and days in one `updateCompany`.
    func testTheProfileSavesItsColourTimeAndDaysThroughUpdateCompany() async throws {
        let store = try Wire17.store()
        store.companies = [try company(color: nil, logo: nil)]
        FakeServer.serve { _ in .init(json: #"{"id":7,"name":"Ainkrad","kind":"own","account_ids":[]}"#) }
        store.saveCompany(
            .init(
                color: "#2563eb", kind: .init(value1: .own), name: "Ainkrad", timezone: "Europe/Berlin", workDays: 31,
                workEnd: 1080, workStart: 540))
        let body = try await Wire17.sent("PUT", "/api/v1/companies/7")
        XCTAssertEqual(body["color"] as? String, "#2563eb")
        XCTAssertEqual(body["timezone"] as? String, "Europe/Berlin")
        XCTAssertEqual(body["work_start"] as? Int, 540)
        XCTAssertEqual(body["work_end"] as? Int, 1080)
        XCTAssertEqual(body["work_days"] as? Int, 31)
        await eventually { store.companies.first?.color == "#2563eb" }
    }

    /// Item 1, gate: an older server keeps today's write (name and kind only).
    func testAnOlderServerStillGetsOnlyNameAndKind() async throws {
        let store = try Wire17.store(minor: 16)
        store.companies = [try company(color: nil, logo: nil)]
        FakeServer.serve { _ in .init(json: "{}") }
        store.saveCompany(.init(color: "#2563eb", kind: .init(value1: .client), name: "Ainkrad", workDays: 31))
        let body = try await Wire17.sent("PUT", "/api/v1/companies/7")
        XCTAssertEqual(body["name"] as? String, "Ainkrad")
        XCTAssertNil(body["color"])
        XCTAssertNil(body["work_days"])
    }

    /// Item 1: a logo is uploaded to, and removed from, the company's logo endpoint.
    func testALogoIsUploadedThenRemovedThroughTheCompanyLogoEndpoint() async throws {
        let store = try Wire17.store()
        store.companies = [try company(color: nil, logo: nil)]
        FakeServer.serve { _ in .init(json: "{}") }
        store.setCompanyLogo(Self.png, type: "image/png")
        await eventually { Wire17.didSend("PUT", "/api/v1/companies/7/logo") }
        store.removeCompanyLogo()
        await eventually { Wire17.didSend("DELETE", "/api/v1/companies/7/logo") }
    }
}
