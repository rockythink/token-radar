import Foundation

public struct QuotaWindowSummary: Identifiable, Equatable {
    public var id: UUID { window.id }
    public var window: SubscriptionQuotaWindow
    public var periodStart: Date
    public var periodEnd: Date
    public var usedUnits: Decimal
    public var remainingUnits: Decimal
    public var utilization: Decimal
    public var projectedUnits: Decimal
    public var evaluatedAt: Date
    public var providerRemainingRatio: Decimal?
    public var providerResetAt: Date?
    public var providerResetLabel: String
    public var providerReportedAt: Date?

    public var isProviderReported: Bool {
        providerRemainingRatio != nil
    }

    public var remainingRatio: Decimal {
        if let providerRemainingRatio {
            return Self.clampedRatio(providerRemainingRatio)
        }
        guard window.includedUnits > 0 else { return 0 }
        return Self.clampedRatio(remainingUnits / window.includedUnits)
    }

    public var usedRatio: Decimal {
        Self.clampedRatio(Decimal(1) - remainingRatio)
    }

    public var timeElapsedRatio: Decimal {
        let periodSeconds = max(1, periodEnd.timeIntervalSince(periodStart))
        let elapsedSeconds = max(0, min(periodSeconds, evaluatedAt.timeIntervalSince(periodStart)))
        return Self.clampedRatio(Decimal(elapsedSeconds / periodSeconds))
    }

    public var timeRemainingRatio: Decimal {
        Self.clampedRatio(Decimal(1) - timeElapsedRatio)
    }

    public var remainingSeconds: TimeInterval {
        max(0, periodEnd.timeIntervalSince(evaluatedAt))
    }

    public var quotaTimeRatio: Decimal {
        if timeRemainingRatio <= 0 {
            return remainingRatio > 0 ? Decimal(99) : Decimal(0)
        }
        return remainingRatio / timeRemainingRatio
    }

    public var quotaTimeBalance: Decimal {
        remainingRatio - timeRemainingRatio
    }

    public init(
        window: SubscriptionQuotaWindow,
        periodStart: Date,
        periodEnd: Date,
        usedUnits: Decimal,
        remainingUnits: Decimal,
        utilization: Decimal,
        projectedUnits: Decimal,
        evaluatedAt: Date = Date(),
        providerRemainingRatio: Decimal? = nil,
        providerResetAt: Date? = nil,
        providerResetLabel: String = "",
        providerReportedAt: Date? = nil
    ) {
        self.window = window
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.usedUnits = usedUnits
        self.remainingUnits = remainingUnits
        self.utilization = utilization
        self.projectedUnits = projectedUnits
        self.evaluatedAt = evaluatedAt
        self.providerRemainingRatio = providerRemainingRatio.map(Self.clampedRatio)
        self.providerResetAt = providerResetAt
        self.providerResetLabel = providerResetLabel
        self.providerReportedAt = providerReportedAt
    }

    private static func clampedRatio(_ ratio: Decimal) -> Decimal {
        min(Decimal(1), max(Decimal(0), ratio))
    }
}

