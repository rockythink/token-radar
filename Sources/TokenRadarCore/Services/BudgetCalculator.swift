import Foundation

public enum BudgetCalculator {
    public static func summarize(
        records: [UsageRecord],
        monthlyBudgetUSD: Decimal,
        thresholds: [Decimal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetSummary {
        let todayStart = DateRanges.startOfDay(containing: now, calendar: calendar)
        let monthStart = DateRanges.startOfMonth(containing: now, calendar: calendar)

        let todaySpend = records
            .filter { $0.timestamp >= todayStart && $0.timestamp <= now }
            .reduce(Decimal(0)) { $0 + $1.costUSD }

        let monthSpend = records
            .filter { $0.timestamp >= monthStart && $0.timestamp <= now }
            .reduce(Decimal(0)) { $0 + $1.costUSD }

        let remaining = max(0, monthlyBudgetUSD - monthSpend)
        let elapsedDays = Decimal(DateRanges.daysElapsedInMonth(containing: now, calendar: calendar))
        let daysInMonth = Decimal(DateRanges.daysInMonth(containing: now, calendar: calendar))
        let burnRate = elapsedDays > 0 ? monthSpend / elapsedDays : monthSpend
        let projected = burnRate * daysInMonth

        let alert = buildAlert(
            monthSpend: monthSpend,
            monthlyBudget: monthlyBudgetUSD,
            projected: projected,
            thresholds: thresholds
        )

        return BudgetSummary(
            todaySpendUSD: todaySpend,
            monthSpendUSD: monthSpend,
            monthlyBudgetUSD: monthlyBudgetUSD,
            remainingBudgetUSD: remaining,
            burnRatePerDayUSD: burnRate,
            projectedMonthEndUSD: projected,
            alert: alert
        )
    }

    public static func providerSummaries(
        records: [UsageRecord],
        budgets: [ProviderKind: Decimal],
        thresholds: [Decimal],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProviderKind: BudgetSummary] {
        Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { provider in
            let providerRecords = records.filter { $0.provider == provider }
            let budget = budgets[provider] ?? 0
            let summary = summarize(
                records: providerRecords,
                monthlyBudgetUSD: budget,
                thresholds: thresholds,
                now: now,
                calendar: calendar
            )
            return (provider, summary)
        })
    }

    private static func buildAlert(
        monthSpend: Decimal,
        monthlyBudget: Decimal,
        projected: Decimal,
        thresholds: [Decimal]
    ) -> BudgetAlert? {
        guard monthlyBudget > 0 else {
            return BudgetAlert(severity: .info, message: "Set a monthly budget to enable alerts.")
        }

        if monthSpend >= monthlyBudget {
            return BudgetAlert(severity: .critical, message: "Monthly budget is exhausted.")
        }

        if projected > monthlyBudget {
            return BudgetAlert(severity: .warning, message: "Current burn rate is projected to exceed budget.")
        }

        let usedRatio = monthSpend / monthlyBudget
        let crossed = thresholds.sorted(by: >).first { usedRatio >= $0 }
        if let crossed {
            let severity: BudgetAlert.Severity = crossed >= Decimal(string: "0.95")! ? .critical : .warning
            return BudgetAlert(severity: severity, message: "Usage crossed \(MoneyFormatter.percent(crossed)) of monthly budget.")
        }

        return nil
    }
}

