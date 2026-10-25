import AppKit
import Foundation
import Observation

/// The companies' uploaded logos by company id (`GET /companies/{id}/logo`, API minor 17).
@MainActor
@Observable
final class CompanyLogos {
    var images: [Int64: NSImage] = [:]
}

extension CitadelStore {
    /// Reads the logo of each company that has one, the way agent avatars load; an older server has none.
    func loadCompanyLogos(using server: CitadelServer) {
        guard serverSupports(minor: Self.structureMinor) else { return }
        for company in companies where company.logoUrl != nil && logos.images[company.id] == nil {
            Task {
                if let data = await server.logo(company: company.id), let image = NSImage(data: data) {
                    logos.images[company.id] = image
                }
            }
        }
    }

    /// Uploads the company's logo (PNG, JPEG or WebP, as the server takes them); the mark shows it at once.
    func setCompanyLogo(_ data: Data, type: String) {
        guard let server, let company, serverSupports(minor: Self.structureMinor) else { return }
        Task {
            if let answer = await server.uploadLogo(company: company.id, data: data, type: type) {
                actionFailure = ActionFailure(
                    title: "Couldn't upload \(company.name)'s logo", answer: answer, outcome: "Its logo is unchanged.")
                return
            }
            logos.images[company.id] = NSImage(data: data)
            if let index = companies.firstIndex(where: { $0.id == company.id }) {
                companies[index].logoUrl = "/api/v1/companies/\(company.id)/logo"
            }
        }
    }

    /// Removes the company's uploaded logo; its colour and initial show again.
    func removeCompanyLogo() {
        guard let server, let company, serverSupports(minor: Self.structureMinor) else { return }
        Task {
            if let answer = await server.resetLogo(company: company.id) {
                actionFailure = ActionFailure(
                    title: "Couldn't remove \(company.name)'s logo", answer: answer, outcome: "Its logo is kept.")
                return
            }
            logos.images[company.id] = nil
            if let index = companies.firstIndex(where: { $0.id == company.id }) {
                companies[index].logoUrl = nil
            }
        }
    }
}
