import Charts
import SwiftUI
import TokenRadarCore

struct DashboardView: View {
    @ObservedObject var store: AppStore
    @State private var filter = DashboardFilter()
    @State private var analytics = DashboardAnalytics.empty
    @State private var analyticsKey = DashboardAnalyticsKey(recordsVersion: -1, filter: DashboardFilter())
    @State private var trackedCoverage: [(model: TrackedModel, spend: Decimal, tokens: Int, lastSeen: Date?)] = []
    @State private var trackedCoverageVersion = -1

    private let columns = [
        GridItem(.adaptive(minimum: 210), spacing: 12)
    ]

    var body: some View {
        let sourceRows = localizedSourceRows(analytics.sourceRows)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                DashboardHeroBand(store: store, analytics: analytics)

                if let error = store.lastError {
                    StatusBanner(title: store.t("dashboard.last_error"), message: error, symbol: "exclamationmark.triangle", tint: .red)
                } else if let alert = store.summary.alert {
                    StatusBanner(title: store.t("dashboard.budget_alert"), message: store.budgetAlertMessage(alert), symbol: "bell.badge", tint: alert.severity == .critical ? .red : .orange)
                }

                DashboardFilterBar(store: store, filter: $filter)

                BIOverviewGrid(store: store, analytics: analytics)

                BITrendPanel(store: store, analytics: analytics)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    BreakdownPanel(
                        title: store.t("dashboard.provider_mix"),
                        subtitle: store.t("dashboard.filtered_scope"),
                        rows: analytics.providerRows,
                        metricMode: filter.metricMode,
                        emptyText: store.t("dashboard.no_records"),
                        onSelect: { row in
                            filter.provider = ProviderKind(rawValue: row.id)
                        }
                    )
                    BreakdownPanel(
                        title: store.t("dashboard.source_mix"),
                        subtitle: store.t("dashboard.filtered_scope"),
                        rows: sourceRows,
                        metricMode: filter.metricMode,
                        emptyText: store.t("dashboard.no_records"),
                        onSelect: { row in
                            filter.source = UsageSource(rawValue: row.id)
                        }
                    )
                    BreakdownPanel(
                        title: store.t("dashboard.model_rank"),
                        subtitle: store.t("dashboard.filtered_scope"),
                        rows: Array(analytics.modelRows.prefix(8)),
                        metricMode: filter.metricMode,
                        emptyText: store.t("dashboard.no_records"),
                        onSelect: { row in
                            let parts = row.id.split(separator: "|", maxSplits: 1).map(String.init)
                            if let providerRaw = parts.first {
                                filter.provider = ProviderKind(rawValue: providerRaw)
                            }
                            filter.searchText = row.title
                        }
                    )
                    BreakdownPanel(
                        title: store.t("dashboard.project_rank"),
                        subtitle: store.t("dashboard.filtered_scope"),
                        rows: Array(analytics.projectRows.prefix(8)),
                        metricMode: filter.metricMode,
                        emptyText: store.t("dashboard.no_records"),
                        onSelect: { row in
                            filter.searchText = row.title
                        }
                    )
                }

                SubscriptionDashboardBand(store: store)

                CodexActivityBand(store: store)

                SectionHeader(title: store.t("dashboard.tracked_models"), subtitle: store.t("dashboard.tracked_models_subtitle"))
                TrackedModelTable(rows: trackedCoverage)

