import Foundation
import TokenRadarCore

enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case today
    case last7Days
    case last30Days
    case thisMonth
    case all

    var id: String { rawValue }

    func startDate(now: Date = Date(), calendar: Calendar = .current, records: [UsageRecord] = []) -> Date? {
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .thisMonth:
            return DateRanges.startOfMonth(containing: now, calendar: calendar)
        case .all:
            return records.map(\.timestamp).min().map { calendar.startOfDay(for: $0) }
        }
    }
}

enum DashboardMetricMode: String, CaseIterable, Identifiable {
    case spend
    case tokens

    var id: String { rawValue }
}

struct DashboardFilter: Equatable {
    var timeRange: DashboardTimeRange = .thisMonth
    var provider: ProviderKind?
    var source: UsageSource?
    var metricMode: DashboardMetricMode = .tokens
    var searchText: String = ""
}

struct DashboardAnalyticsKey: Equatable {
    var recordsVersion: Int
    var filter: DashboardFilter
}

struct DashboardDailyPoint: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var spend: Decimal
    var tokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var records: Int
}

struct DashboardBreakdownRow: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var spend: Decimal
    var tokens: Int
    var count: Int
    var ratio: Decimal
    var lastSeen: Date?
}

struct DashboardKPIs: Equatable {
    var spend: Decimal
    var tokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var requestCount: Int
    var averageTokensPerRequest: Int
    var activeDays: Int
    var peakDayTokens: Int
    var providerCount: Int
    var cacheRatio: Decimal
}

struct DashboardAnalytics: Equatable {
    var filter: DashboardFilter
    var records: [UsageRecord]
    var daily: [DashboardDailyPoint]
    var providerRows: [DashboardBreakdownRow]
    var sourceRows: [DashboardBreakdownRow]
    var modelRows: [DashboardBreakdownRow]
    var projectRows: [DashboardBreakdownRow]
    var recentRecords: [UsageRecord]
    var kpis: DashboardKPIs

    static let empty = DashboardAnalytics(records: [], filter: DashboardFilter())

    init(records allRecords: [UsageRecord], filter: DashboardFilter, now: Date = Date(), calendar: Calendar = .current) {
        self.filter = filter
        let start = filter.timeRange.startDate(now: now, calendar: calendar, records: allRecords)
        let normalizedSearch = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = allRecords.filter { record in
            if let start, record.timestamp < start { return false }
            if let provider = filter.provider, record.provider != provider { return false }
            if let source = filter.source, record.source != source { return false }
            if !normalizedSearch.isEmpty {
                let fields = [
                    record.model,
                    record.provider.displayName,
                    record.project ?? "",
                    record.apiKeyLabel ?? "",
                    record.source.rawValue
                ].joined(separator: " ").lowercased()
                return fields.contains(normalizedSearch)
            }
            return true
        }
        .sorted { $0.timestamp > $1.timestamp }

        records = filtered
        daily = Self.makeDaily(records: filtered, start: start, now: now, calendar: calendar)
        providerRows = Self.breakdown(records: filtered, group: { $0.provider.rawValue }) { records in
            let first = records[0]
            return (first.provider.displayName, "\(records.count)")
        }
        sourceRows = Self.breakdown(records: filtered, group: { $0.source.rawValue }) { records in
            let first = records[0]
            return (first.source.rawValue, "\(records.count)")
        }
        modelRows = Self.breakdown(records: filtered, group: { "\($0.provider.rawValue)|\($0.model)" }) { records in
            let first = records[0]
            return (first.model, first.provider.displayName)
        }
        projectRows = Self.breakdown(records: filtered, group: {
            let project = $0.project?.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = $0.apiKeyLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            return project?.isEmpty == false ? "project|\(project!)" : "key|\(apiKey?.isEmpty == false ? apiKey! : "Unlabeled")"
        }) { records in
            let first = records[0]
            let project = first.project?.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = first.apiKeyLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            if project?.isEmpty == false {
                return (project!, first.provider.displayName)
            }
            return (apiKey?.isEmpty == false ? apiKey! : "Unlabeled", first.provider.displayName)
        }
        recentRecords = Array(filtered.prefix(120))
        kpis = Self.makeKPIs(records: filtered, daily: daily)
    }