public enum QuotaWindowCalculator {
    public static func summarizeAll(
        windows: [SubscriptionQuotaWindow],
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [QuotaWindowSummary] {
        windows
            .filter(\.isEnabled)
            .map { summarize(window: $0, records: records, now: now, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.utilization == rhs.utilization {
                    return lhs.periodEnd < rhs.periodEnd
                }
                return lhs.utilization > rhs.utilization
            }
    }

    public static func summarize(
        window: SubscriptionQuotaWindow,
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuotaWindowSummary {
        let defaultPeriod = quotaPeriod(for: window, now: now, calendar: calendar)
        let period = providerReportedPeriod(for: window, defaultPeriod: defaultPeriod, now: now, calendar: calendar)
        if let providerRemainingRatio = window.providerRemainingRatio {
            let remainingRatio = min(Decimal(1), max(Decimal(0), providerRemainingRatio))
            let usedRatio = Decimal(1) - remainingRatio
            let displayUnits = window.includedUnits > 0 ? window.includedUnits : Decimal(100)

            return QuotaWindowSummary(
                window: window,
                periodStart: period.start,
                periodEnd: period.end,
                usedUnits: displayUnits * usedRatio,
                remainingUnits: displayUnits * remainingRatio,
                utilization: usedRatio,
                projectedUnits: displayUnits * usedRatio,
                evaluatedAt: now,
                providerRemainingRatio: remainingRatio,
                providerResetAt: window.providerResetAt,
                providerResetLabel: window.providerResetLabel,
                providerReportedAt: window.providerReportedAt
            )
        }

        let matchedRecords = records.filter { record in
            record.timestamp >= period.start && record.timestamp < period.end
        }
        let usedUnits = matchedRecords.reduce(Decimal(0)) { partial, record in
            partial + units(for: record, unit: window.quotaUnit)
        }
        let remainingUnits = max(0, window.includedUnits - usedUnits)
        let utilization = window.includedUnits > 0 ? min(1, usedUnits / window.includedUnits) : 0
        let elapsedSeconds = max(1, now.timeIntervalSince(period.start))
        let periodSeconds = max(1, period.end.timeIntervalSince(period.start))
        let elapsedRatio = Decimal(elapsedSeconds / periodSeconds)
        let projectedUnits = elapsedRatio > 0 ? usedUnits / elapsedRatio : usedUnits

        return QuotaWindowSummary(
            window: window,
            periodStart: period.start,
            periodEnd: period.end,
            usedUnits: usedUnits,
            remainingUnits: remainingUnits,
            utilization: utilization,
            projectedUnits: projectedUnits,
            evaluatedAt: now
        )
    }

    public static func quotaPeriod(
        for window: SubscriptionQuotaWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        switch window.kind {
        case .fiveHours:
            anchoredHourPeriod(hours: 5, now: now, calendar: calendar)
        case .daily:
            dailyPeriod(now: now, calendar: calendar)
        case .weekly:
            weeklyPeriod(now: now, calendar: calendar)
        case .monthly:
            monthlyPeriod(now: now, calendar: calendar)
        case .customHours:
            anchoredHourPeriod(hours: window.customHours, now: now, calendar: calendar)
        }
    }

    public static func units(for record: UsageRecord, unit: SubscriptionQuotaUnit) -> Decimal {
        switch unit {
        case .messages, .requests:
            1
        case .tokens:
            Decimal(record.totalTokens)
        case .usd:
            record.costUSD
        }
    }

    private static func dailyPeriod(
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return (start, end)
    }

    private static func weeklyPeriod(
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            return (interval.start, interval.end)
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        return (start, end)
    }

    private static func monthlyPeriod(
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let start = DateRanges.startOfMonth(containing: now, calendar: calendar)
        let end = DateRanges.endOfMonth(containing: now, calendar: calendar)
        return (start, end)
    }

    private static func anchoredHourPeriod(
        hours: Int,
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let clampedHours = min(24 * 31, max(1, hours))
        let anchor = calendar.startOfDay(for: now)
        let elapsedSeconds = max(0, now.timeIntervalSince(anchor))
        let windowSeconds = TimeInterval(clampedHours * 60 * 60)
        let index = floor(elapsedSeconds / windowSeconds)
        let start = anchor.addingTimeInterval(index * windowSeconds)
        let end = start.addingTimeInterval(windowSeconds)
        return (start, end)
    }

    private static func providerReportedPeriod(
        for window: SubscriptionQuotaWindow,
        defaultPeriod: (start: Date, end: Date),
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        guard let resetAt = window.providerResetAt, resetAt > now else {
            return defaultPeriod
        }

        let start: Date?
        switch window.kind {
        case .fiveHours:
            start = resetAt.addingTimeInterval(-5 * 60 * 60)
        case .daily:
            start = calendar.date(byAdding: .day, value: -1, to: resetAt)
        case .weekly:
            start = calendar.date(byAdding: .day, value: -7, to: resetAt)
        case .monthly:
            start = calendar.date(byAdding: .month, value: -1, to: resetAt)
        case .customHours:
            let hours = min(24 * 31, max(1, window.customHours))
            start = resetAt.addingTimeInterval(TimeInterval(-hours * 60 * 60))
        }

        guard let start, start < resetAt else {
            return defaultPeriod
        }

        return (start, resetAt)
    }
}