                BIRecordTable(store: store, records: analytics.recentRecords)
            }
            .padding(24)
        }
        .background(.background)
        .task {
            rebuildDashboardCachesIfNeeded()
        }
        .onChange(of: filter) {
            rebuildDashboardCachesIfNeeded()
        }
        .onChange(of: store.recordsVersion) {
            rebuildDashboardCachesIfNeeded()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.refreshAllProviders() }
                } label: {
                    Label(store.t("menu.refresh"), systemImage: "arrow.clockwise")
                }

                Button {
                    store.toggleProxy()
                } label: {
                    Label(store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"), systemImage: store.isProxyRunning ? "pause.circle" : "play.circle")
                }
            }
        }
    }

    private func rebuildDashboardCachesIfNeeded() {
        let key = DashboardAnalyticsKey(recordsVersion: store.recordsVersion, filter: filter)
        if key != analyticsKey {
            analytics = DashboardAnalytics(records: store.records, filter: filter)
            analyticsKey = key
        }

        if trackedCoverageVersion != store.recordsVersion {
            trackedCoverage = store.trackedModelCoverage()
            trackedCoverageVersion = store.recordsVersion
        }
    }

    private func localizedSourceRows(_ rows: [DashboardBreakdownRow]) -> [DashboardBreakdownRow] {
        rows.map { row in
            var next = row
            if let source = UsageSource(rawValue: row.id) {
                next.title = store.usageSourceLabel(source)
            }
            return next
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("app.title"))
                    .font(.system(size: 26, weight: .semibold))
                Text(store.t("dashboard.subtitle"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(store.isProxyRunning ? "\(store.t("dashboard.proxy_on")) :\(store.settings.proxyPort)" : store.t("dashboard.proxy_paused"), systemImage: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(store.isProxyRunning ? .green : .secondary)
        }
    }
}

struct DashboardHeroBand: View {
    @ObservedObject var store: AppStore
    var analytics: DashboardAnalytics

    private var enabledMonitorCount: Int {
        store.settings.monitorTargets.filter(\.isEnabled).count
    }

    private var hasFilters: Bool {
        analytics.filter.provider != nil ||
            analytics.filter.source != nil ||
            !analytics.filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("dashboard.hero_title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(MoneyFormatter.compactUSD(store.monthTotalCostUSD))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                    Text(store.t("dashboard.current_month"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    StatusPill(
                        text: "\(store.t("dashboard.tokens")) \(formatTokens(analytics.kpis.tokens))",
                        symbol: "number",
                        tint: .orange
                    )
                    StatusPill(
                        text: "\(store.t("sidebar.fixed")) \(MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD))",
                        symbol: "creditcard",
                        tint: .blue
                    )
                    StatusPill(
                        text: "\(store.t("sidebar.monitors")) \(enabledMonitorCount)",
                        symbol: "scope",
                        tint: .green
                    )
                }
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    heroMetric(store.t("dashboard.variable_month"), MoneyFormatter.compactUSD(store.summary.monthSpendUSD))
                    heroMetric(store.t("dashboard.projected"), MoneyFormatter.compactUSD(store.projectedMonthTotalCostUSD))
                    heroMetric(store.t("dashboard.budget_left"), MoneyFormatter.compactUSD(store.summary.remainingBudgetUSD))
                }

                HStack(spacing: 8) {
                    Text(hasFilters ? store.t("dashboard.filter_active") : store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        store.selectedSection = .monitoring
                    } label: {
                        Label(store.t("dashboard.manage_monitors"), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.cyan.opacity(0.10), Color.clear],
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

    private func heroMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 92, alignment: .trailing)
    }
}

