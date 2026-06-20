import SwiftUI
import TokenRadarCore

struct MonitoringView: View {
    @ObservedObject var store: AppStore
    @State private var isAddingMonitor = false
    @State private var draftProvider: ProviderKind = .openAI
    @State private var draftAccountKind: MonitorAccountKind = .subscriptionUser
    @State private var isShowingDataSourceDetails = false
    @State private var isShowingAdvancedMonitors = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                unifiedDashboard
                dataSourceDetailsSection

                if !store.settings.monitorTargets.isEmpty {
                    advancedMonitorSection
                }
            }
            .padding(24)
        }
        .background(.background)
        .sheet(isPresented: $isAddingMonitor) {
            AddMonitorWizard(
                store: store,
                initialProvider: draftProvider,
                initialAccountKind: draftAccountKind
            )
        }
    }

    private var unifiedDashboard: some View {
        UnifiedMonitoringDashboard(
            store: store,
            sources: dashboardSources,
            modelRows: dashboardModelRows,
            quickSources: quickSources,
            onRefresh: {
                Task {
                    await store.refreshAllProviders()
                }
            },
            onSourceAction: handleDashboardSourceAction,
            onQuickSource: handleQuickSourceAction
        )
    }

    private var connectionCenter: some View {
        ConnectionCenterPanel(
            store: store,
            codexSourceAvailable: codexSourceAvailable,
            claudeCodeSourceAvailable: claudeCodeSourceAvailable,
            openAddMonitor: openAddMonitor
        )
    }

    private var dataSourceDetailsSection: some View {
        DisclosureGroup(isExpanded: $isShowingDataSourceDetails) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], spacing: 12) {
                DataSourceDetailCard(
                    store: store,
                    title: store.t("monitoring.connection_codex"),
                    status: codexDetailStatus,
                    coverage: store.t("monitoring.coverage_local_device_only"),
                    source: "~/.codex/sessions",
                    lastData: latestDataText(for: store.monitoringAnalytics.codex.latest),
                    syncSummary: codexSyncSummary,
                    records: store.monitoringAnalytics.codex.records,
                    tokens: store.monitoringAnalytics.codex.tokens,
                    spend: store.monitoringAnalytics.codex.spend,
                    appIcon: .codex,
                    symbol: "terminal",
                    tint: codexSourceAvailable ? .green : .secondary
                )

                DataSourceDetailCard(
                    store: store,
                    title: store.t("monitoring.connection_claude"),
                    status: claudeCodeDetailStatus,
                    coverage: store.t("monitoring.coverage_local_device_only"),
                    source: "~/.claude/projects",
                    lastData: latestDataText(for: store.monitoringAnalytics.claudeCode.latest),
                    syncSummary: claudeCodeSyncSummary,
                    records: store.monitoringAnalytics.claudeCode.records,
                    tokens: store.monitoringAnalytics.claudeCode.tokens,
                    spend: store.monitoringAnalytics.claudeCode.spend,
                    appIcon: .claudeCode,
                    symbol: "curlybraces.square",
                    tint: claudeCodeSourceAvailable ? .purple : .secondary
                )

                DataSourceDetailCard(
                    store: store,
                    title: store.t("monitoring.connection_openai_api"),
                    status: openAIDetailStatus,
                    coverage: store.t("monitoring.coverage_exact_remote"),
                    source: ProviderKind.openAI.defaultBaseURL?.absoluteString ?? "OpenAI API",
                    lastData: latestProviderSyncText(.openAI),
                    syncSummary: providerSyncSummary(.openAI),
                    records: openAIProviderAggregate.records,
                    tokens: openAIProviderAggregate.tokens,
                    spend: openAIProviderAggregate.spend,
                    provider: .openAI,
                    symbol: "server.rack",
                    tint: store.credentialState[.openAI] == true ? .cyan : .secondary
                )

                DataSourceDetailCard(
                    store: store,
                    title: store.t("monitoring.connection_proxy"),
                    status: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                    coverage: store.t("monitoring.coverage_local_device_only"),
                    source: "http://localhost:\(store.settings.proxyPort)",
                    lastData: latestDataText(for: store.monitoringAnalytics.localProxy.latest),
                    syncSummary: store.proxyLiveTestResult?.detail.isEmpty == false ? store.proxyLiveTestResult!.detail : store.settings.defaultProxyProvider.displayName,
                    records: store.monitoringAnalytics.localProxy.records,
                    tokens: store.monitoringAnalytics.localProxy.tokens,
                    spend: store.monitoringAnalytics.localProxy.spend,
                    provider: store.settings.defaultProxyProvider,
                    symbol: "point.3.connected.trianglepath.dotted",
                    tint: store.isProxyRunning ? .green : .secondary
                )
            }
            .padding(.top, 12)
        } label: {
            SectionHeader(
                title: store.t("monitoring.source_details_title"),
                subtitle: store.t("monitoring.source_details_subtitle")
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t("monitoring.title"))
                    .font(.system(size: 26, weight: .semibold))
                Text(store.t("monitoring.subtitle"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.settings.monitorTargets.contains(where: \.isDemo) {
                Button {
                    store.removeDemoData()
                } label: {
                    Label(store.t("monitoring.remove_demo"), systemImage: "eraser")
                }
            }
            Button {
                openAddMonitor(provider: .openAI, accountKind: .subscriptionUser)
            } label: {
                Label(store.t("monitoring.add_data_source"), systemImage: "plus.circle")
            }
        }
    }

    private var advancedMonitorSection: some View {
        DisclosureGroup(isExpanded: $isShowingAdvancedMonitors) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.monitorTargetSummaries) { summary in
                    MonitorSummaryCard(
                        summary: summary,
                        store: store,
                        onToggle: { isEnabled in
                            store.updateMonitorTarget(summary.target.id) { $0.isEnabled = isEnabled }
                        },
                        onDelete: {
                            store.deleteMonitorTarget(id: summary.target.id)
                        }
                    )
                }
            }
            .padding(.top, 12)
        } label: {
            SectionHeader(
                title: store.t("monitoring.advanced_monitors_title"),
                subtitle: store.t("monitoring.advanced_monitors_subtitle")
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var monitoringSummaryStrip: some View {
        HStack(spacing: 12) {
            MonitoringStripMetric(
                title: store.t("sidebar.monitors"),
                value: "\(store.settings.monitorTargets.filter(\.isEnabled).count)/\(store.settings.monitorTargets.count)",
                symbol: "scope",
                tint: .orange
            )
            MonitoringStripMetric(
                title: store.t("dashboard.fixed_cost"),
                value: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD),
                symbol: "creditcard",
                tint: .blue
            )
            MonitoringStripMetric(
                title: store.t("dashboard.observed_tokens"),
                value: formatTokens(store.records.reduce(0) { $0 + $1.observedTokens }),
                symbol: "number",
                tint: .green
            )
            MonitoringStripMetric(
                title: store.t("nav.proxy"),
                value: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                symbol: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle",
                tint: store.isProxyRunning ? .green : .secondary
            )
        }
    }

    private var detectedSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: store.t("monitoring.detected_sources"),
                subtitle: store.t("monitoring.detected_sources_subtitle")
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                DetectedSourceCard(
                    title: store.t("monitoring.codex_source_title"),
                    subtitle: codexSourceDetail,
                    status: discoveredStatus(
                        isBound: store.hasCodexMonitorTarget,
                        isAvailable: codexSourceAvailable
                    ),
                    appIcon: .codex,
                    symbol: "terminal",
                    tint: .green,
                    primaryActionTitle: store.hasCodexMonitorTarget
                        ? store.t("quota.sync_codex")
                        : store.t("monitoring.source_create_monitor"),
                    primaryActionSymbol: store.hasCodexMonitorTarget
                        ? "arrow.triangle.2.circlepath"
                        : "plus.circle",
                    isPrimaryDisabled: !store.hasCodexMonitorTarget && !codexSourceAvailable
                ) {
                    if store.hasCodexMonitorTarget {
                        store.syncCodexSessionQuotas()
                    } else {
                        store.createCodexMonitorTargetFromDiscovery()
                        store.syncCodexUsageHistory()
                        store.syncCodexSessionQuotas()
                    }
                }

                DetectedSourceCard(
                    title: store.t("monitoring.claude_code_source_title"),
                    subtitle: store.t("monitoring.claude_code_source_detail"),
                    status: discoveredStatus(
                        isBound: store.hasClaudeCodeMonitorTarget,
                        isAvailable: claudeCodeSourceAvailable
                    ),
                    appIcon: .claudeCode,
                    symbol: "curlybraces.square",
                    tint: .purple,
                    primaryActionTitle: store.hasClaudeCodeMonitorTarget
                        ? store.t("auth.import_sessions")
                        : store.t("monitoring.source_create_monitor"),
                    primaryActionSymbol: store.hasClaudeCodeMonitorTarget
                        ? "square.and.arrow.down"
                        : "plus.circle",
                    isPrimaryDisabled: !store.hasClaudeCodeMonitorTarget && !claudeCodeSourceAvailable
                ) {
                    if !store.hasClaudeCodeMonitorTarget {
                        store.createClaudeCodeMonitorTargetFromDiscovery()
                    }
                    store.syncLocalSessionLogs()
                }

                DetectedSourceCard(
                    title: store.t("monitoring.proxy_source_title"),
                    subtitle: store.t("monitoring.proxy_source_detail"),
                    status: store.isProxyRunning
                        ? store.t("proxy.running")
                        : store.t("proxy.paused"),
                    symbol: "point.3.connected.trianglepath.dotted",
                    tint: .orange,
                    primaryActionTitle: store.isProxyRunning
                        ? store.t("menu.pause_proxy")
                        : store.t("menu.start_proxy"),
                    primaryActionSymbol: store.isProxyRunning ? "pause.circle" : "play.circle",
                    isPrimaryDisabled: false
                ) {
                    if store.isProxyRunning {
                        store.stopProxy()
                    } else {
                        store.startProxy()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("monitoring.empty_title"), systemImage: "scope")
                .font(.title3.weight(.semibold))
            Text(store.t("monitoring.empty"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                MonitorOnboardingChoiceCard(
                    title: store.t("monitoring.quick_openai_subscription"),
                    subtitle: store.t("monitoring.quick_openai_subscription_subtitle"),
                    symbol: "person.crop.circle.badge.checkmark",
                    tint: .orange
                ) {
                    openAddMonitor(provider: .openAI, accountKind: .subscriptionUser)
                }

                MonitorOnboardingChoiceCard(
                    title: store.t("monitoring.quick_openai_api"),
                    subtitle: store.t("monitoring.quick_openai_api_subtitle"),
                    symbol: "key.viewfinder",
                    tint: .cyan
                ) {
                    openAddMonitor(provider: .openAI, accountKind: .apiUser)
                }
            }

            HStack {
                Button {
                    openAddMonitor(provider: .openAI, accountKind: .subscriptionUser)
                } label: {
                    Label(store.t("monitoring.add_generic"), systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    store.removeDemoData()
                } label: {
                    Label(store.t("monitoring.remove_demo"), systemImage: "eraser")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func openAddMonitor(provider: ProviderKind, accountKind: MonitorAccountKind) {
        draftProvider = provider
        draftAccountKind = accountKind
        isAddingMonitor = true
    }

    private func handleDashboardSourceAction(_ id: String) {
        switch id {
        case "codex":
            if !store.hasCodexMonitorTarget {
                store.createCodexMonitorTargetFromDiscovery()
            }
            store.syncCodexUsageHistory()
            store.syncCodexSessionQuotas()
        case "claude-code":
            if !store.hasClaudeCodeMonitorTarget {
                store.createClaudeCodeMonitorTargetFromDiscovery()
            }
            store.syncLocalSessionLogs()
        case "local-proxy":
            if store.isProxyRunning {
                store.stopProxy()
            } else {
                store.startProxy()
            }
        default:
            if let provider = providerFromDashboardID(id) {
                if store.credentialState[provider] == true, provider.supportsProviderBillingAPI {
                    Task {
                        await store.testProviderConnection(provider)
                    }
                } else {
                    openAddMonitor(provider: provider, accountKind: .apiUser)
                }
            }
        }
    }

    private func handleQuickSourceAction(_ id: String) {
        switch id {
        case "codex", "claude-code", "local-proxy":
            handleDashboardSourceAction(id)
        case "chatgpt-subscription":
            openAddMonitor(provider: .openAI, accountKind: .subscriptionUser)
        case "claude-subscription":
            openAddMonitor(provider: .anthropic, accountKind: .subscriptionUser)
        default:
            if let provider = providerFromDashboardID(id) {
                openAddMonitor(provider: provider, accountKind: .apiUser)
            }
        }
    }

    private func providerFromDashboardID(_ id: String) -> ProviderKind? {
        let prefix = "provider-"
        guard id.hasPrefix(prefix) else { return nil }
        return ProviderKind(rawValue: String(id.dropFirst(prefix.count)))
    }

    private var codexSourceAvailable: Bool {
        store.codexLocalDiscovery.isDetected ||
            !(store.lastCodexQuotaSyncResult?.snapshots.isEmpty ?? true) ||
            (store.lastCodexHistoryImportResult?.filesScanned ?? 0) > 0
    }

    private var claudeCodeSourceAvailable: Bool {
        store.claudeCodeLocalLogsDetected ||
            (store.lastSessionImportResult?.filesScanned ?? 0) > 0
    }

    private var openAIProviderAggregate: MonitoringUsageAggregate {
        store.monitoringAnalytics.providerUsage[.openAI] ?? .empty
    }

    private var dashboardSources: [MonitoringDashboardSource] {
        [
            MonitoringDashboardSource(
                id: "codex",
                title: store.t("monitoring.connection_codex"),
                subtitle: store.t("monitoring.coverage_local_device_only"),
                status: codexDetailStatus,
                records: store.monitoringAnalytics.codex.records,
                tokens: store.monitoringAnalytics.codex.tokens,
                spend: store.monitoringAnalytics.codex.spend,
                lastData: latestDataText(for: store.monitoringAnalytics.codex.latest),
                appIcon: .codex,
                provider: nil,
                symbol: "terminal",
                tint: codexSourceAvailable ? .green : .secondary,
                actionTitle: store.hasCodexMonitorTarget ? store.t("quota.sync_codex") : store.t("monitoring.source_create_monitor"),
                actionSymbol: store.hasCodexMonitorTarget ? "arrow.triangle.2.circlepath" : "plus.circle",
                isActionDisabled: !store.hasCodexMonitorTarget && !codexSourceAvailable
            ),
            MonitoringDashboardSource(
                id: "claude-code",
                title: store.t("monitoring.connection_claude"),
                subtitle: store.t("monitoring.coverage_local_device_only"),
                status: claudeCodeDetailStatus,
                records: store.monitoringAnalytics.claudeCode.records,
                tokens: store.monitoringAnalytics.claudeCode.tokens,
                spend: store.monitoringAnalytics.claudeCode.spend,
                lastData: latestDataText(for: store.monitoringAnalytics.claudeCode.latest),
                appIcon: .claudeCode,
                provider: nil,
                symbol: "curlybraces.square",
                tint: claudeCodeSourceAvailable ? .purple : .secondary,
                actionTitle: store.hasClaudeCodeMonitorTarget ? store.t("auth.import_sessions") : store.t("monitoring.source_create_monitor"),
                actionSymbol: store.hasClaudeCodeMonitorTarget ? "square.and.arrow.down" : "plus.circle",
                isActionDisabled: !store.hasClaudeCodeMonitorTarget && !claudeCodeSourceAvailable
            ),
            MonitoringDashboardSource(
                id: "local-proxy",
                title: store.t("monitoring.connection_proxy"),
                subtitle: "http://localhost:\(store.settings.proxyPort)",
                status: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                records: store.monitoringAnalytics.localProxy.records,
                tokens: store.monitoringAnalytics.localProxy.tokens,
                spend: store.monitoringAnalytics.localProxy.spend,
                lastData: latestDataText(for: store.monitoringAnalytics.localProxy.latest),
                appIcon: nil,
                provider: store.settings.defaultProxyProvider,
                symbol: "point.3.connected.trianglepath.dotted",
                tint: store.isProxyRunning ? .green : .orange,
                actionTitle: store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"),
                actionSymbol: store.isProxyRunning ? "pause.circle" : "play.circle",
                isActionDisabled: false
            )
        ] + configuredProviderDashboardSources
    }

    private var configuredProviderDashboardSources: [MonitoringDashboardSource] {
        quickProviderKinds.compactMap { provider in
            let aggregate = store.monitoringAnalytics.providerUsage[provider] ?? .empty
            guard providerHasMonitor(provider) || store.credentialState[provider] == true || aggregate.records > 0 else {
                return nil
            }

            let isConfigured = providerHasMonitor(provider) || store.credentialState[provider] == true
            let canTest = store.credentialState[provider] == true && provider.supportsProviderBillingAPI
            return MonitoringDashboardSource(
                id: "provider-\(provider.rawValue)",
                title: provider.displayName,
                subtitle: provider.supportsProviderBillingAPI
                    ? store.t("monitoring.coverage_exact_remote")
                    : store.t("monitoring.dashboard_manual_or_proxy"),
                status: isConfigured ? store.t("monitoring.source_bound") : store.t("monitoring.source_available"),
                records: aggregate.records,
                tokens: aggregate.tokens,
                spend: aggregate.spend,
                lastData: latestDataText(for: aggregate.latest),
                appIcon: nil,
                provider: provider,
                symbol: "server.rack",
                tint: isConfigured ? .green : .cyan,
                actionTitle: canTest ? store.t("live_test.test_connection") : store.t("monitoring.add"),
                actionSymbol: canTest ? "bolt.horizontal.circle" : "plus.circle",
                isActionDisabled: false
            )
        }
    }

    private var quickProviderKinds: [ProviderKind] {
        [.openAI, .openRouter, .siliconFlow, .deepSeek, .zhipuGLM]
    }

    private var dashboardModelRows: [MonitoringModelUsageRow] {
        store.monitoringAnalytics.modelRows
    }

    private var quickSources: [MonitoringQuickSource] {
        [
            MonitoringQuickSource(
                id: "codex",
                title: store.t("monitoring.connection_codex"),
                subtitle: store.t("monitoring.dashboard_auto_local"),
                provider: nil,
                appIcon: .codex,
                accountKind: .subscriptionUser,
                symbol: "terminal",
                tint: .green,
                badge: store.t("monitoring.dashboard_auto"),
                actionTitle: store.hasCodexMonitorTarget ? store.t("quota.sync_codex") : store.t("monitoring.source_create_monitor"),
                isConfigured: store.hasCodexMonitorTarget
            ),
            MonitoringQuickSource(
                id: "claude-code",
                title: store.t("monitoring.connection_claude"),
                subtitle: store.t("monitoring.dashboard_auto_local"),
                provider: nil,
                appIcon: .claudeCode,
                accountKind: .subscriptionUser,
                symbol: "curlybraces.square",
                tint: .purple,
                badge: store.t("monitoring.dashboard_auto"),
                actionTitle: store.hasClaudeCodeMonitorTarget ? store.t("auth.import_sessions") : store.t("monitoring.source_create_monitor"),
                isConfigured: store.hasClaudeCodeMonitorTarget
            ),
            MonitoringQuickSource(
                id: "local-proxy",
                title: store.t("monitoring.dashboard_realtime_proxy"),
                subtitle: store.t("monitoring.dashboard_realtime_proxy_detail"),
                provider: store.settings.defaultProxyProvider,
                appIcon: nil,
                accountKind: .apiUser,
                symbol: "point.3.connected.trianglepath.dotted",
                tint: store.isProxyRunning ? .green : .orange,
                badge: store.t("monitoring.coverage_local_device_only"),
                actionTitle: store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"),
                isConfigured: store.isProxyRunning
            ),
            quickProviderSource(.openAI)
        ]
    }

    private func quickProviderSource(_ provider: ProviderKind) -> MonitoringQuickSource {
        let isConfigured = providerHasMonitor(provider) || store.credentialState[provider] == true
        return MonitoringQuickSource(
            id: "provider-\(provider.rawValue)",
            title: provider.displayName,
            subtitle: provider.supportsProviderBillingAPI
                ? store.t("monitoring.dashboard_api_source")
                : store.t("monitoring.dashboard_package_source"),
            provider: provider,
            appIcon: nil,
            accountKind: .apiUser,
            symbol: "server.rack",
            tint: provider.supportsProviderBillingAPI ? .cyan : .secondary,
            badge: store.t("monitoring.dashboard_api_package"),
            actionTitle: isConfigured ? store.t("monitoring.source_bound") : store.t("monitoring.add"),
            isConfigured: isConfigured
        )
    }

    private func providerHasMonitor(_ provider: ProviderKind) -> Bool {
        store.settings.monitorTargets.contains { target in
            target.provider == provider &&
                !store.isCodexMonitorTarget(target) &&
                !store.isClaudeCodeMonitorTarget(target)
        }
    }

    private var codexDetailStatus: String {
        if store.hasCodexMonitorTarget {
            return store.t("monitoring.source_bound")
        }
        return codexSourceAvailable ? store.t("monitoring.source_available") : store.t("monitoring.source_not_found")
    }

    private var claudeCodeDetailStatus: String {
        if store.hasClaudeCodeMonitorTarget {
            return store.t("monitoring.source_bound")
        }
        return claudeCodeSourceAvailable ? store.t("monitoring.source_available") : store.t("monitoring.source_not_found")
    }

    private var openAIDetailStatus: String {
        store.credentialState[.openAI] == true ? store.t("providers.credential_saved") : store.t("providers.no_credential")
    }

    private var codexSyncSummary: String {
        let quota = store.lastCodexQuotaSyncResult
        let history = store.lastCodexHistoryImportResult
        if quota == nil, history == nil {
            return store.t("monitoring.sync_not_run")
        }

        var parts: [String] = []
        if let quota {
            parts.append("\(quota.filesScanned) JSONL")
            parts.append("\(quota.snapshots.count) \(store.t("monitoring.source_snapshots"))")
            if !quota.errors.isEmpty {
                parts.append("\(quota.errors.count) \(store.t("monitoring.sync_errors"))")
            }
        }
        if let history {
            parts.append("\(history.imported) \(store.t("monitoring.sync_imported"))")
            parts.append("\(history.skipped + history.filesSkipped) \(store.t("monitoring.sync_skipped"))")
            if !history.errors.isEmpty {
                parts.append("\(history.errors.count) \(store.t("monitoring.sync_errors"))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var claudeCodeSyncSummary: String {
        guard let result = store.lastSessionImportResult else {
            return store.t("monitoring.sync_not_run")
        }
        var parts = [
            "\(result.filesScanned) JSONL",
            "\(result.imported) \(store.t("monitoring.sync_imported"))",
            "\(result.skipped) \(store.t("monitoring.sync_skipped"))"
        ]
        if !result.errors.isEmpty {
            parts.append("\(result.errors.count) \(store.t("monitoring.sync_errors"))")
        }
        return parts.joined(separator: " · ")
    }

    private func latestProviderSyncText(_ provider: ProviderKind) -> String {
        if let fetchedAt = store.snapshots[provider]?.fetchedAt {
            return formatDateTime(fetchedAt)
        }
        if let testAt = store.providerLiveTestResults[provider]?.timestamp {
            return formatDateTime(testAt)
        }
        return latestDataText(for: store.monitoringAnalytics.providerUsage[provider]?.latest)
    }

    private func providerSyncSummary(_ provider: ProviderKind) -> String {
        if let snapshot = store.snapshots[provider] {
            return "\(MoneyFormatter.usd(snapshot.spendUSD)) · \(snapshot.requestCount) \(store.t("monitoring.requests")) · \(snapshot.quotaConfidence.displayName)"
        }
        if let result = store.providerLiveTestResults[provider] {
            return result.detail.isEmpty ? result.message : result.detail
        }
        return store.t("monitoring.sync_not_run")
    }

    private func latestDataText(for date: Date?) -> String {
        guard let date else {
            return store.t("monitoring.no_records")
        }
        return formatDateTime(date)
    }

    private func formatDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var codexSourceDetail: String {
        let snapshotCount = store.lastCodexQuotaSyncResult?.snapshots.count ?? 0
        if snapshotCount > 0 {
            return "\(store.t("monitoring.codex_source_detail")) · \(snapshotCount) \(store.t("monitoring.source_snapshots"))"
        }
        if store.codexLocalDiscovery.sessionFilesExist {
            return "\(store.t("monitoring.codex_source_detail")) · \(store.t("monitoring.source_sessions_found"))"
        }
        if store.codexLocalDiscovery.authFileExists {
            return "\(store.t("monitoring.codex_source_detail")) · \(store.t("monitoring.source_auth_found"))"
        }
        if store.codexLocalDiscovery.cliURL != nil {
            return "\(store.t("monitoring.codex_source_detail")) · CLI"
        }
        return store.t("monitoring.codex_source_detail")
    }

    private func discoveredStatus(isBound: Bool, isAvailable: Bool) -> String {
        if isBound {
            return store.t("monitoring.source_bound")
        }
        return isAvailable ? store.t("monitoring.source_available") : store.t("monitoring.source_not_found")
    }
}

private struct ConnectionCenterPanel: View {
    @ObservedObject var store: AppStore
    var codexSourceAvailable: Bool
    var claudeCodeSourceAvailable: Bool
    var openAddMonitor: (ProviderKind, MonitorAccountKind) -> Void

    private var codexQuotaSynced: Bool {
        store.settings.monitorTargets.contains { target in
            store.isCodexMonitorTarget(target) && store.hasCodexSessionQuota(target)
        }
    }

    private var hasOpenAICredential: Bool {
        store.credentialState[.openAI] == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(store.t("monitoring.connection_title"), systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(.headline)
                    Text(store.t("monitoring.connection_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Button {
                    Task {
                        await store.refreshAllProviders()
                    }
                } label: {
                    Label(store.t("menu.refresh"), systemImage: "arrow.clockwise")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ConnectionStatusItem(
                    title: store.t("monitoring.connection_codex"),
                    value: codexStatus,
                    detail: codexDetail,
                    appIcon: .codex,
                    symbol: "terminal",
                    tint: codexQuotaSynced ? .green : (codexSourceAvailable ? .orange : .secondary),
                    actionTitle: store.hasCodexMonitorTarget ? store.t("quota.sync_codex") : store.t("monitoring.source_create_monitor"),
                    actionSymbol: store.hasCodexMonitorTarget ? "arrow.triangle.2.circlepath" : "plus.circle",
                    isActionDisabled: !store.hasCodexMonitorTarget && !codexSourceAvailable,
                    action: syncOrCreateCodex
                )

                ConnectionStatusItem(
                    title: store.t("monitoring.connection_claude"),
                    value: claudeCodeStatus,
                    detail: store.t("monitoring.coverage_local_device_only"),
                    appIcon: .claudeCode,
                    symbol: "curlybraces.square",
                    tint: store.hasClaudeCodeMonitorTarget ? .green : (claudeCodeSourceAvailable ? .purple : .secondary),
                    actionTitle: store.hasClaudeCodeMonitorTarget ? store.t("auth.import_sessions") : store.t("monitoring.source_create_monitor"),
                    actionSymbol: store.hasClaudeCodeMonitorTarget ? "square.and.arrow.down" : "plus.circle",
                    isActionDisabled: !store.hasClaudeCodeMonitorTarget && !claudeCodeSourceAvailable,
                    action: syncOrCreateClaudeCode
                )

                ConnectionStatusItem(
                    title: store.t("monitoring.connection_openai_api"),
                    value: hasOpenAICredential ? store.t("monitoring.connection_key_saved") : store.t("monitoring.connection_key_missing"),
                    detail: store.t("monitoring.coverage_exact_remote"),
                    provider: .openAI,
                    symbol: hasOpenAICredential ? "key.fill" : "key",
                    tint: hasOpenAICredential ? .green : .cyan,
                    actionTitle: hasOpenAICredential ? store.t("live_test.test_connection") : store.t("monitoring.connection_action_add_api"),
                    actionSymbol: hasOpenAICredential ? "bolt.horizontal.circle" : "key.viewfinder",
                    isActionDisabled: false,
                    action: {
                        if hasOpenAICredential {
                            Task {
                                await store.testProviderConnection(.openAI)
                            }
                        } else {
                            openAddMonitor(.openAI, .apiUser)
                        }
                    }
                )

                ConnectionStatusItem(
                    title: store.t("monitoring.connection_proxy"),
                    value: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                    detail: store.t("monitoring.coverage_local_device_only"),
                    provider: store.settings.defaultProxyProvider,
                    symbol: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle",
                    tint: store.isProxyRunning ? .green : .secondary,
                    actionTitle: store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"),
                    actionSymbol: store.isProxyRunning ? "pause.circle" : "play.circle",
                    isActionDisabled: false,
                    action: {
                        if store.isProxyRunning {
                            store.stopProxy()
                        } else {
                            store.startProxy()
                        }
                    }
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var codexStatus: String {
        if codexQuotaSynced {
            return store.t("monitoring.status_codex_session_synced")
        }
        if store.hasCodexMonitorTarget {
            return store.t("monitoring.source_bound")
        }
        if codexSourceAvailable {
            return store.t("monitoring.source_available")
        }
        return store.t("monitoring.source_not_found")
    }

    private var codexDetail: String {
        let snapshotCount = store.lastCodexQuotaSyncResult?.snapshots.count ?? 0
        if snapshotCount > 0 {
            return "\(snapshotCount) \(store.t("monitoring.source_snapshots"))"
        }
        if store.codexLocalDiscovery.sessionFilesExist {
            return store.t("monitoring.source_sessions_found")
        }
        if store.codexLocalDiscovery.authFileExists {
            return store.t("monitoring.source_auth_found")
        }
        return store.t("monitoring.coverage_local_device_only")
    }

    private var claudeCodeStatus: String {
        if store.hasClaudeCodeMonitorTarget {
            return store.t("monitoring.source_bound")
        }
        if claudeCodeSourceAvailable {
            return store.t("monitoring.source_available")
        }
        return store.t("monitoring.source_not_found")
    }

    private func syncOrCreateCodex() {
        if !store.hasCodexMonitorTarget {
            store.createCodexMonitorTargetFromDiscovery()
        }
        store.syncCodexUsageHistory()
        store.syncCodexSessionQuotas()
    }

    private func syncOrCreateClaudeCode() {
        if !store.hasClaudeCodeMonitorTarget {
            store.createClaudeCodeMonitorTargetFromDiscovery()
        }
        store.syncLocalSessionLogs()
    }
}

private struct ConnectionStatusItem: View {
    var title: String
    var value: String
    var detail: String
    var appIcon: AppIconKind? = nil
    var provider: ProviderKind? = nil
    var symbol: String
    var tint: Color
    var actionTitle: String
    var actionSymbol: String
    var isActionDisabled: Bool
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                SourceIconView(
                    appIcon: appIcon,
                    provider: provider,
                    size: 24,
                    fallbackSystemImage: symbol,
                    fallbackTint: tint
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbol)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isActionDisabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DataSourceDetailCard: View {
    @ObservedObject var store: AppStore
    var title: String
    var status: String
    var coverage: String
    var source: String
    var lastData: String
    var syncSummary: String
    var records: Int
    var tokens: Int
    var spend: Decimal
    var appIcon: AppIconKind? = nil
    var provider: ProviderKind? = nil
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                SourceIconView(
                    appIcon: appIcon,
                    provider: provider,
                    size: 28,
                    fallbackSystemImage: symbol,
                    fallbackTint: tint
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(source)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                DetailMetric(title: store.t("monitoring.detail_records"), value: "\(records)")
                DetailMetric(title: store.t("monitoring.detail_tokens"), value: formatTokenCount(tokens))
                DetailMetric(title: store.t("monitoring.detail_spend"), value: MoneyFormatter.compactUSD(spend))
            }

            VStack(alignment: .leading, spacing: 6) {
                DetailLine(title: store.t("monitoring.detail_coverage"), value: coverage)
                DetailLine(title: store.t("monitoring.detail_last_data"), value: lastData)
                DetailLine(title: store.t("monitoring.detail_sync"), value: syncSummary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct DetailMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DetailLine: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct MonitoringStripMetric: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MonitorOnboardingChoiceCard: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct DetectedSourceCard: View {
    var title: String
    var subtitle: String
    var status: String
    var appIcon: AppIconKind? = nil
    var symbol: String
    var tint: Color
    var primaryActionTitle: String
    var primaryActionSymbol: String
    var isPrimaryDisabled: Bool
    var primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                SourceIconView(
                    appIcon: appIcon,
                    provider: nil,
                    size: 28,
                    fallbackSystemImage: symbol,
                    fallbackTint: tint
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.14))
                            .foregroundStyle(tint)
                            .clipShape(Capsule())
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: primaryAction) {
                Label(primaryActionTitle, systemImage: primaryActionSymbol)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(isPrimaryDisabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MonitorSummaryCard: View {
    var summary: MonitorTargetSummary
    @ObservedObject var store: AppStore
    var onToggle: (Bool) -> Void
    var onDelete: () -> Void

    private var target: MonitorTarget {
        summary.target
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(target.name)
                            .font(.headline)
                        Text(store.monitorAccountKindLabel(target.accountKind))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if target.accountKind == .subscriptionUser, target.provider == .openAI {
                    Button {
                        store.syncCodexSessionQuotas()
                    } label: {
                        Label(store.t("quota.sync_codex"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help(store.t("quota.sync_codex_help"))
                }

                Toggle(store.t("providers.enabled"), isOn: Binding(
                    get: { target.isEnabled },
                    set: onToggle
                ))
                .toggleStyle(.switch)

                if !isAutoDetectedLocalSubscription {
                    Button(role: .destructive, action: onDelete) {
                        Label(store.t("monitoring.delete"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help(store.t("monitoring.delete"))
                } else {
                    Label(store.t("monitoring.auto_detected"), systemImage: "sparkle.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            dataSourcesBlock

            if target.accountKind == .apiUser {
                SpendProgressBar(
                    value: summary.spendUSD,
                    maxValue: target.budgetLimitUSD,
                    tint: summary.utilization >= Decimal(string: "0.9")! ? .orange : .cyan
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .foregroundStyle(.blue)
                    Text(store.t("monitoring.fixed_subscription_fee"))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(store.t("monitoring.subscription_not_usage_budget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !summary.quotaWindowSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.quotaWindowSummaries.prefix(4)) { quotaSummary in
                        QuotaWindowSummaryRow(summary: quotaSummary, store: store)
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                Text("\(formatTokens(summary.tokenCount)) · \(summary.requestCount) \(store.t("monitoring.requests"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        let provider = target.provider?.displayName ?? store.t("subscription.any_provider")
        let model = target.modelPattern.isEmpty ? store.t("subscription.all_models") : target.modelPattern
        return "\(provider) · \(model) · \(store.monitorScopeLabel(target.scope))"
    }

    private var dataSourcesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.t("monitoring.data_sources"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(costLine)
                    .font(.subheadline.monospacedDigit())
            }

            MonitorDataSourceRow(
                title: primarySourceTitle,
                detail: primarySourceDetail,
                trailing: store.monitorCoverageLabel(target.coverage),
                appIcon: primarySourceAppIcon,
                symbol: coverageSymbol,
                tint: coverageColor
            )

            if target.usesLocalProxy && target.source != .localProxyDevice {
                MonitorDataSourceRow(
                    title: store.t("monitoring.proxy_source_title"),
                    detail: store.t("monitoring.local_proxy_boundary"),
                    trailing: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                    symbol: "point.3.connected.trianglepath.dotted",
                    tint: .orange
                )
            }

            if store.isCodexMonitorTarget(target) || store.hasCodexSessionQuota(target) {
                MonitorDataSourceRow(
                    title: store.t("monitoring.codex_source_title"),
                    detail: store.t("monitoring.subscription_codex_session_note"),
                    trailing: store.hasCodexSessionQuota(target)
                        ? store.t("monitoring.status_codex_session_synced")
                        : store.t("monitoring.status_codex_detected"),
                    appIcon: .codex,
                    symbol: "terminal",
                    tint: .green
                )
            }
        }
    }

    private var primarySourceTitle: String {
        if store.isClaudeCodeMonitorTarget(target) {
            return store.t("monitoring.claude_code_source_title")
        }
        return store.monitorSourceLabel(target.source)
    }

    private var primarySourceAppIcon: AppIconKind? {
        if store.isCodexMonitorTarget(target) {
            return .codex
        }
        if store.isClaudeCodeMonitorTarget(target) {
            return .claudeCode
        }
        return nil
    }

    private var primarySourceDetail: String {
        switch target.source {
        case .providerUsageAPI:
            return store.t("monitoring.source_official_usage_detail")
        case .aiGatewayLogs:
            return store.t("monitoring.source_ai_gateway_detail")
        case .cloudBilling:
            return store.t("monitoring.source_cloud_billing_detail")
        case .localProxyDevice:
            return store.t("monitoring.local_proxy_boundary")
        case .cliSessionLog:
            return store.isClaudeCodeMonitorTarget(target)
                ? store.t("monitoring.claude_code_source_detail")
                : store.t("monitoring.cli_log_boundary")
        case .subscriptionPlan:
            return store.t("monitoring.subscription_boundary")
        case .manualEstimate:
            return store.t("monitoring.source_manual_detail")
        }
    }

    private var costLine: String {
        switch target.accountKind {
        case .apiUser:
            "\(MoneyFormatter.usd(summary.spendUSD)) / \(MoneyFormatter.usd(target.budgetLimitUSD))"
        case .subscriptionUser:
            "\(MoneyFormatter.usd(target.fixedMonthlyFeeUSD)) / \(store.t("monitoring.per_month"))"
        }
    }

    private var statusText: String {
        switch target.accountKind {
        case .apiUser:
            guard let provider = target.provider else { return store.t("monitoring.status_manual") }
            return store.credentialState[provider] == true
                ? store.t("monitoring.status_api_ready")
                : store.t("monitoring.status_api_key_missing")
        case .subscriptionUser:
            if store.hasCodexSessionQuota(target) {
                return store.t("monitoring.status_codex_session_synced")
            }
            if store.isCodexMonitorTarget(target) {
                return store.t("monitoring.status_codex_detected")
            }
            if store.isClaudeCodeMonitorTarget(target) {
                return store.t("monitoring.source_bound")
            }
            if target.quotaWindows.contains(where: { $0.providerRemainingRatio != nil }) {
                return store.t("monitoring.status_manual_synced")
            }
            if target.usesLocalProxy {
                return store.isProxyRunning ? store.t("monitoring.status_proxy_running") : store.t("monitoring.status_proxy_setup")
            }
            return store.t("monitoring.status_subscription_pending")
        }
    }

    private var statusColor: Color {
        if statusText == store.t("monitoring.status_api_ready") ||
            statusText == store.t("monitoring.status_proxy_running") ||
            statusText == store.t("monitoring.status_codex_session_synced") ||
            statusText == store.t("monitoring.source_bound") {
            return .green
        }
        return .secondary
    }

    private var coverageSymbol: String {
        switch target.coverage {
        case .exactRemote:
            "checkmark.seal"
        case .delayedRemote:
            "clock.badge"
        case .localDeviceOnly:
            "desktopcomputer"
        case .estimate:
            "function"
        case .manual:
            "pencil"
        }
    }

    private var coverageColor: Color {
        switch target.coverage {
        case .exactRemote:
            .green
        case .delayedRemote:
            .blue
        case .localDeviceOnly:
            .orange
        case .estimate:
            .purple
        case .manual:
            .secondary
        }
    }

    private var isAutoDetectedLocalSubscription: Bool {
        store.isCodexMonitorTarget(target) || store.isClaudeCodeMonitorTarget(target)
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

private struct MonitorDataSourceRow: View {
    var title: String
    var detail: String
    var trailing: String
    var appIcon: AppIconKind? = nil
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SourceIconView(
                appIcon: appIcon,
                provider: nil,
                size: 20,
                fallbackSystemImage: symbol,
                fallbackTint: tint
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(trailing)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(9)
        .background(.quaternary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct QuotaWindowSummaryRow: View {
    var summary: QuotaWindowSummary
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.window.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(remainingText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(remainingColor)
            }

            SpendProgressBar(
                value: progressValue,
                maxValue: progressMaxValue,
                tint: progressTint
            )

            HStack {
                Text(usageText)
                Spacer()
                Text(resetText)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var remainingText: String {
        if summary.isProviderReported {
            return "\(store.t("quota.remaining")) \(MoneyFormatter.percent(summary.remainingRatio))"
        }
        return "\(formatUnits(summary.remainingUnits, unit: summary.window.quotaUnit)) \(store.t("quota.remaining"))"
    }

    private var usageText: String {
        if summary.isProviderReported {
            return "\(store.t("quota.used")) \(MoneyFormatter.percent(summary.usedRatio)) · \(reportedSourceLabel)"
        }
        return "\(formatUnits(summary.usedUnits, unit: summary.window.quotaUnit)) / \(formatUnits(summary.window.includedUnits, unit: summary.window.quotaUnit))"
    }

    private var reportedSourceLabel: String {
        store.isCodexSessionQuotaWindow(summary.window)
            ? store.t("quota.codex_session_reported")
            : store.t("quota.provider_reported")
    }

    private var resetText: String {
        let providerLabel = summary.providerResetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !providerLabel.isEmpty {
            return "\(store.t("quota.resets_at")) \(providerLabel)"
        }
        return "\(store.t("quota.resets_at")) \(summary.periodEnd.formatted(date: .omitted, time: .shortened))"
    }

    private var progressValue: Decimal {
        summary.isProviderReported ? summary.remainingRatio : summary.usedUnits
    }

    private var progressMaxValue: Decimal {
        summary.isProviderReported ? 1 : max(Decimal(1), summary.window.includedUnits)
    }

    private var progressTint: Color {
        if summary.isProviderReported {
            if summary.remainingRatio <= Decimal(string: "0.15")! {
                return .red
            }
            if summary.remainingRatio <= Decimal(string: "0.35")! {
                return .orange
            }
            return .blue
        }
        return summary.utilization >= Decimal(string: "0.9")! ? .orange : .purple
    }

    private var remainingColor: Color {
        if summary.isProviderReported {
            return summary.remainingRatio <= Decimal(string: "0.35")! ? .orange : .secondary
        }
        return summary.utilization >= Decimal(string: "0.9")! ? .orange : .secondary
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

private struct AddMonitorWizard: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: ProviderKind = .openAI
    @State private var accountKind: MonitorAccountKind = .apiUser
    @State private var name = ""
    @State private var apiKey = ""
    @State private var baseURL = ProviderKind.openAI.defaultBaseURL?.absoluteString ?? ""
    @State private var resourceID = ""
    @State private var monthlyBudget = 25.0
    @State private var hardCap = 0.0
    @State private var modelPattern = ""
    @State private var usesLocalProxy = false
    @State private var networkProxyMode: NetworkProxyMode = .system
    @State private var networkProxyHost = "127.0.0.1"
    @State private var networkProxyPort = 7890
    @State private var browserAuthRequested = false
    @State private var quotaUnit: SubscriptionQuotaUnit = .messages
    @State private var fiveHourQuotaEnabled = true
    @State private var fiveHourQuota = 0.0
    @State private var dailyQuotaEnabled = false
    @State private var dailyQuota = 0.0
    @State private var weeklyQuotaEnabled = true
    @State private var weeklyQuota = 0.0
    @State private var monthlyQuotaEnabled = false
    @State private var monthlyQuota = 0.0
    @State private var customQuotaEnabled = false
    @State private var customQuota = 0.0
    @State private var customQuotaHours = 3

    init(
        store: AppStore,
        initialProvider: ProviderKind = .openAI,
        initialAccountKind: MonitorAccountKind = .subscriptionUser
    ) {
        self.store = store
        _provider = State(initialValue: initialProvider)
        _accountKind = State(initialValue: initialAccountKind)
        _baseURL = State(initialValue: initialProvider.defaultBaseURL?.absoluteString ?? "")
        _monthlyBudget = State(initialValue: initialAccountKind == .subscriptionUser && initialProvider == .openAI ? 100 : 25)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SourceIconView(
                    appIcon: nil,
                    provider: provider,
                    size: 32,
                    fallbackSystemImage: accountKind == .subscriptionUser ? "person.crop.circle.badge.checkmark" : "server.rack",
                    fallbackTint: accountKind == .subscriptionUser ? .orange : .cyan
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("monitoring.add_data_source"))
                        .font(.title3.weight(.semibold))
                    Text(store.t("monitoring.add_data_source_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    Picker(store.t("subscription.provider"), selection: $provider) {
                        ForEach(ProviderKind.allCases) { provider in
                            ProviderPickerItem(provider: provider).tag(provider)
                        }
                    }
                    .onChange(of: provider) { _, newValue in
                        baseURL = newValue.defaultBaseURL?.absoluteString ?? ""
                        if name.isEmpty {
                            name = defaultName(for: newValue, accountKind: accountKind)
                        }
                    }

                    Picker(store.t("monitoring.account_kind"), selection: $accountKind) {
                        ForEach(MonitorAccountKind.allCases) { kind in
                            Text(store.monitorAccountKindLabel(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: accountKind) { _, newValue in
                        if name.isEmpty || name == defaultName(for: provider, accountKind: newValue == .apiUser ? .subscriptionUser : .apiUser) {
                            name = defaultName(for: provider, accountKind: newValue)
                        }
                        if newValue == .subscriptionUser, provider == .openAI, monthlyBudget == 25 {
                            monthlyBudget = 100
                        }
                    }

                    TextField(store.t("monitoring.name"), text: $name)

                    DisclosureGroup(store.t("monitoring.advanced_scope")) {
                        TextField(store.t("monitoring.model_pattern_optional"), text: $modelPattern)
                    }
                } header: {
                    Text(store.t("monitoring.wizard_basics"))
                }

                if accountKind == .subscriptionUser {
                    subscriptionSection
                } else {
                    apiSection
                }

                Section {
                    TextField(costFieldLabel, value: $monthlyBudget, format: .currency(code: "USD"))
                        .frame(width: 180)
                } footer: {
                    Text(accountKind == .subscriptionUser ? store.t("monitoring.subscription_budget_help") : store.t("monitoring.api_budget_help"))
                }
            }
            .formStyle(.grouped)
            .padding(20)

            Divider()

            HStack {
                Button(store.t("monitoring.cancel")) {
                    dismiss()
                }
                Spacer()
                Button(store.t("monitoring.add_data_source")) {
                    createMonitor()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 560)
        .frame(minHeight: 560)
        .onAppear {
            if name.isEmpty {
                name = defaultName(for: provider, accountKind: accountKind)
            }
            networkProxyMode = store.settings.networkProxy.mode
            networkProxyHost = store.settings.networkProxy.host
            networkProxyPort = store.settings.networkProxy.port
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.t("monitoring.browser_auth_title"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text(store.t("monitoring.browser_auth_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    browserAuthRequested = true
                } label: {
                    Label(store.t("monitoring.browser_auth_button"), systemImage: "safari")
                }
                if browserAuthRequested {
                    Text(store.t("monitoring.browser_auth_planned"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(store.t("monitoring.subscription_auth"))
        }

        Section {
            DisclosureGroup(store.t("monitoring.device_capture")) {
                Toggle(store.t("monitoring.use_local_proxy"), isOn: $usesLocalProxy)
                Text(store.t("monitoring.subscription_proxy_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if usesLocalProxy {
                    networkProxySection
                }
            }
        } header: {
            Text(store.t("monitoring.optional_capture"))
        }

        Section {
            DisclosureGroup(store.t("monitoring.advanced_quota")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("quota.window_help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker(store.t("subscription.unit"), selection: $quotaUnit) {
                        ForEach(SubscriptionQuotaUnit.allCases) { unit in
                            Text(store.quotaUnitLabel(unit)).tag(unit)
                        }
                    }
                    .frame(maxWidth: 260)

                    QuotaWindowDraftRow(
                        title: store.t("quota.window_5h"),
                        isOn: $fiveHourQuotaEnabled,
                        units: $fiveHourQuota,
                        unitLabel: store.quotaUnitLabel(quotaUnit)
                    )
                    QuotaWindowDraftRow(
                        title: store.t("quota.window_daily"),
                        isOn: $dailyQuotaEnabled,
                        units: $dailyQuota,
                        unitLabel: store.quotaUnitLabel(quotaUnit)
                    )
                    QuotaWindowDraftRow(
                        title: store.t("quota.window_weekly"),
                        isOn: $weeklyQuotaEnabled,
                        units: $weeklyQuota,
                        unitLabel: store.quotaUnitLabel(quotaUnit)
                    )
                    QuotaWindowDraftRow(
                        title: store.t("quota.window_monthly"),
                        isOn: $monthlyQuotaEnabled,
                        units: $monthlyQuota,
                        unitLabel: store.quotaUnitLabel(quotaUnit)
                    )

                    HStack {
                        Toggle(store.t("quota.window_custom"), isOn: $customQuotaEnabled)
                        TextField(store.t("quota.units"), value: $customQuota, format: .number)
                            .frame(width: 90)
                            .disabled(!customQuotaEnabled)
                        Text(store.quotaUnitLabel(quotaUnit))
                            .foregroundStyle(.secondary)
                        Stepper("\(customQuotaHours) \(store.t("quota.hours"))", value: $customQuotaHours, in: 1...744)
                            .disabled(!customQuotaEnabled)
                    }
                }
            }
        } header: {
            Text(store.t("quota.section"))
        } footer: {
            Text(store.t("quota.window_footer"))
        }
    }

    private var apiSection: some View {
        Section {
            SecureField(provider.credentialLabel, text: $apiKey)
            TextField(store.t("settings.base_url"), text: $baseURL)

            if provider == .cloudflareAIGateway || provider == .cloudflareWorkersAI || provider == .vercelAIGateway {
                TextField(store.t("settings.resource_id"), text: $resourceID)
            }

            DisclosureGroup(store.t("monitoring.advanced_options")) {
                TextField(store.t("settings.hard_cap"), value: $hardCap, format: .currency(code: "USD"))
                    .frame(width: 180)

                Toggle(store.t("monitoring.use_local_proxy"), isOn: $usesLocalProxy)
                Text(store.t("monitoring.api_proxy_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if usesLocalProxy {
                    networkProxySection
                }
            }
        } header: {
            Text(store.t("monitoring.api_config"))
        } footer: {
            Text(store.t("monitoring.api_config_help"))
        }
    }

    private var networkProxySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(store.t("network_proxy.title"), selection: $networkProxyMode) {
                ForEach(NetworkProxyMode.allCases) { mode in
                    Text(store.networkProxyModeLabel(mode)).tag(mode)
                }
            }

            if networkProxyMode == .http || networkProxyMode == .socks {
                HStack {
                    TextField(store.t("network_proxy.host"), text: $networkProxyHost)
                    TextField(store.t("network_proxy.port"), value: $networkProxyPort, format: .number)
                        .frame(width: 100)
                }

                HStack {
                    Button("Clash 7890") {
                        networkProxyMode = .http
                        networkProxyHost = "127.0.0.1"
                        networkProxyPort = 7890
                    }
                    Button("Surge 6152") {
                        networkProxyMode = .http
                        networkProxyHost = "127.0.0.1"
                        networkProxyPort = 6152
                    }
                }
                .buttonStyle(.bordered)
            }

            Text(store.t("network_proxy.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func createMonitor() {
        let budget = Decimal(monthlyBudget)
        switch accountKind {
        case .subscriptionUser:
            store.createSubscriptionMonitorTarget(
                provider: provider,
                name: name,
                monthlyFeeUSD: budget,
                modelPattern: modelPattern,
                usesLocalProxy: usesLocalProxy,
                quotaWindows: configuredQuotaWindows,
                networkProxy: usesLocalProxy ? currentNetworkProxy : nil
            )
        case .apiUser:
            store.createAPIMonitorTarget(
                provider: provider,
                name: name,
                apiKey: apiKey,
                baseURLString: baseURL,
                resourceID: resourceID,
                monthlyBudgetUSD: budget,
                hardCapUSD: hardCap > 0 ? Decimal(hardCap) : nil,
                modelPattern: modelPattern,
                usesLocalProxy: usesLocalProxy,
                networkProxy: usesLocalProxy ? currentNetworkProxy : nil
            )
        }
    }

    private var currentNetworkProxy: NetworkProxyConfiguration {
        NetworkProxyConfiguration(
            mode: networkProxyMode,
            host: networkProxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: networkProxyPort
        )
    }

    private var costFieldLabel: String {
        accountKind == .subscriptionUser ? store.t("monitoring.monthly_fee") : store.t("monitoring.budget")
    }

    private var configuredQuotaWindows: [SubscriptionQuotaWindow] {
        var windows: [SubscriptionQuotaWindow] = []
        appendQuotaWindow(
            to: &windows,
            isEnabled: fiveHourQuotaEnabled,
            kind: .fiveHours,
            title: store.t("quota.window_5h"),
            units: fiveHourQuota
        )
        appendQuotaWindow(
            to: &windows,
            isEnabled: dailyQuotaEnabled,
            kind: .daily,
            title: store.t("quota.window_daily"),
            units: dailyQuota
        )
        appendQuotaWindow(
            to: &windows,
            isEnabled: weeklyQuotaEnabled,
            kind: .weekly,
            title: store.t("quota.window_weekly"),
            units: weeklyQuota
        )
        appendQuotaWindow(
            to: &windows,
            isEnabled: monthlyQuotaEnabled,
            kind: .monthly,
            title: store.t("quota.window_monthly"),
            units: monthlyQuota
        )
        appendQuotaWindow(
            to: &windows,
            isEnabled: customQuotaEnabled,
            kind: .customHours,
            title: "\(customQuotaHours) \(store.t("quota.hours"))",
            units: customQuota,
            customHours: customQuotaHours
        )
        return windows
    }

    private func appendQuotaWindow(
        to windows: inout [SubscriptionQuotaWindow],
        isEnabled: Bool,
        kind: QuotaWindowKind,
        title: String,
        units: Double,
        customHours: Int = 24
    ) {
        guard isEnabled, units > 0 else { return }
        windows.append(
            SubscriptionQuotaWindow(
                name: title,
                kind: kind,
                includedUnits: Decimal(units),
                quotaUnit: quotaUnit,
                customHours: customHours
            )
        )
    }

    private func defaultName(for provider: ProviderKind, accountKind: MonitorAccountKind) -> String {
        switch accountKind {
        case .subscriptionUser:
            "\(provider.displayName) \(store.t("monitoring.account_subscription"))"
        case .apiUser:
            "\(provider.displayName) API"
        }
    }
}

private struct QuotaWindowDraftRow: View {
    var title: String
    @Binding var isOn: Bool
    @Binding var units: Double
    var unitLabel: String

    var body: some View {
        HStack {
            Toggle(title, isOn: $isOn)
            TextField("0", value: $units, format: .number)
                .frame(width: 90)
                .disabled(!isOn)
            Text(unitLabel)
                .foregroundStyle(.secondary)
        }
    }
}
