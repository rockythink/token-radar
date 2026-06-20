import Foundation

public struct BudgetSummary: Equatable {
    public var todaySpendUSD: Decimal
    public var monthSpendUSD: Decimal
    public var monthlyBudgetUSD: Decimal
    public var remainingBudgetUSD: Decimal
    public var burnRatePerDayUSD: Decimal
    public var projectedMonthEndUSD: Decimal
    public var alert: BudgetAlert?

    public init(
        todaySpendUSD: Decimal,
        monthSpendUSD: Decimal,
        monthlyBudgetUSD: Decimal,
        remainingBudgetUSD: Decimal,
        burnRatePerDayUSD: Decimal,
        projectedMonthEndUSD: Decimal,
        alert: BudgetAlert?
    ) {
        self.todaySpendUSD = todaySpendUSD
        self.monthSpendUSD = monthSpendUSD
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.remainingBudgetUSD = remainingBudgetUSD
        self.burnRatePerDayUSD = burnRatePerDayUSD
        self.projectedMonthEndUSD = projectedMonthEndUSD
        self.alert = alert
    }

    public var remainingRatio: Decimal {
        guard monthlyBudgetUSD > 0 else { return 1 }
        return max(0, remainingBudgetUSD / monthlyBudgetUSD)
    }
}

public struct BudgetAlert: Identifiable, Equatable {
    public enum Severity: String {
        case info
        case warning
        case critical
    }

    public var id: String { "\(severity.rawValue)-\(message)" }
    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

