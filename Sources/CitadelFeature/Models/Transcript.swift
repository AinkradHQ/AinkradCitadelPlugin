import AinkradAppKit
import Foundation

/// One tool call of a run, as `AinkradToolCard` draws it.
struct ToolCallItem: Equatable {
    let id: String
    let name: String
    let argument: String
    var status: AinkradToolCardStatus
    var result: AinkradToolCardResult
    /// An edit's before and after, for the diff body.
    var edit: Edit?
    /// Secrets the server's redactor caught in the call, by name.
    var secrets: [String]
    var footnote: String?

    struct Edit: Equatable {
        let path: String
        let old: String
        let new: String
    }
}

/// A run's transcript in the screens' terms: assistant text, tool cards, system lines (provider drops,
/// fallbacks), in the order they happened.
enum TranscriptItem: Identifiable, Equatable {
    case text(id: String, text: String, secrets: [String])
    case tool(ToolCallItem)
    case note(id: String, text: String)

    var id: String {
        switch self {
        case .text(let id, _, _), .note(let id, _): id
        case .tool(let call): call.id
        }
    }
}

enum Transcript {
    /// Folds a run's chunks (and its system lines) into items. A tool call runs until anything else the
    /// harness says follows it; it then counts as done (the transcript carries no tool results yet). A call
    /// the pending approval `waitingRequest` asks about waits, amber; a run that ended `failed` fails the call
    /// it was in.
    static func items(
        _ chunks: [TranscriptChunkInfo], notes: [RunNote] = [], runState: String, waitingRequest: String? = nil
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var open: Int?

        func close(_ status: AinkradToolCardStatus = .succeeded) {
            guard let index = open, case .tool(var call) = items[index], call.status == .running else { return }
            call.status = status
            items[index] = .tool(call)
            open = nil
        }

        let timeline =
            chunks.map { (at: $0.at, chunk: Optional($0), note: RunNote?.none) }
            + notes.map { (at: $0.at, chunk: TranscriptChunkInfo?.none, note: Optional($0)) }
        for entry in timeline.sorted(by: { $0.at < $1.at }) {
            if let note = entry.note {
                items.append(.note(id: "note-\(note.at.timeIntervalSince1970)-\(note.action)", text: note.text))
                continue
            }
            guard let chunk = entry.chunk else { continue }
            let f = chunk.fields
            switch chunk.kind {
            case "assistant_text":
                close()
                let text = f["text"] ?? ""
                if case .text(let id, let previous, let secrets)? = items.last {
                    items[items.count - 1] = .text(
                        id: id, text: previous + "\n\n" + text, secrets: secrets + Redaction.names(in: text))
                } else {
                    items.append(.text(id: "text-\(chunk.seq)", text: text, secrets: Redaction.names(in: text)))
                }
            case "tool_use":
                close()
                items.append(.tool(toolCall(chunk)))
                open = items.count - 1
            case "approval_requested":
                guard let request = f["id"], request == waitingRequest else { continue }
                let tool = f["tool"] ?? ""
                if let index = open, case .tool(var call) = items[index], call.name == tool {
                    call.status = .waiting
                    items[index] = .tool(call)
                } else {
                    close()
                    var call = toolCall(chunk, name: tool)
                    call.status = .waiting
                    items.append(.tool(call))
                    open = items.count - 1
                }
            case "turn_ended", "exited":
                close()
            default:
                continue
            }
        }
        if !["queued", "claimed", "running"].contains(runState) {
            close(runState == "succeeded" ? .succeeded : runState == "failed" ? .failed : .succeeded)
        }
        return items
    }

    private static func toolCall(_ chunk: TranscriptChunkInfo, name: String? = nil) -> ToolCallItem {
        let f = chunk.fields
        let name = name ?? f["name"] ?? "Tool"
        let argument = ToolLine.argument(f)
        var edit: ToolCallItem.Edit?
        var result: AinkradToolCardResult = .none
        if let old = f["input.old_string"], let new = f["input.new_string"] {
            let path = f["input.file_path"] ?? argument
            edit = ToolCallItem.Edit(path: path, old: old, new: new)
            let lines = AinkradDiffEngine.compute(old: old, new: new, path: path, context: 0).hunks.flatMap(\.lines)
            result = .counts(
                added: lines.filter { $0.kind == .insertion }.count,
                removed: lines.filter { $0.kind == .deletion }.count)
        }
        let secrets = f.filter { $0.key.hasPrefix("input.") }.values.flatMap(Redaction.names)
        if !secrets.isEmpty, case .none = result {
            result = .summary("\(secrets.count) secret\(secrets.count == 1 ? "" : "s") redacted")
        }
        return ToolCallItem(
            id: "tool-\(chunk.seq)", name: name, argument: Redaction.masked(argument), status: .running,
            result: result, edit: edit, secrets: secrets, footnote: nil)
    }
}

/// The server's redactor writes `[redacted:<name>]` where a secret was (Citadel `proto::redact`).
enum Redaction {
    static func names(in text: String) -> [String] {
        text.matches(of: /\[redacted:([^\]]+)\]/).map { String($0.output.1) }
    }

    /// The text with each marker as `🔒name`, for one-line places (a tool's argument).
    static func masked(_ text: String) -> String {
        text.replacing(/\[redacted:([^\]]+)\]/) { "🔒\($0.output.1)" }
    }
}
