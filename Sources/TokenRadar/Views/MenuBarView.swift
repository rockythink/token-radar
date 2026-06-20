import AppKit
import SwiftUI
import TokenRadarCore

struct MenuBarLabelView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: store.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
            Text(labelText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: 128)
    }

    private var labelText: String {
        if store.summary.alert?.severity == .critical {
            return store.t("menu.remaining")
        }
        if let quota = primarySubscriptionQuota, quota.isProviderReported {
            return "\(MoneyFormatter.percent(quota.remainingRatio)) \(store.t("quota.remaining"))"
        }
        if store.totalMonthlyBudgetUSD > 0 {
            return MoneyFormatter.compactUSD(store.summary.remainingBudgetUSD)
        }
        if store.monthlySubscriptionFeesUSD > 0 {
            return "\(MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD))/mo"
        }
        return MoneyFormatter.compactUSD(store.summary.todaySpendUSD)
    }

    private var statusColor: Color {
        switch store.summary.alert?.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        default:
            if let quota = primarySubscriptionQuota, quota.isProviderReported {
                return quota.remainingRatio <= Decimal(string: "0.15")! ? Color.red :
                    quota.remainingRatio <= Decimal(string: "0.35")! ? Color.orange : Color.green
            }
            return store.isProxyRunning ? .green : .teal
        }
    }

    private var primarySubscriptionQuota: QuotaWindowSummary? {
        store.subscriptionMonitorSummaries
            .flatMap(\.quotaWindowSummaries)
            .sorted { lhs, rhs in
                if lhs.utilization == rhs.utilization {
                    return lhs.periodEnd < rhs.periodEnd
                }
                return lhs.utilization > rhs.utilization
            }
            .first
    }
}

private struct MenuRingState {
    var progress: Decimal
    var centerText: String
    var centerCaption: String
    var title: String
    var detail: String
    var tint: Color
}