    private static func makeKPIs(records: [UsageRecord], daily: [DashboardDailyPoint]) -> DashboardKPIs {
        let spend = records.reduce(Decimal(0)) { $0 + $1.costUSD }
        let tokens = records.reduce(0) { $0 + $1.observedTokens }
        let cached = records.reduce(0) { $0 + $1.cachedInputTokens }
        let reasoning = records.reduce(0) { $0 + $1.reasoningOutputTokens }
        let count = records.count
        let activeDays = daily.filter { $0.records > 0 }.count
        let providerCount = Set(records.map(\.provider)).count
        let peakDay = daily.map(\.tokens).max() ?? 0
        let cacheRatio = tokens > 0 ? Decimal(cached) / Decimal(tokens) : 0
        return DashboardKPIs(
            spend: spend,
            tokens: tokens,
            cachedTokens: cached,
            reasoningTokens: reasoning,
            requestCount: count,
            averageTokensPerRequest: count > 0 ? tokens / count : 0,
            activeDays: activeDays,
            peakDayTokens: peakDay,
            providerCount: providerCount,
            cacheRatio: cacheRatio
        )
    }

    private static func makeDaily(
        records: [UsageRecord],
        start: Date?,
        now: Date,
        calendar: Calendar
    ) -> [DashboardDailyPoint] {
        guard !records.isEmpty || start != nil else { return [] }
        let startDate = start ?? records.map(\.timestamp).min().map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
        let endDate = calendar.startOfDay(for: now)
        let dayCount = max(1, min(120, (calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1))
        let starts = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
        }
        let grouped = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }
        return starts.map { day in
            let rows = grouped[day] ?? []
            return DashboardDailyPoint(
                date: day,
                spend: rows.reduce(Decimal(0)) { $0 + $1.costUSD },
                tokens: rows.reduce(0) { $0 + $1.observedTokens },
                cachedTokens: rows.reduce(0) { $0 + $1.cachedInputTokens },
                reasoningTokens: rows.reduce(0) { $0 + $1.reasoningOutputTokens },
                records: rows.count
            )
        }
    }

    private static func breakdown(
        records: [UsageRecord],
        group: (UsageRecord) -> String,
        label: ([UsageRecord]) -> (title: String, subtitle: String)
    ) -> [DashboardBreakdownRow] {
        let grouped = Dictionary(grouping: records, by: group)
        let rows = grouped.compactMap { key, rows -> DashboardBreakdownRow? in
            guard !rows.isEmpty else { return nil }
            let label = label(rows)
            return DashboardBreakdownRow(
                id: key,
                title: label.title,
                subtitle: label.subtitle,
                spend: rows.reduce(Decimal(0)) { $0 + $1.costUSD },
                tokens: rows.reduce(0) { $0 + $1.observedTokens },
                count: rows.count,
                ratio: 0,
                lastSeen: rows.map(\.timestamp).max()
            )
        }
        let maxTokens = max(rows.map(\.tokens).max() ?? 0, 1)
        return rows
            .map { row in
                DashboardBreakdownRow(
                    id: row.id,
                    title: row.title,
                    subtitle: row.subtitle,
                    spend: row.spend,
                    tokens: row.tokens,
                    count: row.count,
                    ratio: Decimal(row.tokens) / Decimal(maxTokens),
                    lastSeen: row.lastSeen
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.spend > rhs.spend
                }
                return lhs.tokens > rhs.tokens
            }
    }
}

extension UsageRecord {
    var observedTokens: Int {
        inputTokens + cachedInputTokens + outputTokens
    }
}
