import AppKit
import CitadelClient
import Foundation
import Observation

extension Schemas.ArtifactKind: OpenWord {}

/// Screen 13 Artifacts: the company's published files and the open preview.
@MainActor
@Observable
final class ArtifactsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
    /// Newest first (`GET /artifacts`).
    var items: [ArtifactInfo] = []
    var usage: ArtifactUsageInfo?
    var filter = ArtifactFilter()
    var selectedID: Int64?
    var isGrid = true
    /// Fetched previews: text (first 64 KiB, as the server cut it) or an image.
    var texts: [Int64: String] = [:]
    var images: [Int64: NSImage] = [:]
}

/// A file an agent published (`publish_artifact`).
struct ArtifactInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    /// `report`, `file`, `screenshot`, `other`.
    var kind: String
    var mime: String
    var size: Int64
    /// `text`, `image` or `none` (download it).
    var preview: String
    var sha256: String
    var agentID: Int64?
    var issueID: Int64?
    var requirementID: Int64?
    var runID: Int64?
    var createdAt: Date
    /// Secrets redacted before it was stored.
    var redactions: Int64

    /// The name's extension, lowercased: `md`, `png`, `log`.
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var isMarkdown: Bool { ext == "md" || ext == "markdown" || mime == "text/markdown" }
    var isImage: Bool { preview == "image" }
    var isText: Bool { preview == "text" }

    /// The tag over the card's corner: "report · md", "png · 1440×900", "log · 84 KB".
    func typeLabel(imageSize: CGSize? = nil) -> String {
        if isImage, let size = imageSize { return "\(ext) · \(Int(size.width))×\(Int(size.height))" }
        if kind == "report" || isMarkdown { return "\(kind == "file" ? "doc" : kind) · \(ext)" }
        return "\(ext.isEmpty ? kind : ext) · \(ScopedSetting.bytes(size))"
    }

    /// A name safe to suggest in a save panel: no directories, no hidden file, no control characters.
    var safeFileName: String { Self.safeFileName(name, id: id) }

    static func safeFileName(_ name: String, id: Int64) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        var clean = String(String.UnicodeScalarView(name.unicodeScalars.map { unsafe.contains($0) ? "_" : $0 }))
        while clean.hasPrefix(".") || clean.hasPrefix(" ") { clean.removeFirst() }
        clean = String(clean.prefix(200)).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty || clean.allSatisfy({ $0 == "_" }) ? "artifact-\(id)" : clean
    }
}

struct ArtifactUsageInfo: Equatable, Sendable {
    var used: Int64
    var quota: Int64
    var maxFile: Int64
}

/// The filter row: requirement (set from a requirement's ▤ button), type, agent, issue.
struct ArtifactFilter: Equatable {
    var requirementID: Int64?
    var kind: String?
    var agentID: Int64?
    var issueID: Int64?

    /// `requirementOf` names an artifact's issue's requirement: a screenshot published on CIT-61 belongs to R-12.
    func matches(_ artifact: ArtifactInfo, requirementOf: (Int64?) -> Int64? = { _ in nil }) -> Bool {
        let requirement = artifact.requirementID ?? requirementOf(artifact.issueID)
        return (requirementID == nil || requirement == requirementID) && (kind == nil || artifact.kind == kind)
            && (agentID == nil || artifact.agentID == agentID) && (issueID == nil || artifact.issueID == issueID)
    }
}

/// A day group of the grid: "Today", "Earlier this week", "Older".
struct ArtifactGroup: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var items: [ArtifactInfo]

    static func groups(
        _ items: [ArtifactInfo], now: Date, calendar: Calendar = .current
    ) -> [ArtifactGroup] {
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var groups: [ArtifactGroup] = []
        for item in items.sorted(by: { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }) {
            let title =
                item.createdAt >= today ? "Today" : item.createdAt >= weekAgo ? "Earlier this week" : "Older"
            if groups.last?.title == title {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(ArtifactGroup(title: title, items: [item]))
            }
        }
        return groups
    }
}

extension ArtifactInfo {
    init(_ artifact: Schemas.Artifact) {
        self.init(
            id: artifact.id, name: artifact.name, kind: artifact.kind.word, mime: artifact.mime, size: artifact.size,
            preview: artifact.preview, sha256: artifact.sha256, agentID: artifact.agentId, issueID: artifact.issueId,
            requirementID: artifact.requirementId, runID: artifact.runId, createdAt: artifact.createdAt,
            redactions: artifact.redactions)
    }
}

extension CompanyModel {
    /// The artifacts the filter keeps, newest first.
    var filteredArtifacts: [ArtifactInfo] {
        artifactsPage.items.filter { artifactsPage.filter.matches($0, requirementOf: { issue($0)?.requirementID }) }
    }

    /// "31 in Ainkrad · 4 today · 212 MB of 2 GB".
    func artifactsCrumb(company: String, now: Date) -> String {
        let today = Calendar.current.startOfDay(for: now)
        var parts = [
            "\(artifactsPage.items.count) in \(company)",
            "\(artifactsPage.items.filter { $0.createdAt >= today }.count) today",
        ]
        if let usage = artifactsPage.usage {
            parts.append("\(ScopedSetting.bytes(usage.used)) of \(ScopedSetting.bytes(usage.quota))")
        }
        return parts.joined(separator: " · ")
    }

    /// "R-12", "CIT-61" — the keys an artifact belongs to, issue first.
    func references(_ artifact: ArtifactInfo) -> [String] {
        var keys: [String] = []
        if let issue = issue(artifact.issueID) { keys.append(issue.key) }
        if let id = artifact.requirementID, let requirement = requirements.first(where: { $0.id == id }) {
            keys.append(requirement.key)
        }
        return keys
    }
}
