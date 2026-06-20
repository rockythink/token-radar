import Foundation

public enum SubscriptionCalculator {
    public static func summarize(
        plan: SubscriptionPlan,
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SubscriptionSummary {
        let period = billingPeriod(resetDay: plan.resetDay, now: now, calendar: calendar)
        let matchedRecords = records.filter { record in
            record.timestamp >= period.start &&
            record.timestamp < period.end &&
            matches(plan: plan, record: record)
        }

        let usedUnits = matchedRecords.reduce(Decimal(0)) { partial, record in
            partial + QuotaWindowCalculator.units(for: record, unit: plan.quotaUnit)
        }
        let remaining = max(0, plan.includedUnits - usedUnits)
        let utilization = plan.includedUnits > 0 ? min(1, usedUnits / plan.includedUnits) : 0

        let elapsedSeconds = max(1, now.timeIntervalSince(period.start))
        let periodSeconds = max(1, period.end.timeIntervalSince(period.start))
        let elapsedRatio = Decimal(elapsedSeconds / periodSeconds)
        let projectedUnits = elapsedRatio > 0 ? usedUnits / elapsedRatio : usedUnits
        let amortized = plan.monthlyFeeUSD * min(1, max(0, elapsedRatio))
        let effectiveUnitCost = usedUnits > 0 ? plan.monthlyFeeUSD / usedUnits : nil
        let overageUnits = max(0, projectedUnits - plan.includedUnits)
        let overageCost = overageUnits * (plan.overageUnitPriceUSD ?? 0)

        return SubscriptionSummary(
            plan: plan,
            periodStart: period.start,
            periodEnd: period.end,
            usedUnits: usedUnits,
            remainingUnits: remaining,
            utilization: utilization,
            projectedUnits: projectedUnits,
            amortizedCostToDateUSD: amortized,
            effectiveUnitCostUSD: effectiveUnitCost,
            projectedOverageUnits: overageUnits,
            projectedOverageCostUSD: overageCost
        )
    }

    public static func summarizeAll(
        plans: [SubscriptionPlan],
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SubscriptionSummary] {
        plans
            .filter(\.isEnabled)
            .map { summarize(plan: $0, records: records, now: now, calendar: calendar) }
            .sorted { $0.utilization > $1.utilization }
    }

    public static func billingPeriod(
        resetDay: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let day = min(28, max(1, resetDay))
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let currentMonthStart = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)) ?? DateRanges.startOfMonth(containing: now, calendar: calendar)
        let start: Date
        if now >= currentMonthStart {
            start = currentMonthStart
        } else {
            start = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
        }
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? DateRanges.endOfMonth(containing: now, calendar: calendar)
        return (start, end)
    }

    private static func matches(plan: SubscriptionPlan, record: UsageRecord) -> Bool {
        if let provider = plan.provider, record.provider != provider {
            return false
        }
        let pattern = plan.modelPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return true
        }
        return record.model.lowercased().contains(pattern.lowercased())
    }

}
