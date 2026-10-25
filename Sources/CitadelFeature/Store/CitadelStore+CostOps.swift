import AinkradAppKit
import Foundation

/// Cost (prototype `cost.js`): the inline budget edits with their toasts and Undo, and the toasts after a price,
/// a new budget and an export.
extension CitadelStore {
    /// A budget card's cap pill, in the budget's own unit (dollars when it has a dollar cap): refused input toasts
    /// and changes nothing; a change can be undone.
    func editBudgetCap(_ budget: BudgetInfo, text: String, inheritsWarn: Bool) {
        guard case .success(let edit) = BudgetEdit.parse(cap: text, warn: "", unit: budget.unit) else {
            toast(
                AinkradRichToast(
                    title: budget.isDollars ? "The cap is a dollar amount" : "The cap is a token count",
                    body: "“\(text)” was refused · \(budget.isDollars ? "$900, 1.5k" : "2M, 900k")", status: .danger))
            return
        }
        let warn = inheritsWarn ? nil : budget.warnPercent
        let cap = budget.isDollars ? budget.cap : edit.cap
        let usd = budget.isDollars ? edit.usdCap : budget.usdCap
        setBudget(budget, cap: cap, usdCap: usd, warnPercent: warn)
        let shown = budget.isDollars ? edit.usdCap ?? 0 : edit.cap
        toast(
            AinkradRichToast(
                title: "\(budget.label) cap → \(budget.word(shown))\(budget.isDollars ? "" : " tok")",
                body: shown > budget.shownSpent ? "New runs allowed again." : "Still at the cap.", status: .success,
                actions: [
                    AinkradRichToastAction("Undo") { [weak self] in
                        self?.setBudget(budget, cap: budget.cap, usdCap: budget.usdCap, warnPercent: warn)
                    }
                ]))
    }

    /// A budget card's warn pill: 50–99 or refused (never clamped); `nil` (↺) inherits again.
    func editBudgetWarn(_ budget: BudgetInfo, text: String?, inherited: Int) {
        guard let text else {
            setBudget(budget, cap: budget.cap, warnPercent: nil)
            toast(AinkradRichToast(title: "\(budget.label) warn reset", body: "Inherits \(inherited)%"))
            return
        }
        guard case .success(let edit) = BudgetEdit.parse(cap: "\(budget.cap)", warn: text),
            let percent = edit.warnPercent
        else {
            toast(
                AinkradRichToast(
                    title: "Warn % must be 50–99", body: "“\(text)” was refused · bounds come from the server setting",
                    status: .danger))
            return
        }
        setBudget(budget, cap: budget.cap, warnPercent: percent == inherited ? nil : percent)
        toast(
            AinkradRichToast(
                title: "\(budget.label) warns at \(percent)%",
                body: percent == inherited ? "Inherited again" : "Set on this budget · ↺ resets", status: .success))
    }

    /// Save price in the drawer: priced from now on, or past runs too (API minor 18).
    func savePrice(_ price: PriceDraft, pastToo: Bool = false) {
        setPrice(price, pastToo: pastToo)
        toast(
            AinkradRichToast(
                title: "\(price.model) priced",
                body: pastToo && serverSupports(minor: Self.trancheBMinor)
                    ? "Past runs are re-costed too · audited" : "Runs from now on count in dollars · audited",
                status: .success))
    }

    /// Create budget in the drawer: a token cap, or a dollar cap (`usdCap`, millionths) with no tokens.
    func addBudget(scope: String, label: String, period: String, cap: Int64, usdCap: Int64? = nil) {
        createBudget(scope: scope, label: label, period: period, cap: cap, usdCap: usdCap, warnPercent: nil)
        toast(AinkradRichToast(title: "Budget created", body: "Counts from the start of the period.", status: .success))
    }

    /// The approval a stopped budget waits on (`budget_overrun` for its scope), else any budget approval.
    func openBudgetApproval(_ budget: BudgetInfo) {
        let approvals = model?.approvals.filter { $0.kind == "budget_overrun" } ?? []
        selectedApproval = (approvals.first { $0.fields["scope"] == budget.scope } ?? approvals.first)?.id
        screen = .approvals
    }
}
