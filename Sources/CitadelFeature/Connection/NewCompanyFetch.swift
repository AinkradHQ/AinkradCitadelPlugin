import CitadelClient
import Foundation
import OpenAPIRuntime

/// The New company wizard's two writes that have no other caller: the company itself and its logo.
extension CitadelServer {
    func createCompany(_ body: Schemas.NewCompany) async -> Result<Schemas.Company, ServerAnswer> {
        await attempt({ try await scoped(to: nil).client.createCompany(body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json
        }
    }

    /// PNG, JPEG or WebP, as the server takes them.
    func uploadLogo(company: Int64, data: Data, type: String) async -> ServerAnswer? {
        let body = HTTPBody(data)
        let payload: Operations.UploadCompanyLogo.Input.Body =
            switch type {
            case "image/jpeg": .jpeg(body)
            case "image/webp": .imageWebp(body)
            default: .png(body)
            }
        return await act { try await client.uploadCompanyLogo(path: .init(id: company), body: payload) }
    }
}
