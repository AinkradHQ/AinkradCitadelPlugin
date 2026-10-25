import AinkradAppKit
import Foundation

/// Cost (prototype `cost.js`): the inline budget edits with their toasts and Undo, and the toasts after a price,
/// a new budget and an export.
extension CitadelStore {
    /// A budget card's cap pill: refused input toasts and changes nothing; a change can be undone.
    func editBudgetCap(_ budget: BudgetInfo, text: String, inheritsWarn: Bool) {
        guard case .success(let edit) = BudgetEdit.parse(cap: text, warn: "") else {
            toast(
                AinkradRichToast(
                    title: "The cap is a token count", body: "“\(text)” was refused · 2M, 900k", status: .danger))
            return
        }
        let warn = inheritsWarn ? nil : budget.warnPercent
        setBudget(budget, cap: edit.cap, warnPercent: warn)
        toast(
            AinkradRichToast(
                title: "\(budget.label) cap → \(Fmt.tokens(edit.cap)) tok",
                body: edit.cap > budget.spent ? "New runs allowed again." : "Still at the cap.", status: .success,
                actions: [
                    AinkradRichToastAction("Undo") { [weak self] in
                        self?.setBudget(budget, cap: budget.cap, warnPercent: warn)
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

    /// Save price in the drawer: priced from now on (re-pricing past runs needs the server).
    func savePrice(_ price: PriceDraft) {
        setPrice(price)
        toast(
            AinkradRichToast(
                title: "\(price.model) priced", body: "Runs from now on count in dollars · audited", status: .success))
    }

    /// Create budget in the drawer.
    func addBudget(scope: String, label: String, period: String, cap: Int64) {
        createBudget(scope: scope, label: label, period: period, cap: cap, warnPercent: nil)
        toast(AinkradRichToast(title: "Budget created", body: "Counts from the start of the period.", status: .success))
    }

    /// The approval a stopped budget waits on (`budget_overrun` for its scope), else any budget approval.
    func openBudgetApproval(_ budget: BudgetInfo) {
        let approvals = model?.approvals.filter { $0.kind == "budget_overrun" } ?? []
        selectedApproval = (approvals.first { $0.fields["scope"] == budget.scope } ?? approvals.first)?.id
        screen = .approvals
    }
}