struct MenuBarView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var range: DashboardTimeRange = .last7Days
    @State private var metricMode: DashboardMetricMode = .tokens
    @State private var analytics = DashboardAnalytics.empty
    @State private var analyticsKey = DashboardAnalyticsKey(recordsVersion: -1, filter: DashboardFilter())

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            menuHeroCard(analytics)
            menuControls
            menuMetrics(analytics)
            miniTrendPanel(analytics)
            quotaSnapshotPanel
            menuRankPanels(analytics)
            actionBar
        }
        .padding(14)
        .frame(width: 440)
        .task {
            rebuildMenuAnalyticsIfNeeded()
        }
        .onChange(of: range) {
            rebuildMenuAnalyticsIfNeeded()
        }
        .onChange(of: metricMode) {
            rebuildMenuAnalyticsIfNeeded()
        }
        .onChange(of: store.recordsVersion) {
            rebuildMenuAnalyticsIfNeeded()
        }
    }

    private var menuFilter: DashboardFilter {
        var filter = DashboardFilter()
        filter.timeRange = range
        filter.metricMode = metricMode
        return filter
    }

    private func rebuildMenuAnalyticsIfNeeded() {
        let filter = menuFilter
        let key = DashboardAnalyticsKey(recordsVersion: store.recordsVersion, filter: filter)
        guard key != analyticsKey else { return }
        analytics = DashboardAnalytics(records: store.records, filter: filter)
        analyticsKey = key
    }

    private func menuHeroCard(_ analytics: DashboardAnalytics) -> some View {
        let ring = primaryMenuRing

        return HStack(alignment: .center, spacing: 12) {
            StatusRingView(
                progress: ring.progress,
                centerText: ring.centerText,
                centerCaption: ring.centerCaption,
                tint: ring.tint,
                lineWidth: 7
            )
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(store.t("menu.mini_dashboard"))
                        .font(.system(size: 17, weight: .semibold))
                    Circle()
                        .fill(store.isProxyRunning ? .green : .secondary.opacity(0.55))
                        .frame(width: 6, height: 6)
                }
                Text(ring.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(ring.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(formatTokens(analytics.kpis.tokens)) · \(analytics.kpis.requestCount) \(store.t("monitoring.requests")) · \(proxyStatus)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(MoneyFormatter.compactUSD(store.monthTotalCostUSD))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(store.t("dashboard.total_month"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(store.t("dashboard.fixed_plus_variable"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Button {
                    Task { await store.refreshAllProviders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(store.t("menu.refresh"))
            }
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.cyan.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryMenuRing: MenuRingState {
        if let quota = primaryQuotaSummary {
            return MenuRingState(
                progress: quota.remainingRatio,
                centerText: MoneyFormatter.percent(quota.remainingRatio),
                centerCaption: store.t("quota.remaining"),
                title: quota.window.name,
                detail: quotaDetailLine(quota),
                tint: quotaTint(quota)
            )
        }

        if store.totalMonthlyBudgetUSD > 0 {
            return MenuRingState(
                progress: store.budgetUsedRatio,
                centerText: MoneyFormatter.percent(store.budgetUsedRatio),
                centerCaption: store.t("menu.ring_used"),
                title: store.t("menu.api_budget"),
                detail: "\(MoneyFormatter.compactUSD(store.summary.monthSpendUSD)) / \(MoneyFormatter.compactUSD(store.totalMonthlyBudgetUSD))",
                tint: budgetTint(store.budgetUsedRatio)
            )
        }

        if store.monthlySubscriptionFeesUSD > 0 {
            return MenuRingState(
                progress: 1,
                centerText: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD),
                centerCaption: store.t("monitoring.per_month"),
                title: store.t("menu.fixed_subscription"),
                detail: store.t("monitoring.subscription_not_usage_budget"),
                tint: .blue
            )
        }

        return MenuRingState(
            progress: 0,
            centerText: "0%",
            centerCaption: store.t("menu.ring_used"),
            title: store.t("menu.no_monitoring"),
            detail: store.t("monitoring.add_first"),
            tint: .secondary
        )
    }

    private var primaryQuotaSummary: QuotaWindowSummary? {
        store.subscriptionMonitorSummaries
            .flatMap(\.quotaWindowSummaries)
            .sorted { lhs, rhs in
                if lhs.utilization == rhs.utilization {
                    return lhs.periodEnd < rhs.periodEnd
                }
                return lhs.utilization > rhs.utilization
            }
            .first
    }

    private func quotaDetailLine(_ summary: QuotaWindowSummary) -> String {
        let source = store.isCodexSessionQuotaWindow(summary.window)
            ? store.t("quota.codex_session_reported")
            : (summary.isProviderReported ? store.t("quota.provider_reported") : store.t("monitoring.source_manual_estimate"))
        return "\(source) · \(quotaRefreshText(summary))"
    }

    private func budgetTint(_ ratio: Decimal) -> Color {
        if ratio >= Decimal(string: "0.95")! { return .red }
        if ratio >= Decimal(string: "0.8")! { return .orange }
        if ratio >= Decimal(string: "0.5")! { return .teal }
        return .green
    }

    private var menuControls: some View {
        HStack(spacing: 8) {
            Picker(store.t("dashboard.range"), selection: $range) {
                Text(store.t("dashboard.range_7d")).tag(DashboardTimeRange.last7Days)
                Text(store.t("dashboard.range_30d")).tag(DashboardTimeRange.last30Days)
                Text(store.t("dashboard.range_month")).tag(DashboardTimeRange.thisMonth)
            }
            .pickerStyle(.segmented)

            Picker(store.t("dashboard.metric"), selection: $metricMode) {
                Text(store.t("dashboard.metric_tokens")).tag(DashboardMetricMode.tokens)
                Text(store.t("dashboard.metric_spend")).tag(DashboardMetricMode.spend)
            }
            .pickerStyle(.segmented)
            .frame(width: 158)
        }
    }

    private func menuMetrics(_ analytics: DashboardAnalytics) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            MenuMetric(title: store.t("dashboard.observed_tokens"), value: formatTokens(analytics.kpis.tokens), tint: .orange)
            MenuMetric(title: store.t("dashboard.filtered_spend"), value: MoneyFormatter.compactUSD(analytics.kpis.spend), tint: .cyan)
            MenuMetric(title: store.t("dashboard.cache_ratio"), value: MoneyFormatter.percent(analytics.kpis.cacheRatio), tint: .teal)
            MenuMetric(title: store.t("dashboard.peak_day"), value: formatTokens(analytics.kpis.peakDayTokens), tint: .purple)
        }
    }

    private func miniTrendPanel(_ analytics: DashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("dashboard.token_trend"), systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metricMode == .tokens ? formatTokens(analytics.kpis.averageTokensPerRequest) : MoneyFormatter.compactUSD(analytics.kpis.spend))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            let values = metricMode == .tokens
                ? analytics.daily.map { Decimal($0.tokens) }
                : analytics.daily.map(\.spend)
            SparklineView(values: values, tint: metricMode == .tokens ? .orange : .cyan)
                .frame(height: 64)
            ActivityHeatmapView(points: analytics.daily, showsSelectionLabel: false)
                .frame(height: 42)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var quotaSnapshotPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("menu.quota"), systemImage: "gauge.with.dots.needle.bottom.50percent")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let quotas = store.subscriptionMonitorSummaries
                .flatMap(\.quotaWindowSummaries)
                .filter(\.isProviderReported)
                .prefix(4)
            if quotas.isEmpty {
                EmptyStateLine(text: store.t("subscription.empty_short"))
                    .frame(height: 28)
            } else {
                ForEach(Array(quotas), id: \.window.id) { quota in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(quota.window.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(MoneyFormatter.percent(quota.remainingRatio))
                                .font(.caption.monospacedDigit())
                        }
                        Text(quotaRefreshText(quota))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        SpendProgressBar(value: quota.remainingRatio, maxValue: 1, tint: quotaTint(quota))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func menuRankPanels(_ analytics: DashboardAnalytics) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MenuRankList(title: store.t("dashboard.provider_mix"), rows: Array(analytics.providerRows.prefix(4)), metricMode: metricMode)
            MenuRankList(title: store.t("dashboard.model_rank"), rows: Array(analytics.modelRows.prefix(4)), metricMode: metricMode)
        }
    }

    private var header: some View {
        let ring = primaryMenuRing

        return HStack(alignment: .center, spacing: 12) {
            StatusRingView(
                progress: ring.progress,
                centerText: ring.centerText,
                centerCaption: ring.centerCaption,
                tint: ring.tint,
                lineWidth: 7
            )
                .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("app.title"))
                    .font(.system(size: 17, weight: .semibold))
                Text(ring.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let alert = store.summary.alert {
                    Text(store.budgetAlertMessage(alert))
                        .font(.caption)
                        .foregroundStyle(alert.severity == .critical ? .red : .orange)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var spendOverview: some View {
        HStack(spacing: 10) {
            MenuMetric(title: store.t("menu.today"), value: MoneyFormatter.compactUSD(store.summary.todaySpendUSD), tint: .green)
            MenuMetric(title: store.t("menu.month"), value: MoneyFormatter.compactUSD(store.summary.monthSpendUSD), tint: .cyan)
            MenuMetric(title: store.t("menu.fixed"), value: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD), tint: .orange)
        }
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("menu.burn_rate"), systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(MoneyFormatter.compactUSD(store.summary.burnRatePerDayUSD)) / d")
                    .font(.caption.monospacedDigit())
            }
            SparklineView(values: store.dailySpendSeries(days: 14).map(\.spend), tint: .cyan)
                .frame(height: 58)
            MicroBarView(values: store.dailySpendSeries(days: 14).map(\.spend))
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("nav.providers"), systemImage: "server.rack")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let rows = store.providerSpendDistribution()
            if rows.isEmpty {
                EmptyStateLine(text: store.t("dashboard.no_usage"))
                    .frame(height: 30)
            } else {
                ProviderDistributionBar(rows: rows)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subscriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("subscription.title"), systemImage: "creditcard")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD))
                    .font(.caption.monospacedDigit())
            }

            if let summary = store.subscriptionMonitorSummaries.first {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.target.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let quota = summary.quotaWindowSummaries.first {
                            Text(quotaMenuLine(quota))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(MoneyFormatter.compactUSD(summary.target.fixedMonthlyFeeUSD)) / \(store.t("monitoring.per_month"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(store.t("monitoring.fixed_subscription_fee"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let quota = summary.quotaWindowSummaries.first {
                    SpendProgressBar(value: quotaProgressValue(quota), maxValue: quotaProgressMaxValue(quota), tint: quotaTint(quota))
                }
            } else if let summary = store.subscriptionSummaries.first {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.plan.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("\(formatUnits(summary.remainingUnits, unit: summary.plan.quotaUnit)) \(store.t("subscription.remaining_short"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(MoneyFormatter.percent(summary.utilization))
                        .font(.caption.monospacedDigit())
                }
                SpendProgressBar(value: summary.usedUnits, maxValue: summary.plan.includedUnits, tint: summary.utilization > Decimal(string: "0.9")! ? .orange : .blue)
            } else {
                EmptyStateLine(text: store.t("subscription.empty_short"))
                    .frame(height: 28)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("menu.top_model"), systemImage: "cpu")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.topModelTitle)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }

            let models = store.spendByModel(limit: 4)
            if models.isEmpty {
                EmptyStateLine(text: store.t("dashboard.no_usage"))
                    .frame(height: 30)
            } else {
                let maxSpend = models.map(\.spend).max() ?? 0
                ForEach(models, id: \.model) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ModelIconView(modelName: row.model, provider: row.provider, size: 18)
                            Text(row.model)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(MoneyFormatter.compactUSD(row.spend))
                                .font(.caption.monospacedDigit())
                        }
                        SpendProgressBar(value: row.spend, maxValue: maxSpend, tint: modelTint(row.provider))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            MenuQuickActionButton(title: store.t("nav.overview"), symbol: "rectangle.grid.2x2") {
                openDashboard(section: .overview)
            }

            MenuQuickActionButton(title: store.t("nav.monitoring"), symbol: "scope") {
                openDashboard(section: .monitoring)
            }

            MenuQuickActionButton(title: store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"), symbol: store.isProxyRunning ? "pause.circle" : "play.circle") {
                store.toggleProxy()
            }

            MenuQuickActionButton(title: store.t("menu.settings"), symbol: "gearshape") {
                openDashboard(section: .settings)
            }
        }
    }

    private func openDashboard(section: DashboardSection) {
        store.selectedSection = section
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var proxyStatus: String {
        store.isProxyRunning
            ? "\(store.t("dashboard.proxy_on")) :\(store.settings.proxyPort)"
            : store.t("dashboard.proxy_paused")
    }

    private func modelTint(_ provider: ProviderKind) -> Color {
        switch provider {
        case .openAI:
            .green
        case .anthropic:
            .orange
        case .gemini:
            .blue
        case .deepSeek:
            .cyan
        case .xAI:
            .purple
        default:
            .teal
        }
    }

    private func quotaMenuLine(_ summary: QuotaWindowSummary) -> String {
        if summary.isProviderReported {
            return "\(summary.window.name) · \(MoneyFormatter.percent(summary.remainingRatio)) \(store.t("quota.remaining")) · \(quotaRefreshText(summary))"
        }
        return "\(formatUnits(summary.remainingUnits, unit: summary.window.quotaUnit)) \(store.t("subscription.remaining_short"))"
    }

    private func quotaRefreshText(_ summary: QuotaWindowSummary) -> String {
        if summary.remainingSeconds <= 60 {
            return store.t("quota.refresh_soon")
        }
        return "\(compactDuration(summary.remainingSeconds)) \(store.t("quota.until_refresh"))"
    }

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "\(days)\(store.t("quota.day_unit")) \(hours)\(store.t("quota.hour_unit"))"
            }
            return "\(days)\(store.t("quota.day_unit"))"
        }

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)\(store.t("quota.hour_unit")) \(minutes)\(store.t("quota.minute_unit"))"
            }
            return "\(hours)\(store.t("quota.hour_unit"))"
        }

        return "\(minutes)\(store.t("quota.minute_unit"))"
    }

    private func quotaProgressValue(_ summary: QuotaWindowSummary) -> Decimal {
        summary.isProviderReported ? summary.remainingRatio : summary.usedUnits
    }

    private func quotaProgressMaxValue(_ summary: QuotaWindowSummary) -> Decimal {
        summary.isProviderReported ? 1 : max(Decimal(1), summary.window.includedUnits)
    }

    private func quotaTint(_ summary: QuotaWindowSummary) -> Color {
        if summary.isProviderReported {
            if summary.remainingRatio <= Decimal(string: "0.15")! {
                return .red
            }
            if summary.remainingRatio <= Decimal(string: "0.35")! {
                return .orange
            }
            return .blue
        }
        return summary.utilization > Decimal(string: "0.9")! ? .orange : .blue
    }

    private func formatUnits(_ units: Decimal, unit: SubscriptionQuotaUnit) -> String {
        switch unit {
        case .messages:
            return "\(Int(units.doubleValue)) msg"
        case .tokens:
            let value = units.doubleValue
            if value >= 1_000_000 {
                return String(format: "%.1fM tok", value / 1_000_000)
            }
            if value >= 1_000 {
                return String(format: "%.0fk tok", value / 1_000)
            }
            return "\(Int(value)) tok"
        case .requests:
            return "\(Int(units.doubleValue)) req"
        case .usd:
            return MoneyFormatter.compactUSD(units)
        }
    }
}

struct MenuMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MenuQuickActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}

struct MenuRankList: View {
    var title: String
    var rows: [DashboardBreakdownRow]
    var metricMode: DashboardMetricMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            } else {
                let maxValue = max(rows.map { metricMode == .tokens ? Decimal($0.tokens) : $0.spend }.max() ?? 0, 1)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let provider = row.inferredProvider {
                                ProviderIconView(provider: provider, size: 16)
                            }
                            Text(row.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(metricMode == .tokens ? formatTokens(row.tokens) : MoneyFormatter.compactUSD(row.spend))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        SpendProgressBar(
                            value: metricMode == .tokens ? Decimal(row.tokens) : row.spend,
                            maxValue: maxValue,
                            tint: metricMode == .tokens ? .orange : .cyan
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
