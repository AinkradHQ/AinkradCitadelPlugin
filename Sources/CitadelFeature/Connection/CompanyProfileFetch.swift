import CitadelClient
import Foundation

/// Company settings › General: the profile fields the API stores today (name, kind).
extension CitadelServer {
    /// Renames the company and/or changes its kind (`updateCompany`); absent fields stay.
    func updateCompany(_ id: Int64, name: String?, kind: Components.Schemas.CompanyKind.Value1Payload?) async
        -> ServerAnswer?
    {
        await act {
            try await scoped(to: nil).client.updateCompany(
                path: .init(id: id),
                body: .json(.init(kind: kind.map { .init(value1: $0) }, name: name)))
        }
    }
}
