import SwiftUI
import TokenRadarCore

struct MonitoringDashboardSource: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var status: String
    var records: Int
    var tokens: Int
    var spend: Decimal
    var lastData: String
    var appIcon: AppIconKind?
    var provider: ProviderKind?
    var symbol: String
    var tint: Color
    var actionTitle: String
    var actionSymbol: String
    var isActionDisabled: Bool
}

struct MonitoringQuickSource: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var provider: ProviderKind?
    var appIcon: AppIconKind?
    var accountKind: MonitorAccountKind
    var symbol: String
    var tint: Color
    var badge: String
    var actionTitle: String
    var isConfigured: Bool
}

struct UnifiedMonitoringDashboard: View {
    @ObservedObject var store: AppStore
    var sources: [MonitoringDashboardSource]
    var modelRows: [MonitoringModelUsageRow]
    var quickSources: [MonitoringQuickSource]
    var onRefresh: () -> Void
    var onSourceAction: (String) -> Void
    var onQuickSource: (String) -> Void

    private var autoSourceCount: Int {
        sources.filter { $0.appIcon != nil }.count
    }

    private var totalTokens: Int {
        sources.reduce(0) { $0 + $1.tokens }
    }

    private var totalRecords: Int {
        sources.reduce(0) { $0 + $1.records }
    }

    private var variableSpend: Decimal {
        store.summary.monthSpendUSD
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metricGrid

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
                sourceList
                modelUsageList
            }

            quickSourceGrid
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            SectionHeader(
                title: store.t("monitoring.dashboard_title"),
                subtitle: store.t("monitoring.dashboard_subtitle")
            )
            Spacer(minLength: 12)
            Button(action: onRefresh) {
                Label(store.t("menu.refresh"), systemImage: "arrow.clockwise")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
            MonitoringDashboardMetricTile(
                title: store.t("monitoring.dashboard_sources"),
                value: "\(sources.count)",
                detail: "\(autoSourceCount) \(store.t("monitoring.dashboard_auto_sources"))",
                symbol: "point.3.connected.trianglepath.dotted",
                tint: .orange
            )
            MonitoringDashboardMetricTile(
                title: store.t("dashboard.observed_tokens"),
                value: formatTokens(totalTokens),
                detail: "\(totalRecords) \(store.t("monitoring.requests"))",
                symbol: "number",
                tint: .green
            )
            MonitoringDashboardMetricTile(
                title: store.t("dashboard.fixed_cost"),
                value: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD),
                detail: store.t("dashboard.subscription_fixed_detail"),
                symbol: "creditcard",
                tint: .blue
            )
            MonitoringDashboardMetricTile(
                title: store.t("monitoring.dashboard_api_package"),
                value: MoneyFormatter.compactUSD(variableSpend),
                detail: store.t("dashboard.variable_spend_detail"),
                symbol: "server.rack",
                tint: .cyan
            )
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: store.t("monitoring.dashboard_sources_title"),
                subtitle: store.t("monitoring.dashboard_sources_subtitle")
            )

            ForEach(sources) { source in
                MonitoringDashboardSourceCard(
                    store: store,
                    source: source,
                    onAction: {
                        onSourceAction(source.id)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var modelUsageList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: store.t("monitoring.dashboard_model_usage"),
                subtitle: store.t("monitoring.dashboard_model_usage_subtitle")
            )

            if modelRows.isEmpty {
                EmptyStateLine(text: store.t("monitoring.dashboard_no_model_usage"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(modelRows.prefix(8)) { row in
                        MonitoringModelUsageRowView(store: store, row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quickSourceGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: store.t("monitoring.dashboard_quick_sources"),
                subtitle: store.t("monitoring.dashboard_quick_sources_subtitle")
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(quickSources) { source in
                    MonitoringQuickSourceCard(
                        store: store,
                        source: source,
                        onAction: {
                            onQuickSource(source.id)
                        }
                    )
                }
            }
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000_000 {
            return String(format: "%.1fB", Double(tokens) / 1_000_000_000)
        }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

private struct MonitoringDashboardMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MonitoringDashboardSourceCard: View {
    @ObservedObject var store: AppStore
    var source: MonitoringDashboardSource
    var onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                SourceIconView(
                    appIcon: source.appIcon,
                    provider: source.provider,
                    size: 28,
                    fallbackSystemImage: source.symbol,
                    fallbackTint: source.tint
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(source.status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(source.tint)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(source.tint.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                compactMetric(store.t("monitoring.detail_records"), value: "\(source.records)")
                compactMetric(store.t("monitoring.detail_tokens"), value: formatTokens(source.tokens))
                compactMetric(store.t("monitoring.detail_spend"), value: MoneyFormatter.compactUSD(source.spend))
            }

            HStack(spacing: 8) {
                Text("\(store.t("monitoring.detail_last_data")) \(source.lastData)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onAction) {
                    Label(source.actionTitle, systemImage: source.actionSymbol)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(source.isActionDisabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func compactMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.0fk", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

private struct MonitoringModelUsageRowView: View {
    @ObservedObject var store: AppStore
    var row: MonitoringModelUsageRow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                ProviderIconView(provider: row.provider, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.model)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(row.provider.displayName) · \(store.usageSourceLabel(row.source))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatTokens(row.tokens))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text("\(row.requests) \(store.t("monitoring.requests"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SpendProgressBar(
                value: row.ratio,
                maxValue: 1,
                tint: .orange
            )

            HStack(spacing: 8) {
                Text(MoneyFormatter.compactUSD(row.spend))
                Spacer(minLength: 8)
                Text(lastSeenText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var lastSeenText: String {
        guard let lastSeen = row.lastSeen else {
            return store.t("monitoring.no_records")
        }
        return "\(store.t("monitoring.dashboard_last_seen")) \(lastSeen.formatted(date: .abbreviated, time: .shortened))"
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM tok", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.0fk tok", Double(tokens) / 1_000)
        }
        return "\(tokens) tok"
    }
}

private struct MonitoringQuickSourceCard: View {
    @ObservedObject var store: AppStore
    var source: MonitoringQuickSource
    var onAction: () -> Void

    var body: some View {
        Button(action: onAction) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    SourceIconView(
                        appIcon: source.appIcon,
                        provider: source.provider,
                        size: 26,
                        fallbackSystemImage: source.symbol,
                        fallbackTint: source.tint
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(source.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 7) {
                    Text(source.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(source.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(source.tint.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer(minLength: 8)
                    Label(source.actionTitle, systemImage: source.isConfigured ? "checkmark.circle" : "plus.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(source.isConfigured ? .secondary : source.tint)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
