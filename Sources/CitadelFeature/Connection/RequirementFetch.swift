import CitadelClient
import Foundation
import OpenAPIRuntime

/// The requirement hub's and the artifacts screen's reads and writes (screens 12, 13).
extension CitadelServer {
    /// A requirement's thread, oldest first, with who a post goes to.
    func thread(requirement: Int64) async -> RequirementThread? {
        await read("getRequirementThread") {
            guard case .ok(let ok) = try await client.getRequirementThread(path: .init(id: requirement)) else {
                return nil
            }
            let thread = try ok.body.json
            return RequirementThread(
                requirementID: thread.requirementId, ownerAgentID: thread.ownerAgentId,
                toQuestionID: thread.toQuestionId,
                items: thread.items.map { item in
                    switch item {
                    case .message(let m): .message(CommentInfo(m.comment), at: m.at)
                    case .question(let q): .question(QuestionInfo(q.question), answer: q.question.answer)
                    case .approval(let a): .approval(ApprovalInfo(a.approval), at: a.at)
                    case .artifact(let a): .artifact(ArtifactInfo(a.artifact))
                    }
                })
        }
    }

    /// Posts in a requirement thread: an answer to `questionID` (routed to its asker, who is woken), or a message
    /// to the owner. Returns the answered question's id, if any.
    func post(requirement: Int64, body: String, questionID: Int64?, toOwner: Bool) async -> Int64?? {
        await read("postToRequirement") {
            guard
                case .ok(let ok) = try await client.postToRequirement(
                    path: .init(id: requirement),
                    body: .json(.init(body: body, questionId: questionID, toOwner: toOwner ? true : nil)))
            else { return nil }
            return .some(try ok.body.json.answered?.id)
        }
    }

    /// The requirement's live plan.
    /// The requirement's live plan, its epics named by their keys (`CIT-E3`, API minor 9) from each project's epics.
    func plan(requirement: Int64) async -> PlanTree? {
        let tree = await read("getRequirementTree") { () -> PlanTree? in
            guard case .ok(let ok) = try await client.getRequirementTree(path: .init(id: requirement)) else {
                return nil
            }
            return PlanTree(try ok.body.json)
        }
        guard var tree else { return nil }
        var keys: [Int64: String] = [:]
        for project in Set(tree.epics.map(\.projectID)) {
            let epics = await read("listEpics") { () -> [Schemas.Epic]? in
                guard case .ok(let ok) = try await client.listEpics(path: .init(id: project)) else { return nil }
                return try ok.body.json
            }
            for epic in epics ?? [] { keys[epic.id] = epic.key }
        }
        for index in tree.epics.indices { tree.epics[index].key = keys[tree.epics[index].id] }
        return tree
    }

    /// A new request for the CEO to route (the list's ＋); the intake issue it became.
    func submitRequest(company: Int64, title: String, body: String) async -> Bool {
        await read("submitRequest") {
            guard
                case .ok = try await client.submitRequest(
                    path: .init(id: company), body: .json(.init(body: body.isEmpty ? nil : body, title: title)))
            else { return false }
            return true
        } ?? false
    }

    /// The company's newest artifacts (up to `limit`).
    func artifacts(limit: Int32 = 200) async -> [ArtifactInfo]? {
        await read("listArtifacts") {
            guard case .ok(let ok) = try await client.listArtifacts(query: .init(limit: limit)) else { return nil }
            return try ok.body.json.items.map(ArtifactInfo.init)
        }
    }

    func artifactUsage(company: Int64) async -> ArtifactUsageInfo? {
        await read("getArtifactUsage") {
            guard case .ok(let ok) = try await client.getArtifactUsage(path: .init(id: company)) else { return nil }
            let usage = try ok.body.json
            return ArtifactUsageInfo(used: usage.usedBytes, quota: usage.quotaBytes, maxFile: usage.maxFileBytes)
        }
    }

    /// The preview bytes: text (its first 64 KiB) or an image; a type with no preview is a 409.
    func artifactPreview(_ id: Int64) async -> Data? {
        await read("previewArtifact") {
            guard case .ok(let ok) = try await client.previewArtifact(path: .init(id: id)) else { return nil }
            guard case .any(let body) = ok.body else { return nil }
            return try await Data(collecting: body, upTo: 16 << 20)
        }
    }

    /// The whole file, for the save panel; never opened or run here.
    func artifactContent(_ id: Int64, upTo limit: Int) async -> Data? {
        await read("downloadArtifact") {
            guard case .ok(let ok) = try await client.downloadArtifact(path: .init(id: id)) else { return nil }
            guard case .any(let body) = ok.body else { return nil }
            return try await Data(collecting: body, upTo: limit)
        }
    }
}

extension PlanTree {
    init(_ tree: Schemas.RequirementTree) {
        func task(_ t: Schemas.TreeTask) -> PlanTask {
            var agent: Int64?
            if case .agent(let a) = t.assignee { agent = a.agentId }
            return PlanTask(
                issueID: t.issueId, key: t.key, title: t.title, points: t.points.map(Int.init), state: t.state.word,
                assigneeAgentID: agent, prs: t.prs, timeSecs: t.timeSecs, tokens: t.tokens, sprintID: t.sprintId)
        }
        let cost = tree.cost
        self.init(
            points: Int(tree.points), donePoints: Int(tree.donePoints), percent: Int(tree.percentDone),
            tasks: Int(tree.tasks), doneTasks: Int(tree.doneTasks), eta: tree.eta, pointsPerDay: tree.pointsPerDay,
            tokens: cost.inputTokens + cost.outputTokens + cost.cacheTokens + cost.subscriptionTokens,
            costMicros: cost.costUsdMicros, burndown: tree.burndown.map { ($0.day, Int($0.left)) },
            epics: tree.epics.map {
                PlanEpic(
                    id: $0.epicId, projectID: $0.projectId, title: $0.title, points: Int($0.points),
                    donePoints: Int($0.donePoints),
                    tasks: $0.tasks.map(task))
            },
            other: tree.other.map(task),
            diff: tree.diff.map { diff in
                PlanDiffInfo(
                    version: Int(diff.version), added: diff.added.map { ($0.key, $0.points.map(Int.init)) },
                    removed: diff.removed.map { ($0.key, $0.points.map(Int.init)) },
                    pointsApproved: Int(diff.pointsApproved), pointsNow: Int(diff.pointsNow))
            },
            intakeIssueID: tree.requirement.intakeIssueId, planVersion: Int(tree.requirement.planVersion))
    }
}

/// Screen 12's "⋯" and 📎 (API minor 7): rename, cancel, and a file into the thread. `nil` = done.
extension CitadelServer {
    func rename(requirement: Int64, title: String) async -> ServerAnswer? {
        await act { try await client.renameRequirement(path: .init(id: requirement), body: .json(.init(title: title))) }
    }

    /// Cancels it and its open issues; refused while a run works on one of them.
    func cancel(requirement: Int64, reason: String?) async -> ServerAnswer? {
        await act {
            try await client.cancelRequirement(path: .init(id: requirement), body: .json(.init(reason: reason)))
        }
    }

    /// The file becomes an artifact of the requirement's thread (a text file is redacted of key shapes first).
    func attach(requirement: Int64, name: String, data: Data) async -> ServerAnswer? {
        await act {
            try await client.attachToRequirement(
                path: .init(id: requirement, name: name), body: .binary(HTTPBody(data)))
        }
    }
}
