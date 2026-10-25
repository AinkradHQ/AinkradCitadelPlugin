import CitadelClient
import Foundation
import OpenAPIRuntime

/// API minor 18, the project page: its identity and teams (`PATCH /projects/{id}`), logo, the run context preview
/// and the cumulative flow.
extension CitadelServer {
    /// Changes only the settings `settings` names; the project as the server keeps it.
    func updateProject(_ project: Int64, _ settings: Schemas.ProjectSettings) async -> Result<ProjectInfo, ServerAnswer>
    {
        await attempt({ try await client.updateProject(path: .init(id: project), body: .json(settings)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ProjectInfo(try ok.body.json)
        }
    }

    /// The project's uploaded logo, when it has one.
    func projectLogo(_ project: Int64) async -> Data? {
        await read("getProjectLogo") {
            guard case .ok(let ok) = try await client.getProjectLogo(path: .init(id: project)) else { return nil }
            let body: HTTPBody =
                switch ok.body {
                case .jpeg(let b), .png(let b), .imageWebp(let b): b
                }
            return try await Data(collecting: body, upTo: 4 << 20)
        }
    }

    /// PNG, JPEG or WebP, as the server takes them.
    func uploadProjectLogo(_ project: Int64, data: Data, type: String) async -> Result<ProjectInfo, ServerAnswer> {
        let body = HTTPBody(data)
        let payload: Operations.UploadProjectLogo.Input.Body =
            switch type {
            case "image/jpeg": .jpeg(body)
            case "image/webp": .imageWebp(body)
            default: .png(body)
            }
        return await attempt({ try await client.uploadProjectLogo(path: .init(id: project), body: payload) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ProjectInfo(try ok.body.json)
        }
    }

    func resetProjectLogo(_ project: Int64) async -> Result<ProjectInfo, ServerAnswer> {
        await attempt({ try await client.resetProjectLogo(path: .init(id: project)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ProjectInfo(try ok.body.json)
        }
    }

    /// The text a run on the project is given (`GET /projects/{id}/profile/preview`).
    func profilePreview(project: Int64) async -> ProfilePreviewInfo? {
        await read("getProfilePreview") {
            guard case .ok(let ok) = try await client.getProfilePreview(path: .init(id: project)) else { return nil }
            return ProfilePreviewInfo(try ok.body.json)
        }
    }

    /// Issues in each state at each day's end, oldest first (`GET /projects/{id}/cfd`).
    func cumulativeFlow(project: Int64) async -> [CfdPoint]? {
        await read("getProjectCfd") {
            guard case .ok(let ok) = try await client.getProjectCfd(path: .init(id: project)) else { return nil }
            return try ok.body.json.compactMap(CfdPoint.init).sorted { $0.day < $1.day }
        }
    }
}
