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
}
