import CitadelClient
import Foundation

/// Company settings › General: the profile the API stores (name, kind, and from minor 17 colour, time zone, working
/// hours and days) and the logo.
extension CitadelServer {
    /// Changes the company's profile (`updateCompany`); absent fields stay.
    func updateCompany(_ id: Int64, _ change: Components.Schemas.CompanyChange) async -> ServerAnswer? {
        await act { try await scoped(to: nil).client.updateCompany(path: .init(id: id), body: .json(change)) }
    }

    /// Removes the company's uploaded logo (`resetCompanyLogo`): its colour and initial show again.
    func resetLogo(company id: Int64) async -> ServerAnswer? {
        await act { try await scoped(to: nil).client.resetCompanyLogo(path: .init(id: id)) }
    }
}
