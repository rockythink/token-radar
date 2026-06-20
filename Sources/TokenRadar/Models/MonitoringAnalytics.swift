import Foundation
import TokenRadarCore

struct MonitoringUsageAggregate: Equatable {
    var records: Int = 0
    var tokens: Int = 0
    var spend: Decimal = 0
    var latest: Date?

    static let empty = MonitoringUsageAggregate()

    mutating func add(_ record: UsageRecord) {
        records += 1
        tokens += record.observedTokens
        spend += record.costUSD
        latest = latest.map { max($0, record.timestamp) } ?? record.timestamp
    }
}

struct MonitoringModelUsageRow: Identifiable, Equatable {
    var id: String
    var model: String
    var provider: ProviderKind
    var source: UsageSource
    var tokens: Int
    var requests: Int
    var spend: Decimal
    var lastSeen: Date?
    var ratio: Decimal
}

struct MonitoringAnalytics: Equatable {
    var codex: MonitoringUsageAggregate
    var claudeCode: MonitoringUsageAggregate
    var localProxy: MonitoringUsageAggregate
    var providerUsage: [ProviderKind: MonitoringUsageAggregate]
    var modelRows: [MonitoringModelUsageRow]

    static let empty = MonitoringAnalytics(
        codex: .empty,
        claudeCode: .empty,
        localProxy: .empty,
        providerUsage: [:],
        modelRows: []
    )

    static func make(
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MonitoringAnalytics {
        var codex = MonitoringUsageAggregate.empty
        var claudeCode = MonitoringUsageAggregate.empty
        var localProxy = MonitoringUsageAggregate.empty
        var providerUsage: [ProviderKind: MonitoringUsageAggregate] = [:]

        let monthStart = DateRanges.startOfMonth(containing: now, calendar: calendar)
        var monthModelGroups: [String: (records: Int, tokens: Int, spend: Decimal, latest: Date?, model: String, provider: ProviderKind, source: UsageSource)] = [:]

        for record in records {
            if isCodexRecord(record) {
                codex.add(record)
            }
            if isClaudeCodeRecord(record) {
                claudeCode.add(record)
            }
            if record.source == .localProxy {
                localProxy.add(record)
            }
            if record.source != .cliSessionLog {
                providerUsage[record.provider, default: .empty].add(record)
            }

            guard record.timestamp >= monthStart else { continue }
            let key = "\(record.provider.rawValue)|\(record.source.rawValue)|\(record.model)"
            var group = monthModelGroups[key] ?? (
                records: 0,
                tokens: 0,
                spend: 0,
                latest: nil,
                model: record.model,
                provider: record.provider,
                source: record.source
            )
            group.records += 1
            group.tokens += record.observedTokens
            group.spend += record.costUSD
            group.latest = group.latest.map { max($0, record.timestamp) } ?? record.timestamp
            monthModelGroups[key] = group
        }

        let modelRowsWithoutRatio = monthModelGroups.map { key, group in
            MonitoringModelUsageRow(
                id: key,
                model: group.model,
                provider: group.provider,
                source: group.source,
                tokens: group.tokens,
                requests: group.records,
                spend: group.spend,
                lastSeen: group.latest,
                ratio: 0
            )
        }
        let maxTokens = max(modelRowsWithoutRatio.map(\.tokens).max() ?? 0, 1)
        let modelRows = modelRowsWithoutRatio
            .map { row in
                MonitoringModelUsageRow(
                    id: row.id,
                    model: row.model,
                    provider: row.provider,
                    source: row.source,
                    tokens: row.tokens,
                    requests: row.requests,
                    spend: row.spend,
                    lastSeen: row.lastSeen,
                    ratio: Decimal(row.tokens) / Decimal(maxTokens)
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.spend > rhs.spend
                }
                return lhs.tokens > rhs.tokens
            }

        return MonitoringAnalytics(
            codex: codex,
            claudeCode: claudeCode,
            localProxy: localProxy,
            providerUsage: providerUsage,
            modelRows: modelRows
        )
    }

    private static func isCodexRecord(_ record: UsageRecord) -> Bool {
        record.provider == .openAI &&
            record.source == .cliSessionLog &&
            (
                record.apiKeyLabel == "Codex" ||
                record.model.localizedCaseInsensitiveContains("codex")
            )
    }

    private static func isClaudeCodeRecord(_ record: UsageRecord) -> Bool {
        record.provider == .anthropic &&
            record.source == .cliSessionLog &&
            record.apiKeyLabel == "Claude Code"
    }
}