struct StatusPill: View {
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct DashboardFilterBar: View {
    @ObservedObject var store: AppStore
    @Binding var filter: DashboardFilter
    @State private var showsAdvancedFilters = false

    private var hasAdvancedFilters: Bool {
        filter.provider != nil ||
            filter.source != nil ||
            !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker(store.t("dashboard.range"), selection: $filter.timeRange) {
                    Text(store.t("dashboard.range_today")).tag(DashboardTimeRange.today)
                    Text(store.t("dashboard.range_7d")).tag(DashboardTimeRange.last7Days)
                    Text(store.t("dashboard.range_30d")).tag(DashboardTimeRange.last30Days)
                    Text(store.t("dashboard.range_month")).tag(DashboardTimeRange.thisMonth)
                    Text(store.t("dashboard.range_all")).tag(DashboardTimeRange.all)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)

                Picker(store.t("dashboard.metric"), selection: $filter.metricMode) {
                    Text(store.t("dashboard.metric_tokens")).tag(DashboardMetricMode.tokens)
                    Text(store.t("dashboard.metric_spend")).tag(DashboardMetricMode.spend)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                Spacer()

                Button {
                    withAnimation(.smooth(duration: 0.16)) {
                        showsAdvancedFilters.toggle()
                    }
                } label: {
                    Label(store.t("dashboard.advanced_filters"), systemImage: hasAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    filter = DashboardFilter()
                    showsAdvancedFilters = false
                } label: {
                    Label(store.t("dashboard.clear_filters"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
            }

            if showsAdvancedFilters || hasAdvancedFilters {
                HStack(spacing: 10) {
                Picker(store.t("nav.providers"), selection: providerBinding) {
                    Text(store.t("dashboard.provider_all")).tag("")
                    ForEach(ProviderKind.allCases) { provider in
                        ProviderPickerItem(provider: provider).tag(provider.rawValue)
                    }
                }
                .frame(width: 220)

                Picker(store.t("dashboard.source"), selection: sourceBinding) {
                    Text(store.t("dashboard.source_all")).tag("")
                    ForEach(UsageSource.allCasesForDashboard, id: \.rawValue) { source in
                        Text(store.usageSourceLabel(source)).tag(source.rawValue)
                    }
                }
                .frame(width: 220)

                TextField(store.t("dashboard.search_placeholder"), text: $filter.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { filter.provider?.rawValue ?? "" },
            set: { filter.provider = ProviderKind(rawValue: $0) }
        )
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { filter.source?.rawValue ?? "" },
            set: { filter.source = UsageSource(rawValue: $0) }
        )
    }
}

struct BIOverviewGrid: View {
    @ObservedObject var store: AppStore
    var analytics: DashboardAnalytics

    private let columns = [
        GridItem(.adaptive(minimum: 175), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(title: store.t("dashboard.filtered_spend"), value: MoneyFormatter.usd(analytics.kpis.spend), detail: store.t("dashboard.variable_spend_detail"), symbol: "dollarsign.circle")
            MetricTile(title: store.t("dashboard.observed_tokens"), value: formatTokens(analytics.kpis.tokens), detail: "\(analytics.kpis.requestCount) \(store.t("monitoring.requests"))", symbol: "number")
            MetricTile(title: store.t("dashboard.avg_request"), value: formatTokens(analytics.kpis.averageTokensPerRequest), detail: store.t("dashboard.avg_request_detail"), symbol: "divide.circle")
            MetricTile(title: store.t("dashboard.cache_ratio"), value: MoneyFormatter.percent(analytics.kpis.cacheRatio), detail: formatTokens(analytics.kpis.cachedTokens), symbol: "bolt.horizontal.circle")
            MetricTile(title: store.t("dashboard.peak_day"), value: formatTokens(analytics.kpis.peakDayTokens), detail: "\(analytics.kpis.activeDays) \(store.t("dashboard.active_days"))", symbol: "chart.bar.fill")
            MetricTile(title: store.t("dashboard.fixed_cost"), value: MoneyFormatter.usd(store.monthlySubscriptionFeesUSD), detail: store.t("dashboard.subscription_fixed_detail"), symbol: "creditcard")
        }
    }
}

struct BITrendPanel: View {
    @ObservedObject var store: AppStore
    var analytics: DashboardAnalytics
    @State private var selectedTrendDate: Date?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: store.t("dashboard.token_trend"), subtitle: store.t("dashboard.filtered_scope"))
                InteractiveMetricChartView(
                    points: analytics.daily,
                    metricMode: analytics.filter.metricMode,
                    selectedDate: $selectedTrendDate,
                    cachedLabel: store.t("dashboard.cached_tokens"),
                    reasoningLabel: store.t("dashboard.reasoning_tokens")
                )
                .frame(height: 142)
                HStack {
                    Text("\(store.t("dashboard.reasoning_tokens")) \(formatTokens(analytics.kpis.reasoningTokens))")
                    Spacer()
                    Text("\(store.t("dashboard.cached_tokens")) \(formatTokens(analytics.kpis.cachedTokens))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: store.t("dashboard.activity_heatmap"), subtitle: store.t("dashboard.filtered_scope"))
                ActivityHeatmapView(points: analytics.daily)
                    .frame(height: 122)
                HStack {
                    Text("\(analytics.kpis.providerCount) \(store.t("dashboard.providers_count"))")
                    Spacer()
                    Text("\(analytics.kpis.requestCount) \(store.t("monitoring.requests"))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct InteractiveMetricChartView: View {
    var points: [DashboardDailyPoint]
    var metricMode: DashboardMetricMode
    @Binding var selectedDate: Date?
    var cachedLabel: String
    var reasoningLabel: String

    private var selectedPoint: DashboardDailyPoint? {
        guard let selectedDate else { return points.last }
        return points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedDate)) < abs(rhs.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { point in
                    let value = metricValue(point)
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metricName, value)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(point.date == selectedPoint?.date ? Color.orange.gradient : Color.cyan.opacity(0.28).gradient)

                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metricName, value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(chartTint.opacity(0.14).gradient)

                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(metricName, value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(chartTint)
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected", selectedPoint.date, unit: .day))
                        .foregroundStyle(.primary.opacity(0.22))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                    PointMark(
                        x: .value("Selected", selectedPoint.date, unit: .day),
                        y: .value(metricName, metricValue(selectedPoint))
                    )
                    .symbolSize(72)
                    .foregroundStyle(chartTint)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(.secondary.opacity(0.18))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.14))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(axisLabel(doubleValue))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(
                        LinearGradient(
                            colors: [chartTint.opacity(0.10), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .chartBackground { _ in
                if let selectedPoint {
                    selectedTooltip(for: selectedPoint)
                }
            }
            .animation(.smooth(duration: 0.18), value: selectedDate)

            if let selectedPoint {
                HStack(spacing: 12) {
                    Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.medium))
                    Text(formatTokens(selectedPoint.tokens))
                    Text(MoneyFormatter.compactUSD(selectedPoint.spend))
                    Text("\(selectedPoint.records)")
                    Spacer()
                    Text("\(formatTokens(selectedPoint.cachedTokens)) \(cachedLabel)")
                    Text("\(formatTokens(selectedPoint.reasoningTokens)) \(reasoningLabel)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var metricName: String {
        metricMode == .tokens ? "Tokens" : "Spend"
    }

    private var chartTint: Color {
        metricMode == .tokens ? .orange : .cyan
    }

    private func metricValue(_ point: DashboardDailyPoint) -> Double {
        switch metricMode {
        case .tokens:
            return Double(point.tokens)
        case .spend:
            return point.spend.doubleValue
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metricMode {
        case .tokens:
            return formatTokens(Int(value))
        case .spend:
            return MoneyFormatter.compactUSD(Decimal(value))
        }
    }

    private func selectedTooltip(for point: DashboardDailyPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                Text(formatTokens(point.tokens))
                Text(MoneyFormatter.compactUSD(point.spend))
                Text("\(point.records)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

struct ActivityHeatmapView: View {
    var points: [DashboardDailyPoint]
    var showsSelectionLabel: Bool = true
    @State private var selectedDate: Date?
    @State private var hoveredDate: Date?

    private var selectedPoint: DashboardDailyPoint? {
        let activeDate = hoveredDate ?? selectedDate
        guard let activeDate else { return nil }
        return points.first { $0.date == activeDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let columns = max(12, min(30, Int(proxy.size.width / 18)))
                let cellSize = max(8, min(14, (proxy.size.width - CGFloat(columns - 1) * 4) / CGFloat(columns)))
                let maxTokens = max(points.map(\.tokens).max() ?? 0, 1)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 4), count: columns), spacing: 4) {
                    ForEach(points.suffix(columns * 6)) { point in
                        let isActive = (hoveredDate ?? selectedDate) == point.date
                        RoundedRectangle(cornerRadius: 3)
                            .fill(heatColor(tokens: point.tokens, maxTokens: maxTokens))
                            .frame(width: cellSize, height: cellSize)
                            .scaleEffect(isActive ? 1.18 : 1)
                            .overlay {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(.primary.opacity(0.7), lineWidth: 1)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDate = point.date
                            }
                            .onHover { isHovering in
                                hoveredDate = isHovering ? point.date : nil
                            }
                            .help(point.date.formatted(date: .abbreviated, time: .omitted) + " · " + formatTokens(point.tokens))
                            .animation(.smooth(duration: 0.16), value: isActive)
                    }
                }
            }

            if showsSelectionLabel {
                if let selectedPoint {
                    Text("\(selectedPoint.date.formatted(date: .abbreviated, time: .omitted)) · \(formatTokens(selectedPoint.tokens)) · \(selectedPoint.records)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                        .font(.caption)
                }
            }
        }
    }

    private func heatColor(tokens: Int, maxTokens: Int) -> Color {
        guard tokens > 0 else { return Color.secondary.opacity(0.13) }
        let ratio = Double(tokens) / Double(maxTokens)
        if ratio > 0.75 { return .orange }
        if ratio > 0.45 { return .cyan }
        if ratio > 0.2 { return .teal }
        return .green.opacity(0.75)
    }
}

struct BreakdownPanel: View {
    var title: String
    var subtitle: String
    var rows: [DashboardBreakdownRow]
    var metricMode: DashboardMetricMode
    var emptyText: String
    var onSelect: ((DashboardBreakdownRow) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: subtitle)
            if rows.isEmpty {
                EmptyStateLine(text: emptyText)
            } else {
                let maxValue = max(rows.map { metricMode == .tokens ? Decimal($0.tokens) : $0.spend }.max() ?? 0, 1)
                ForEach(rows.prefix(8)) { row in
                    Button {
                        onSelect?(row)
                    } label: {
                        BreakdownRowContent(row: row, metricMode: metricMode, maxValue: maxValue)
                    }
                    .buttonStyle(.plain)
                    .help(row.title)
                    Divider()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BreakdownRowContent: View {
    var row: DashboardBreakdownRow
    var metricMode: DashboardMetricMode
    var maxValue: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let provider = row.inferredProvider {
                    ProviderIconView(provider: provider, size: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(metricMode == .tokens ? formatTokens(row.tokens) : MoneyFormatter.compactUSD(row.spend))
                        .font(.subheadline.monospacedDigit())
                    Text("\(row.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            SpendProgressBar(
                value: metricMode == .tokens ? Decimal(row.tokens) : row.spend,
                maxValue: maxValue,
                tint: metricMode == .tokens ? .orange : .cyan
            )
        }
        .contentShape(Rectangle())
    }
}

struct BIRecordTable: View {
    @ObservedObject var store: AppStore
    var records: [UsageRecord]
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator<DashboardRecordTableRow>(\.timestamp, order: .reverse)]

    private var rows: [DashboardRecordTableRow] {
        records.map { record in
            DashboardRecordTableRow(
                id: record.id,
                timestamp: record.timestamp,
                providerKind: record.provider,
                provider: record.provider.displayName,
                source: store.usageSourceLabel(record.source),
                model: record.model,
                project: record.project ?? record.apiKeyLabel ?? record.source.rawValue,
                tokens: record.observedTokens,
                cachedTokens: record.cachedInputTokens,
                reasoningTokens: record.reasoningOutputTokens,
                cost: record.costUSD.doubleValue
            )
        }
        .sorted(using: sortOrder)
    }

    private var selectedRow: DashboardRecordTableRow? {
        guard let selection else { return nil }
        return rows.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: store.t("dashboard.recent_records"), subtitle: store.t("dashboard.filtered_scope"))
            if records.isEmpty {
                EmptyStateLine(text: store.t("dashboard.no_records"))
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(store.t("nav.providers"), value: \.provider) { row in
                        HStack(spacing: 7) {
                            ProviderIconView(provider: row.providerKind, size: 18)
                            Text(row.provider)
                                .lineLimit(1)
                        }
                    }
                        .width(min: 120, ideal: 150)
                    TableColumn(store.t("dashboard.source"), value: \.source)
                        .width(min: 110, ideal: 140)
                    TableColumn(store.t("dashboard.model"), value: \.model)
                        .width(min: 180, ideal: 260)
                    TableColumn(store.t("monitoring.scope_project"), value: \.project)
                        .width(min: 120, ideal: 180)
                    TableColumn(store.t("dashboard.tokens"), value: \.tokens) { row in
                        Text(formatTokens(row.tokens))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn(store.t("dashboard.cost"), value: \.cost) { row in
                        Text(MoneyFormatter.compactUSD(Decimal(row.cost)))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 80, ideal: 96)
                    TableColumn(store.t("dashboard.time"), value: \.timestamp) { row in
                        Text(row.timestamp.formatted(date: .numeric, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 130, ideal: 150)
                }
                .frame(height: 320)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let selectedRow {
                    HStack(spacing: 14) {
                        HStack(spacing: 7) {
                            ModelIconView(modelName: selectedRow.model, provider: selectedRow.providerKind, size: 18)
                            Text(selectedRow.model)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatTokens(selectedRow.tokens))
                        Text("\(formatTokens(selectedRow.cachedTokens)) \(store.t("dashboard.cached_tokens"))")
                        Text("\(formatTokens(selectedRow.reasoningTokens)) \(store.t("dashboard.reasoning_tokens"))")
                        Text(MoneyFormatter.compactUSD(Decimal(selectedRow.cost)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DashboardRecordTableRow: Identifiable {
    var id: UUID
    var timestamp: Date
    var providerKind: ProviderKind
    var provider: String
    var source: String
    var model: String
    var project: String
    var tokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var cost: Double
}

struct CodexActivityBand: View {
    @ObservedObject var store: AppStore
    @State private var summary = CodexActivitySummary.empty
    @State private var summaryVersion = -1

    private let metricColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: store.t("dashboard.codex_activity"),
                    subtitle: subtitle
                )
                Spacer()
                Button {
                    _ = store.syncCodexUsageHistory()
                    _ = store.syncCodexSessionQuotas()
                } label: {
                    Label(store.t("menu.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !summary.hasHistory {
                EmptyStateLine(text: store.t("dashboard.codex_no_history"))
            } else {
                LazyVGrid(columns: metricColumns, spacing: 10) {
                    compactMetric(store.t("dashboard.codex_total_tokens"), value: formatTokens(summary.totalObservedTokens), symbol: "sum")
                    compactMetric(store.t("dashboard.codex_peak_run"), value: formatTokens(summary.peakObservedTokens), symbol: "chart.bar.xaxis")
                    compactMetric(store.t("dashboard.codex_active_days"), value: "\(summary.activeDays)", symbol: "calendar.badge.clock")
                    compactMetric(store.t("dashboard.codex_reasoning_tokens"), value: formatTokens(summary.reasoningOutputTokens), symbol: "brain")
                    compactMetric(store.t("dashboard.codex_cached_tokens"), value: formatTokens(summary.cachedInputTokens), symbol: "bolt.horizontal.circle")
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("dashboard.codex_daily_trend"))
                            .font(.subheadline.weight(.medium))
                        let values = summary.dailyTokenSeries.map { Decimal($0.tokens) }
                        SparklineView(values: values, tint: .orange)
                            .frame(height: 92)
                        MicroBarView(values: values)
                            .frame(height: 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("dashboard.codex_model_mix"))
                            .font(.subheadline.weight(.medium))
                        let models = summary.modelUsage
                        let maxTokens = max(models.map(\.tokens).max() ?? 0, 1)
                        ForEach(models) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(row.model)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(formatTokens(row.tokens)) · \(row.runs) \(store.t("dashboard.codex_runs"))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                SpendProgressBar(value: Decimal(row.tokens), maxValue: Decimal(maxTokens), tint: .orange)
                            }
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            rebuildSummaryIfNeeded()
        }
        .onChange(of: store.recordsVersion) {
            rebuildSummaryIfNeeded()
        }
    }

    private func rebuildSummaryIfNeeded() {
        guard summaryVersion != store.recordsVersion else { return }
        summary = store.codexActivitySummary(days: 35, modelLimit: 5)
        summaryVersion = store.recordsVersion
    }

    private var subtitle: String {
        guard let result = store.lastCodexHistoryImportResult else {
            return store.t("dashboard.codex_activity_subtitle")
        }
        return "\(store.t("dashboard.codex_activity_subtitle")) · \(store.t("dashboard.codex_history_files")) \(result.filesScanned)"
    }

    private func compactMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 100_000_000 {
            return String(format: "%.1fB tok", Double(tokens) / 1_000_000_000)
        }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM tok", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk tok", Double(tokens) / 1_000)
        }
        return "\(tokens) tok"
    }
}

struct SubscriptionDashboardBand: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    title: store.t("subscription.title"),
                    subtitle: "\(store.t("subscription.monthly_fees")) \(MoneyFormatter.usd(store.monthlySubscriptionFeesUSD))"
                )
                Spacer()
                Text("\(store.t("subscription.allocated")) \(MoneyFormatter.usd(store.subscriptionAllocatedCostToDateUSD))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if store.subscriptionSummaries.isEmpty {
                if store.subscriptionMonitorSummaries.isEmpty {
                    EmptyStateLine(text: store.t("subscription.empty"))
                } else {
                    subscriptionMonitorRows
                }
            } else {
                subscriptionMonitorRows
                ForEach(store.subscriptionSummaries.prefix(4)) { summary in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.plan.name)
                                    .font(.subheadline.weight(.medium))
                                Text(subscriptionSubtitle(summary))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.percent(summary.utilization))
                                .font(.subheadline.monospacedDigit())
                        }
                        SpendProgressBar(value: summary.usedUnits, maxValue: summary.plan.includedUnits, tint: summary.utilization >= Decimal(string: "0.9")! ? .orange : .blue)
                        HStack {
                            Text("\(store.t("subscription.remaining")) \(formatUnits(summary.remainingUnits, unit: summary.plan.quotaUnit))")
                            Spacer()
                            Text("\(store.t("subscription.projected")) \(formatUnits(summary.projectedUnits, unit: summary.plan.quotaUnit))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subscriptionMonitorRows: some View {
        ForEach(store.subscriptionMonitorSummaries.prefix(4)) { summary in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.target.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(summary.target.provider?.displayName ?? store.t("subscription.any_provider")) · \(MoneyFormatter.usd(summary.target.monthlyBudgetUSD)) / \(store.t("monitoring.per_month"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.t("monitoring.fixed_subscription_fee"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !summary.quotaWindowSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(summary.quotaWindowSummaries.prefix(2))) { quota in
                            QuotaRunwayView(
                                summary: quota,
                                quotaLabel: store.t("quota.quota_remaining"),
                                timeLabel: store.t("quota.time_remaining"),
                                paceLabel: store.t("quota.pace"),
                                refreshLabel: store.t("quota.refresh_countdown"),
                                elapsedLabel: store.t("quota.window_elapsed"),
                                remainingText: quotaRemainingValueText(quota),
                                refreshText: quotaRefreshText(quota),
                                tint: quotaTint(quota)
                            )
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func subscriptionSubtitle(_ summary: SubscriptionSummary) -> String {
        let provider = summary.plan.provider?.displayName ?? store.t("subscription.any_provider")
        let model = summary.plan.modelPattern.isEmpty ? store.t("subscription.all_models") : summary.plan.modelPattern
        return "\(provider) · \(model) · \(MoneyFormatter.usd(summary.plan.monthlyFeeUSD))"
    }

    private func quotaRemainingValueText(_ summary: QuotaWindowSummary) -> String {
        if summary.isProviderReported {
            return MoneyFormatter.percent(summary.remainingRatio)
        }
        return formatUnits(summary.remainingUnits, unit: summary.window.quotaUnit)
    }

    private func quotaRefreshText(_ summary: QuotaWindowSummary) -> String {
        if summary.remainingSeconds <= 60 {
            return store.t("quota.refresh_soon")
        }
        return "\(compactDuration(summary.remainingSeconds)) \(store.t("quota.until_refresh"))"
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
        return summary.utilization >= Decimal(string: "0.9")! ? .orange : .blue
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
            return MoneyFormatter.usd(units)
        }
    }
}

struct DashboardVisualBand: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: store.t("menu.burn_rate"), subtitle: "\(MoneyFormatter.usd(store.summary.burnRatePerDayUSD)) / \(store.t("dashboard.per_day"))")
                SparklineView(values: store.dailySpendSeries(days: 21).map(\.spend), tint: .cyan)
                    .frame(height: 96)
                MicroBarView(values: store.dailySpendSeries(days: 21).map(\.spend))
                    .frame(height: 22)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: store.t("nav.providers"), subtitle: store.t("dashboard.current_month"))
                if store.providerSpendDistribution().isEmpty {
                    EmptyStateLine(text: store.t("dashboard.no_usage"))
                } else {
                    ProviderDistributionBar(rows: store.providerSpendDistribution(limit: 7))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusBanner: View {
    var title: String
    var message: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TrackedModelTable: View {
    var rows: [(model: TrackedModel, spend: Decimal, tokens: Int, lastSeen: Date?)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.model.id) { row in
                HStack(spacing: 12) {
                    Text("#\(row.model.rank)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)
                    ProviderIconView(provider: row.model.provider, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.model.displayName)
                            .font(.subheadline.weight(.medium))
                        Text(row.model.provider.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(row.model.score)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(row.tokens == 0 ? "No calls" : "\(row.tokens) tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.tokens == 0 ? .secondary : .primary)
                        .frame(width: 110, alignment: .trailing)
                    Text(MoneyFormatter.compactUSD(row.spend))
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 74, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.top, 9)
                SpendProgressBar(value: row.spend, maxValue: rows.map(\.spend).max() ?? 0, tint: row.tokens == 0 ? .secondary : .cyan)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 7)
                    .padding(.top, -2)
                Divider()
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ModelRankingView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: store.t("dashboard.model_spend"), subtitle: store.t("dashboard.current_month"))
            let models = store.spendByModel()
            if models.isEmpty {
                EmptyStateLine(text: store.t("dashboard.no_usage"))
            } else {
                let maxSpend = models.map(\.spend).max() ?? 0
                ForEach(models, id: \.model) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            ModelIconView(modelName: row.model, provider: row.provider, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.model)
                                    .lineLimit(1)
                                Text(row.provider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.compactUSD(row.spend))
                                .monospacedDigit()
                        }
                        SpendProgressBar(value: row.spend, maxValue: maxSpend, tint: .teal)
                    }
                    Divider()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SpikeListView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: store.t("dashboard.spikes"), subtitle: store.t("dashboard.spikes_subtitle"))
            let spikes = store.recentSpikeRecords()
            if spikes.isEmpty {
                EmptyStateLine(text: store.t("dashboard.no_spikes"))
            } else {
                ForEach(spikes) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.model)
                                .lineLimit(1)
                            Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(MoneyFormatter.compactUSD(record.costUSD))
                            .monospacedDigit()
                    }
                    Divider()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RecentUsageView: View {
    @ObservedObject var store: AppStore
    var records: [UsageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: store.t("dashboard.recent_usage"), subtitle: store.t("dashboard.recent_usage_subtitle"))
            if records.isEmpty {
                EmptyStateLine(text: store.t("dashboard.connect_hint"))
            } else {
                ForEach(records) { record in
                    HStack {
                        HStack(spacing: 7) {
                            ProviderIconView(provider: record.provider, size: 20)
                            Text(record.provider.displayName)
                                .lineLimit(1)
                        }
                        .frame(width: 150, alignment: .leading)
                        Text(record.model)
                            .lineLimit(1)
                        Spacer()
                        Text("\(record.totalTokens) tok")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Text(MoneyFormatter.compactUSD(record.costUSD))
                            .monospacedDigit()
                            .frame(width: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateLine: View {
    var text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
