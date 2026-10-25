import AinkradAppKit
import AppKit
import CitadelClient
import Foundation

/// The New company wizard (prototype `company.js`): open it fresh, load what it picks from, create.
extension CitadelStore {
    func openNewCompany() {
        newCompany = NewCompanySession()
        isSwitchingCompany = false
        isCreatingCompany = true
        loadNewCompanyChoices()
    }

    /// The whole pool (accounts to assign) and every runner (tag counts); a failed read leaves the lists empty.
    func loadNewCompanyChoices() {
        guard let server else { return }
        Task {
            if let pool = await server.poolUsage() { newCompany.pool = pool }
            if let runners = await server.runnerList() { newCompany.runners = runners }
        }
    }

    /// Creates the company, then its logo, accounts, budget and CEO proposal — one call each, so not atomic: a
    /// later failure keeps the company and a toast names what did not happen. Then closes and switches to it.
    func createCompany() {
        let draft = newCompany.draft
        guard draft.hasName, !newCompany.isCreating, let server else { return }
        newCompany.isCreating = true
        let extended = serverSupports(minor: Self.structureMinor)
        Task {
            var body = Schemas.NewCompany(
                kind: .init(value1: draft.kind == "own" ? .own : .client), name: draft.cleanName)
            if extended {
                body.color = draft.colour
                body.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
                body.industries = draft.industries.sorted()
                body.website = draft.website.trimmingCharacters(in: .whitespaces)
            }
            let created: Schemas.Company
            switch await server.createCompany(body) {
            case .success(let company): created = company
            case .failure(let answer):
                newCompany.isCreating = false
                actionFailure = ActionFailure(
                    title: "Couldn't create \(draft.cleanName)", answer: answer, outcome: "Nothing was created.")
                return
            }
            actionFailure = nil
            let missed = await finishCompany(created, draft: draft, extended: extended, server: server)
            companies.append(created)
            if let data = draft.logo, let image = NSImage(data: data), !missed.contains("its logo") {
                logos.images[created.id] = image
            }
            isCreatingCompany = false
            newCompany = NewCompanySession()
            select(company: created.id, announce: false)
            if missed.isEmpty {
                toast(
                    AinkradRichToast(
                        title: "\(created.name) created",
                        body:
                            "\(draft.ceoName) (CEO · \(draft.modelName)) is waiting for your first requirement.",
                        status: .success))
            } else {
                toast(
                    AinkradRichToast(
                        title: "\(created.name) created, but \(missed.formatted(.list(type: .and))) didn't go through",
                        body: "The company is kept — add them from its settings.", status: .warning))
            }
        }
    }

    /// Every follow-up the company needs; the names of those the server refused.
    private func finishCompany(
        _ company: Schemas.Company, draft: NewCompanyDraft, extended: Bool, server: CitadelServer
    ) async -> [String] {
        let scoped = server.scoped(to: company.id)
        var missed: [String] = []
        if let logo = draft.logo, extended, let type = draft.logoType,
            await scoped.uploadLogo(company: company.id, data: logo, type: type) != nil
        {
            missed.append("its logo")
        }
        for account in draft.accounts.sorted() {
            if await scoped.setAccount(account, assigned: true, company: company.id) != nil {
                let label = newCompany.pool.first { $0.id == account }?.label ?? "account \(account)"
                missed.append("the \(label) account")
            }
        }
        if await scoped.createBudget(
            company: company.id, scope: "company:\(company.id)", period: "month", cap: draft.budgetTokens,
            warnPercent: 80) != nil
        {
            missed.append("its \(Fmt.tokens(draft.budgetTokens)) token budget")
        }
        if case .failure = await scoped.proposeAgent(company: company.id, draft.proposal(extended: extended)) {
            missed.append("the CEO \(draft.ceoName)")
        }
        return missed
    }
}
