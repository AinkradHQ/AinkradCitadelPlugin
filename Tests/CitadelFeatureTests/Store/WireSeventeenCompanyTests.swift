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
}
