import Foundation
import TokenRadarCore
import UserNotifications

enum LiveTestStatus: Equatable {
    case running
    case success
    case failure
}

struct LiveTestResult: Equatable {
    var status: LiveTestStatus
    var message: String
    var detail: String
    var timestamp: Date

    init(
        status: LiveTestStatus,
        message: String,
        detail: String = "",
        timestamp: Date = Date()
    ) {
        self.status = status
        self.message = message
        self.detail = detail
        self.timestamp = timestamp
    }
}

struct CodexDailyTokenPoint: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var tokens: Int
}

struct CodexModelUsageRow: Identifiable, Equatable {
    var id: String { model }
    var model: String
    var tokens: Int
    var runs: Int
    var lastSeen: Date?
}

struct CodexActivitySummary {
    var hasHistory: Bool
    var totalObservedTokens: Int
    var cachedInputTokens: Int
    var reasoningOutputTokens: Int
    var peakObservedTokens: Int
    var activeDays: Int
    var dailyTokenSeries: [CodexDailyTokenPoint]
    var modelUsage: [CodexModelUsageRow]

    static let empty = CodexActivitySummary(
        hasHistory: false,
        totalObservedTokens: 0,
        cachedInputTokens: 0,
        reasoningOutputTokens: 0,
        peakObservedTokens: 0,
        activeDays: 0,
        dailyTokenSeries: [],
        modelUsage: []
    )
}

private struct ProviderRefreshSchedule: Equatable {
    var isEnabled: Bool
    var intervalMinutes: Int
}

@MainActor
final class AppStore: ObservableObject {
    @Published var settings: AppSettings
    @Published var records: [UsageRecord] = []
    @Published var snapshots: [ProviderKind: ProviderUsageSnapshot] = [:]
    @Published var selectedSection: DashboardSection = .overview
    @Published var statusMessage: String = "Ready"
    @Published var lastError: String?
    @Published var isProxyRunning = false
    @Published var credentialState: [ProviderKind: Bool] = [:]
    @Published var lastSessionImportResult: ClaudeCodeSessionImporter.ImportResult?
    @Published var lastCodexQuotaSyncResult: CodexSessionImporter.SyncResult?
    @Published var lastCodexHistoryImportResult: CodexSessionImporter.HistoryImportResult?
    @Published var codexLocalDiscovery: CodexLocalDiscovery = .empty
    @Published var providerLiveTestResults: [ProviderKind: LiveTestResult] = [:]
    @Published var proxyLiveTestResult: LiveTestResult?
    @Published private(set) var recordsVersion = 0
    @Published private(set) var monitoringAnalytics: MonitoringAnalytics = .empty
    @Published private(set) var monitorTargetSummaries: [MonitorTargetSummary] = []

    private let settingsStore: SettingsStore
    private let database: UsageDatabase
    private let keychain: KeychainService
    private let providerFactory = ProviderClientFactory()
    private let proxyServer = LocalProxyServer()
    private static let codexResourceLabel = "codex-cli"
    private static let claudeCodeResourceLabel = "~/.claude/projects"
    private static let codexQuotaNote = "codex-session-rate-limits"
    private var hasBootstrapped = false
    private var isRefreshingProviders = false
    private var providerRefreshTask: Task<Void, Never>?
    private var providerRefreshSchedule: ProviderRefreshSchedule?
    private var localSourceWatcher: LocalSourceFileWatcher?
    private var localSourceWatcherEnabled: Bool?

    init(
        settingsStore: SettingsStore,
        database: UsageDatabase,
        keychain: KeychainService
    ) {
        self.settingsStore = settingsStore
        self.database = database
        self.keychain = keychain
        let loadedSettings = (try? settingsStore.load()) ?? AppSettings()
        self.settings = Self.normalizedSettings(loadedSettings)
        self.statusMessage = L10n.text("status.ready", language: self.settings.language)
        if self.settings != loadedSettings {
            try? settingsStore.save(self.settings)
        }
        try? database.deleteRecords(project: Self.demoProjectLabel)
        if self.settings.monitorTargets.isEmpty {
            self.selectedSection = .monitoring
        }
        self.codexLocalDiscovery = CodexSessionImporter.detectLocalInstallation()
        reloadRecords()
        reloadCredentialState()
    }

    static func live() -> AppStore {
        do {
            return AppStore(
                settingsStore: try SettingsStore(),
                database: try UsageDatabase(),
                keychain: KeychainService()
            )
        } catch {
            let temporarySettings = try! SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("token-radar-settings.json"))
            let temporaryDatabase = try! UsageDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent("token-radar.sqlite3"))
            let store = AppStore(settingsStore: temporarySettings, database: temporaryDatabase, keychain: KeychainService())
            store.lastError = error.localizedDescription
            return store
        }
    }

    var enabledProviders: [ProviderConfiguration] {
        settings.providers.filter(\.isEnabled)
    }

    var enabledMonitorTargets: [MonitorTarget] {
        settings.monitorTargets.filter(\.isEnabled)
    }

    var enabledAPIMonitorTargets: [MonitorTarget] {
        enabledMonitorTargets.filter { $0.accountKind == .apiUser }
    }

    var enabledSubscriptionMonitorTargets: [MonitorTarget] {
        enabledMonitorTargets.filter { $0.accountKind == .subscriptionUser }
    }

    var monitoredRecords: [UsageRecord] {
        let targets = enabledMonitorTargets
        guard !targets.isEmpty else { return records }
        return records.filter { record in
            targets.contains { $0.matches(record) }
        }
    }

    var variableSpendRecords: [UsageRecord] {
        if !enabledAPIMonitorTargets.isEmpty {
            return records.filter { record in
                enabledAPIMonitorTargets.contains { $0.matches(record) }
            }
        }
        return enabledMonitorTargets.isEmpty ? records : []
    }

    var totalMonthlyBudgetUSD: Decimal {
        if !enabledMonitorTargets.isEmpty {
            return enabledAPIMonitorTargets.reduce(Decimal(0)) { $0 + $1.monthlyBudgetUSD }
        }
        return enabledProviders.reduce(Decimal(0)) { $0 + $1.monthlyBudgetUSD }
    }

    var enabledSubscriptions: [SubscriptionPlan] {
        settings.subscriptions.filter(\.isEnabled)
    }

    var subscriptionSummaries: [SubscriptionSummary] {
        SubscriptionCalculator.summarizeAll(plans: settings.subscriptions, records: records)
    }

    var subscriptionMonitorSummaries: [MonitorTargetSummary] {
        monitorTargetSummaries.filter { $0.target.accountKind == .subscriptionUser && $0.target.isEnabled }
    }

    var monthlySubscriptionFeesUSD: Decimal {
        let monitorFees = enabledSubscriptionMonitorTargets.reduce(Decimal(0)) { $0 + $1.monthlyBudgetUSD }
        let planFees = enabledSubscriptions.reduce(Decimal(0)) { $0 + $1.monthlyFeeUSD }
        return monitorFees + planFees
    }

    var subscriptionAllocatedCostToDateUSD: Decimal {
        subscriptionSummaries.reduce(Decimal(0)) { $0 + $1.amortizedCostToDateUSD }
    }

    var subscriptionProjectedOverageUSD: Decimal {
        subscriptionSummaries.reduce(Decimal(0)) { $0 + $1.projectedOverageCostUSD }
    }

    var summary: BudgetSummary {
        BudgetCalculator.summarize(
            records: variableSpendRecords,
            monthlyBudgetUSD: totalMonthlyBudgetUSD,
            thresholds: settings.alertThresholds
        )
    }

    var monthTotalCostUSD: Decimal {
        monthlySubscriptionFeesUSD + summary.monthSpendUSD
    }

    var projectedMonthTotalCostUSD: Decimal {
        monthlySubscriptionFeesUSD + summary.projectedMonthEndUSD
    }

    var menuBarTitle: String {
        if summary.alert?.severity == .critical {
            return "Alert"
        }
        if totalMonthlyBudgetUSD > 0 {
            return "\(MoneyFormatter.compactUSD(summary.remainingBudgetUSD)) left"
        }
        if monthlySubscriptionFeesUSD > 0 {
            return "\(MoneyFormatter.compactUSD(monthlySubscriptionFeesUSD))/mo"
        }
        return "\(MoneyFormatter.compactUSD(summary.todaySpendUSD)) today"
    }

    var menuBarSymbol: String {
        switch summary.alert?.severity {
        case .critical:
            "exclamationmark.triangle.fill"
        case .warning:
            "dot.radiowaves.left.and.right"
        default:
            "scope"
        }
    }

    var topModelTitle: String {
        let monthStart = DateRanges.startOfMonth()
        let grouped = Dictionary(grouping: records.filter { $0.timestamp >= monthStart }, by: \.model)
        let top = grouped
            .map { (model: $0.key, spend: $0.value.reduce(Decimal(0)) { $0 + $1.costUSD }) }
            .sorted { $0.spend > $1.spend }
            .first
        return top.map { "\($0.model) \(MoneyFormatter.compactUSD($0.spend))" } ?? "No usage yet"
    }

    var budgetUsedRatio: Decimal {
        guard totalMonthlyBudgetUSD > 0 else { return 0 }
        return min(1, max(0, summary.monthSpendUSD / totalMonthlyBudgetUSD))
    }

    func t(_ key: String) -> String {
        L10n.text(key, language: settings.language)
    }

    func budgetAlertMessage(_ alert: BudgetAlert) -> String {
        switch alert.message {
        case "Set a monthly budget to enable alerts.":
            return t("budget.alert.set_budget")
        case "Monthly budget is exhausted.":
            return t("budget.alert.exhausted")
        case "Current burn rate is projected to exceed budget.":
            return t("budget.alert.projected_overrun")
        default:
            let prefix = "Usage crossed "
            let suffix = " of monthly budget."
            if alert.message.hasPrefix(prefix), alert.message.hasSuffix(suffix) {
                let percent = alert.message
                    .dropFirst(prefix.count)
                    .dropLast(suffix.count)
                return t("budget.alert.threshold")
                    .replacingOccurrences(of: "{percent}", with: String(percent))
            }
            return alert.message
        }
    }

    func authMethodLabel(_ method: ProviderAuthMethod) -> String {
        switch method {
        case .apiKey:
            t("auth.method_api_key")
        case .adminAPIKey:
            t("auth.method_admin_key")
        case .aiGatewayKey:
            t("auth.method_ai_gateway_key")
        case .browserSession:
            t("auth.method_browser_session")
        case .notAvailable:
            t("auth.method_not_available")
        }
    }

    func subscriptionSyncLabel(_ source: SubscriptionSyncSource) -> String {
        switch source {
        case .manual:
            t("subscription.sync_manual")
        case .localProxy:
            t("subscription.sync_proxy")
        case .cliSessionLog:
            t("subscription.sync_cli_session")
        case .providerAPI:
            t("subscription.sync_provider_api")
        case .browserSession:
            t("subscription.sync_browser")
        }
    }

    func monitorAccountKindLabel(_ kind: MonitorAccountKind) -> String {
        switch kind {
        case .subscriptionUser:
            t("monitoring.account_subscription")
        case .apiUser:
            t("monitoring.account_api")
        }
    }

    func networkProxyModeLabel(_ mode: NetworkProxyMode) -> String {
        switch mode {
        case .system:
            t("network_proxy.mode_system")
        case .direct:
            t("network_proxy.mode_direct")
        case .http:
            t("network_proxy.mode_http")
        case .socks:
            t("network_proxy.mode_socks")
        }
    }

    func quotaWindowKindLabel(_ kind: QuotaWindowKind) -> String {
        switch kind {
        case .fiveHours:
            t("quota.window_5h")
        case .daily:
            t("quota.window_daily")
        case .weekly:
            t("quota.window_weekly")
        case .monthly:
            t("quota.window_monthly")
        case .customHours:
            t("quota.window_custom")
        }
    }

    func quotaUnitLabel(_ unit: SubscriptionQuotaUnit) -> String {
        switch unit {
        case .messages:
            t("subscription.unit_messages")
        case .tokens:
            t("subscription.unit_tokens")
        case .requests:
            t("subscription.unit_requests")
        case .usd:
            t("subscription.unit_usd")
        }
    }

    func monitorSourceLabel(_ source: MonitorSourceKind) -> String {
        switch source {
        case .providerUsageAPI:
            t("monitoring.source_provider_usage_api")
        case .aiGatewayLogs:
            t("monitoring.source_ai_gateway_logs")
        case .cloudBilling:
            t("monitoring.source_cloud_billing")
        case .localProxyDevice:
            t("monitoring.source_local_proxy_device")
        case .cliSessionLog:
            t("monitoring.source_cli_session_log")
        case .subscriptionPlan:
            t("monitoring.source_subscription_plan")
        case .manualEstimate:
            t("monitoring.source_manual_estimate")
        }
    }

    func usageSourceLabel(_ source: UsageSource) -> String {
        switch source {
        case .providerAPI:
            t("monitoring.source_provider_usage_api")
        case .localProxy:
            t("monitoring.source_local_proxy_device")
        case .cliSessionLog:
            t("monitoring.source_cli_session_log")
        case .estimate:
            t("monitoring.source_manual_estimate")
        case .fixture:
            t("dashboard.fixture")
        }
    }

    func monitorScopeLabel(_ scope: MonitorScope) -> String {
        switch scope {
        case .account:
            t("monitoring.scope_account")
        case .project:
            t("monitoring.scope_project")
        case .apiKey:
            t("monitoring.scope_api_key")
        case .gateway:
            t("monitoring.scope_gateway")
        case .worker:
            t("monitoring.scope_worker")
        case .device:
            t("monitoring.scope_device")
        case .subscription:
            t("monitoring.scope_subscription")
        }
    }

    func monitorCoverageLabel(_ coverage: MonitorCoverage) -> String {
        switch coverage {
        case .exactRemote:
            t("monitoring.coverage_exact_remote")
        case .delayedRemote:
            t("monitoring.coverage_delayed_remote")
        case .localDeviceOnly:
            t("monitoring.coverage_local_device_only")
        case .estimate:
            t("monitoring.coverage_estimate")
        case .manual:
            t("monitoring.coverage_manual")
        }
    }

    func subscriptionAuthStatus(for plan: SubscriptionPlan) -> (message: String, symbol: String, isReady: Bool) {
        switch plan.syncSource {
        case .manual:
            return (t("subscription.auth_manual"), "pencil", true)
        case .localProxy:
            return (isProxyRunning ? t("subscription.auth_proxy_ready") : t("subscription.auth_proxy_required"), isProxyRunning ? "checkmark.circle.fill" : "pause.circle", isProxyRunning)
        case .cliSessionLog:
            if let result = lastSessionImportResult, result.filesScanned > 0 {
                return (
                    "\(t("subscription.auth_cli_ready_prefix")) \(result.filesScanned) \(t("subscription.auth_cli_ready_suffix"))",
                    "checkmark.circle.fill",
                    true
                )
            }
            return (t("subscription.auth_cli_required"), "terminal", false)
        case .providerAPI:
            guard let provider = plan.provider else {
                return (t("subscription.auth_provider_required"), "exclamationmark.triangle", false)
            }
            guard provider.supportsOfficialSubscriptionSync else {
                return (t("subscription.auth_official_unavailable"), "xmark.circle", false)
            }
            let hasKey = credentialState[provider] == true
            return (
                hasKey ? t("subscription.auth_provider_ready") : "\(provider.displayName) \(t("subscription.auth_key_required"))",
                hasKey ? "checkmark.circle.fill" : "key",
                hasKey
            )
        case .browserSession:
            return (t("subscription.auth_browser_planned"), "person.crop.circle.badge.clock", false)
        }
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        ensureDefaultSubscriptionMonitorsFromLocalSources(syncCodexQuota: true)
        await refreshAllProviders()
        if settings.proxyEnabled {
            startProxy()
        }
        configureRefreshAutomation()
        requestNotificationPermission()
    }

    func refreshAllProviders() async {
        guard !isRefreshingProviders else { return }
        isRefreshingProviders = true
        defer {
            isRefreshingProviders = false
        }

        lastError = nil
        statusMessage = t("status.refreshing")
        ensureDefaultSubscriptionMonitorsFromLocalSources()
        var loaded = 0

        for configuration in enabledProviders {
            do {
                guard let apiKey = try keychain.readAPIKey(for: configuration.provider), !apiKey.isEmpty else {
                    continue
                }
                let client = providerFactory.client(for: configuration.provider)
                let snapshot = try await client.fetchSnapshot(
                    configuration: configuration,
                    apiKey: apiKey,
                    networkProxy: settings.networkProxy
                )
                snapshots[configuration.provider] = snapshot
                try database.insert(snapshot: snapshot)
                loaded += 1
            } catch {
                lastError = "\(configuration.provider.displayName): \(error.localizedDescription)"
            }
        }

        var shouldReloadRecords = loaded > 0
        let sessionImport = hasClaudeCodeMonitorTarget
            ? syncLocalSessionLogs(updateStatus: false, reloadAfterImport: false)
            : nil
        if (sessionImport?.imported ?? 0) > 0 {
            shouldReloadRecords = true
        }
        let codexHistoryImport = hasCodexMonitorTarget
            ? syncCodexUsageHistory(updateStatus: false, reloadAfterImport: false)
            : nil
        if (codexHistoryImport?.imported ?? 0) > 0 {
            shouldReloadRecords = true
        }
        let codexQuotaSync = syncCodexSessionQuotas(updateStatus: false)
        if shouldReloadRecords {
            reloadRecords()
        }
        evaluateNotifications()
        let importedSessions = sessionImport?.imported ?? 0
        let importedCodexHistory = codexHistoryImport?.imported ?? 0
        let codexQuotaCount = hasCodexMonitorTarget ? codexQuotaSync.snapshots.count : 0
        if loaded == 0 && importedSessions == 0 && importedCodexHistory == 0 && codexQuotaCount == 0 {
            statusMessage = codexLocalDiscovery.isDetected || claudeCodeLocalLogsDetected
                ? t("status.local_sources_detected")
                : t("status.no_provider_refreshed")
        } else {
            statusMessage = "\(t("status.refreshed_prefix")) \(loaded) \(t("status.refreshed_suffix")), \(t("status.session_imported_prefix")) \(importedSessions) \(t("status.session_imported_suffix")), \(t("status.codex_history_imported_prefix")) \(importedCodexHistory) \(t("status.codex_history_imported_suffix")), \(t("status.codex_quota_synced_prefix")) \(codexQuotaCount) \(t("status.codex_quota_synced_suffix"))"
        }
    }

    func testProviderConnection(_ provider: ProviderKind) async {
        providerLiveTestResults[provider] = LiveTestResult(
            status: .running,
            message: "\(provider.displayName) \(t("live_test.running"))",
            detail: t("live_test.official_detail")
        )
        lastError = nil

        do {
            let configuration = providerConfiguration(for: provider)
            guard let apiKey = try keychain.readAPIKey(for: provider), !apiKey.isEmpty else {
                throw ProviderClientError.missingCredential(provider)
            }

            let client = providerFactory.client(for: provider)
            let snapshot = try await client.fetchSnapshot(
                configuration: configuration,
                apiKey: apiKey,
                networkProxy: settings.networkProxy
            )
            snapshots[provider] = snapshot
            try database.insert(snapshot: snapshot)
            reloadRecords()

            let detail = providerSnapshotDetail(snapshot)
            providerLiveTestResults[provider] = LiveTestResult(
                status: .success,
                message: "\(provider.displayName) \(t("live_test.provider_success"))",
                detail: detail
            )
            statusMessage = "\(provider.displayName) \(t("live_test.provider_success"))"
        } catch {
            let message = truncated(error.localizedDescription)
            providerLiveTestResults[provider] = LiveTestResult(
                status: .failure,
                message: "\(provider.displayName) \(t("live_test.failed"))",
                detail: message
            )
            lastError = "\(provider.displayName): \(message)"
        }
    }

    func defaultProxyTestModel() -> String {
        switch settings.defaultProxyProvider {
        case .openAI:
            return "gpt-4o-mini"
        case .deepSeek:
            return "deepseek-chat"
        default:
            return ModelCatalog.imageRanking.first { $0.provider == settings.defaultProxyProvider }?.defaultModelID ?? "gpt-4o-mini"
        }
    }

    func runProxyLiveTest(model: String) async {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else {
            proxyLiveTestResult = LiveTestResult(
                status: .failure,
                message: t("live_test.proxy_failed"),
                detail: t("live_test.model_required")
            )
            return
        }

        proxyLiveTestResult = LiveTestResult(
            status: .running,
            message: t("live_test.proxy_running"),
            detail: "http://127.0.0.1:\(settings.proxyPort)/v1/chat/completions"
        )

        do {
            if !isProxyRunning {
                startProxy()
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard isProxyRunning else {
                throw LiveTestError.proxyNotRunning
            }

            let requestBody: [String: Any] = [
                "model": cleanModel,
                "messages": [
                    [
                        "role": "user",
                        "content": "Reply with exactly: token-radar-ok"
                    ]
                ],
                "max_tokens": 12,
                "temperature": 0,
                "stream": false
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            guard let url = URL(string: "http://127.0.0.1:\(settings.proxyPort)/v1/chat/completions") else {
                throw LiveTestError.invalidProxyURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("Bearer token-radar-local-test", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LiveTestError.httpStatus(statusCode, truncated(body, limit: 500))
            }

            guard let extracted = OpenAIUsageExtractor.extract(
                responseData: data,
                requestData: bodyData,
                fallbackModel: cleanModel
            ) else {
                throw LiveTestError.noUsage
            }

            try await Task.sleep(nanoseconds: 250_000_000)

            let cost = PriceCatalog.estimateCost(
                provider: settings.defaultProxyProvider,
                model: extracted.model,
                inputTokens: extracted.inputTokens,
                outputTokens: extracted.outputTokens
            )
            proxyLiveTestResult = LiveTestResult(
                status: .success,
                message: t("live_test.proxy_success"),
                detail: "\(extracted.model) · \(extracted.inputTokens + extracted.outputTokens) tok · \(MoneyFormatter.usd(cost))"
            )
            statusMessage = t("live_test.proxy_success")
        } catch {
            let message = truncated(error.localizedDescription)
            proxyLiveTestResult = LiveTestResult(
                status: .failure,
                message: t("live_test.proxy_failed"),
                detail: message
            )
            lastError = message
        }
    }

    func saveAPIKey(_ apiKey: String, for provider: ProviderKind) {
        do {
            try keychain.saveAPIKey(apiKey, for: provider)
            credentialState[provider] = true
            statusMessage = "\(provider.displayName) \(t("settings.saved"))"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteAPIKey(for provider: ProviderKind) {
        do {
            try keychain.deleteAPIKey(for: provider)
            credentialState[provider] = false
            statusMessage = "\(provider.displayName) \(t("settings.delete"))"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func persistSettings(reconfigureProxy: Bool = true) {
        do {
            try settingsStore.save(settings)
            statusMessage = t("status.settings_saved")
            if reconfigureProxy {
                if settings.proxyEnabled {
                    restartProxyIfNeeded()
                } else {
                    stopProxy()
                }
            }
            configureRefreshAutomation()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSettings(reconfigureProxy: Bool = true, mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        refreshMonitoringDerivedState()
        persistSettings(reconfigureProxy: reconfigureProxy)
    }

    func setLanguage(_ language: AppLanguage) {
        guard settings.language != language else { return }
        updateSettings(reconfigureProxy: false) { next in
            next.language = language
        }
        statusMessage = t("status.settings_saved")
    }

    func toggleProxy() {
        updateSettings(reconfigureProxy: false) {
            $0.proxyEnabled.toggle()
        }
        if settings.proxyEnabled {
            startProxy()
        } else {
            stopProxy()
        }
    }

    func startProxy() {
        do {
            guard let providerConfig = settings.providers.first(where: { $0.provider == settings.defaultProxyProvider }) else {
                throw ProviderClientError.unsupportedProvider(settings.defaultProxyProvider)
            }
            guard let apiKey = try keychain.readAPIKey(for: providerConfig.provider), !apiKey.isEmpty else {
                throw ProviderClientError.missingCredential(providerConfig.provider)
            }
            guard let baseURL = providerConfig.baseURL else {
                throw ProviderClientError.invalidBaseURL(providerConfig.provider)
            }

            let hardCap = providerConfig.hardCapUSD
            let provider = providerConfig.provider
            let database = self.database

            try proxyServer.start(
                configuration: LocalProxyServer.Configuration(
                    port: settings.proxyPort,
                    upstreamBaseURL: baseURL,
                    upstreamAPIKey: apiKey,
                    provider: provider,
                    projectLabel: "Local Proxy",
                    apiKeyLabel: providerConfig.apiKeyLabel,
                    networkProxy: settings.networkProxy
                ),
                shouldBlockRequest: {
                    guard let hardCap else { return false }
                    let monthRecords = (try? database.fetchRecords(since: DateRanges.startOfMonth())) ?? []
                    let spend = monthRecords
                        .filter { $0.provider == provider }
                        .reduce(Decimal(0)) { $0 + $1.costUSD }
                    return spend >= hardCap
                },
                onRecord: { [weak self] record in
                    try? database.insert(record)
                    DispatchQueue.main.async {
                        self?.mergeRecordIntoMemory(record)
                        self?.evaluateNotifications()
                    }
                },
                onError: { [weak self] error in
                    DispatchQueue.main.async {
                        self?.lastError = error.localizedDescription
                    }
                }
            )
            isProxyRunning = true
            updateSettings(reconfigureProxy: false) { $0.proxyEnabled = true }
            statusMessage = "\(t("status.proxy_listening")):\(settings.proxyPort)"
        } catch {
            isProxyRunning = false
            updateSettings(reconfigureProxy: false) { $0.proxyEnabled = false }
            lastError = error.localizedDescription
        }
    }

    func stopProxy() {
        proxyServer.stop()
        isProxyRunning = false
        updateSettings(reconfigureProxy: false) { $0.proxyEnabled = false }
        statusMessage = t("status.proxy_paused")
    }

    func restartProxyIfNeeded() {
        guard settings.proxyEnabled || isProxyRunning else { return }
        startProxy()
    }

    private func configureRefreshAutomation() {
        configureProviderRefreshTimer()
        configureLocalSourceWatcher()
    }

    private func configureProviderRefreshTimer() {
        let schedule = ProviderRefreshSchedule(
            isEnabled: settings.automaticProviderRefreshEnabled,
            intervalMinutes: Self.clampedProviderRefreshInterval(settings.providerRefreshIntervalMinutes)
        )
        guard schedule != providerRefreshSchedule else { return }

        providerRefreshTask?.cancel()
        providerRefreshTask = nil
        providerRefreshSchedule = schedule

        guard schedule.isEnabled else { return }

        let intervalNanoseconds = Self.refreshIntervalNanoseconds(minutes: schedule.intervalMinutes)
        providerRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.refreshAllProviders()
            }
        }
    }

    private func configureLocalSourceWatcher() {
        let isEnabled = settings.realtimeLocalSourceRefreshEnabled
        guard isEnabled != localSourceWatcherEnabled else { return }

        localSourceWatcherEnabled = isEnabled
        guard isEnabled else {
            localSourceWatcher?.stop()
            return
        }

        if localSourceWatcher == nil {
            localSourceWatcher = LocalSourceFileWatcher { [weak self] in
                self?.syncLocalSourcesFromWatcher()
            }
        }
        localSourceWatcher?.start(roots: localSourceWatchRoots())
    }

    private func syncLocalSourcesFromWatcher() {
        ensureDefaultSubscriptionMonitorsFromLocalSources()

        var shouldReloadRecords = false
        let sessionImport = hasClaudeCodeMonitorTarget
            ? syncLocalSessionLogs(updateStatus: false, reloadAfterImport: false)
            : nil
        if (sessionImport?.imported ?? 0) > 0 {
            shouldReloadRecords = true
        }

        let codexHistoryImport = hasCodexMonitorTarget
            ? syncCodexUsageHistory(updateStatus: false, reloadAfterImport: false)
            : nil
        if (codexHistoryImport?.imported ?? 0) > 0 {
            shouldReloadRecords = true
        }

        let codexQuotaSync = hasCodexMonitorTarget
            ? syncCodexSessionQuotas(updateStatus: false)
            : CodexSessionImporter.SyncResult()

        if shouldReloadRecords {
            reloadRecords()
        }
        evaluateNotifications()

        let importedSessions = sessionImport?.imported ?? 0
        let importedCodexHistory = codexHistoryImport?.imported ?? 0
        let codexQuotaCount = codexQuotaSync.snapshots.count
        if importedSessions > 0 || importedCodexHistory > 0 || codexQuotaCount > 0 {
            statusMessage = "\(t("status.realtime_refresh")): \(t("status.session_imported_prefix")) \(importedSessions) \(t("status.session_imported_suffix")), \(t("status.codex_history_imported_prefix")) \(importedCodexHistory) \(t("status.codex_history_imported_suffix")), \(t("status.codex_quota_synced_prefix")) \(codexQuotaCount) \(t("status.codex_quota_synced_suffix"))"
        }
    }

    private func localSourceWatchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        return [
            codexDirectory.appendingPathComponent("sessions", isDirectory: true),
            claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        ]
    }

    private nonisolated static func clampedProviderRefreshInterval(_ minutes: Int) -> Int {
        min(24 * 60, max(5, minutes))
    }

    private nonisolated static func refreshIntervalNanoseconds(minutes: Int) -> UInt64 {
        UInt64(clampedProviderRefreshInterval(minutes)) * 60 * 1_000_000_000
    }

    @discardableResult
    func syncLocalSessionLogs(
        updateStatus: Bool = true,
        reloadAfterImport: Bool = true
    ) -> ClaudeCodeSessionImporter.ImportResult? {
        do {
            let result = try ClaudeCodeSessionImporter().importRecords(into: database)
            lastSessionImportResult = result
            if reloadAfterImport, result.imported > 0 {
                reloadRecords()
            }
            if updateStatus {
                statusMessage = result.imported == 0
                    ? t("status.session_import_empty")
                    : "\(t("status.session_imported_prefix")) \(result.imported) \(t("status.session_imported_suffix"))"
            }
            if let firstError = result.errors.first {
                lastError = firstError
            }
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func syncCodexSessionQuotas(updateStatus: Bool = true) -> CodexSessionImporter.SyncResult {
        codexLocalDiscovery = CodexSessionImporter.detectLocalInstallation()
        let result = CodexSessionImporter().sync()
        lastCodexQuotaSyncResult = result

        if !result.snapshots.isEmpty {
            applyCodexQuotaSnapshots(result.snapshots)
        }

        if updateStatus {
            if result.snapshots.isEmpty {
                statusMessage = codexLocalDiscovery.isDetected
                    ? t("status.codex_detected_no_quota")
                    : t("status.codex_quota_empty")
            } else {
                statusMessage = "\(t("status.codex_quota_synced_prefix")) \(result.snapshots.count) \(t("status.codex_quota_synced_suffix"))"
            }
        }
        if let firstError = result.errors.first {
            lastError = firstError
        }
        return result
    }

    @discardableResult
    func syncCodexUsageHistory(
        updateStatus: Bool = true,
        reloadAfterImport: Bool = true
    ) -> CodexSessionImporter.HistoryImportResult? {
        do {
            codexLocalDiscovery = CodexSessionImporter.detectLocalInstallation()
            let result = try CodexSessionImporter().importUsageRecords(
                into: database,
                knownFileModificationTimes: settings.codexImportedSessionFiles
            )
            lastCodexHistoryImportResult = result
            persistCodexImportCache(result.fileModificationTimes)
            if reloadAfterImport, result.imported > 0 {
                reloadRecords()
            }
            if updateStatus {
                statusMessage = result.imported == 0
                    ? t("status.codex_history_import_empty")
                    : "\(t("status.codex_history_imported_prefix")) \(result.imported) \(t("status.codex_history_imported_suffix"))"
            }
            if let firstError = result.errors.first {
                lastError = firstError
            }
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func hasCodexSessionQuota(_ target: MonitorTarget) -> Bool {
        target.quotaWindows.contains { isCodexSessionQuotaWindow($0) }
    }

    func isCodexSessionQuotaWindow(_ window: SubscriptionQuotaWindow) -> Bool {
        window.note == Self.codexQuotaNote
    }

    func isCodexMonitorTarget(_ target: MonitorTarget) -> Bool {
        Self.isCodexMonitorTarget(target)
    }

    var hasCodexMonitorTarget: Bool {
        settings.monitorTargets.contains(where: Self.isCodexMonitorTarget)
    }

    var hasClaudeCodeMonitorTarget: Bool {
        settings.monitorTargets.contains(where: Self.isClaudeCodeMonitorTarget)
    }

    var claudeCodeLocalLogsDetected: Bool {
        let projectsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        return Self.hasJSONLFile(in: projectsDirectory)
    }

    private static func isCodexMonitorTarget(_ target: MonitorTarget) -> Bool {
        target.accountKind == .subscriptionUser &&
        target.provider == .openAI &&
        (
            target.resourceLabel == Self.codexResourceLabel ||
            target.quotaWindows.contains { $0.note == Self.codexQuotaNote }
        )
    }

    func isClaudeCodeMonitorTarget(_ target: MonitorTarget) -> Bool {
        Self.isClaudeCodeMonitorTarget(target)
    }

    private static func isClaudeCodeMonitorTarget(_ target: MonitorTarget) -> Bool {
        target.provider == .anthropic &&
            target.source == .cliSessionLog &&
            (
                target.resourceLabel == Self.claudeCodeResourceLabel ||
                target.note.localizedCaseInsensitiveContains("Claude Code")
            )
    }

    func ensureDefaultSubscriptionMonitorsFromLocalSources(syncCodexQuota: Bool = false) {
        codexLocalDiscovery = CodexSessionImporter.detectLocalInstallation()
        if codexLocalDiscovery.isDetected, !hasCodexMonitorTarget {
            let snapshots = syncCodexQuota
                ? syncCodexSessionQuotas(updateStatus: false).snapshots
                : (lastCodexQuotaSyncResult?.snapshots ?? [])
            createCodexMonitorTarget(snapshots: snapshots)
        }

        if claudeCodeLocalLogsDetected, !hasClaudeCodeMonitorTarget {
            createClaudeCodeMonitorTargetFromDiscovery()
        }
    }

    func createCodexMonitorTargetFromDiscovery() {
        createCodexMonitorTarget(snapshots: lastCodexQuotaSyncResult?.snapshots ?? [])
    }

    func createClaudeCodeMonitorTargetFromDiscovery() {
        guard !settings.monitorTargets.contains(where: Self.isClaudeCodeMonitorTarget) else {
            return
        }

        let target = MonitorTarget(
            name: "Claude Code",
            accountKind: .subscriptionUser,
            provider: .anthropic,
            source: .cliSessionLog,
            scope: .device,
            resourceLabel: Self.claudeCodeResourceLabel,
            deviceLabel: Host.current().localizedName ?? "This Mac",
            monthlyBudgetUSD: 20,
            usesLocalProxy: false,
            quotaWindows: [],
            note: t("monitoring.claude_code_detected_note")
        )

        updateSettings(reconfigureProxy: false) {
            $0.monitorTargets.append(target)
        }
    }

    private func createCodexMonitorTarget(snapshots: [CodexUsageSnapshot]) {
        guard !settings.monitorTargets.contains(where: Self.isCodexMonitorTarget) else {
            return
        }

        let quotaWindows = codexQuotaWindows(from: snapshots)
        let target = MonitorTarget(
            name: t("monitoring.codex_auto_name"),
            accountKind: .subscriptionUser,
            provider: .openAI,
            source: .subscriptionPlan,
            scope: .subscription,
            resourceLabel: Self.codexResourceLabel,
            modelPattern: "codex",
            deviceLabel: Host.current().localizedName ?? "This Mac",
            monthlyBudgetUSD: defaultCodexMonthlyFee(snapshots: snapshots),
            usesLocalProxy: false,
            quotaWindows: quotaWindows,
            note: quotaWindows.isEmpty
                ? t("monitoring.subscription_codex_detected_note")
                : t("monitoring.subscription_codex_session_note")
        )

        updateSettings(reconfigureProxy: false) {
            $0.monitorTargets.append(target)
        }
    }

    private static func hasJSONLFile(in directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return false
        }

        for case let file as URL in enumerator {
            if file.pathExtension.lowercased() == "jsonl" {
                return true
            }
        }
        return false
    }

    private func applyCodexQuotaSnapshots(_ snapshots: [CodexUsageSnapshot]) {
        let windows = codexQuotaWindows(from: snapshots)
        guard !windows.isEmpty else { return }

        let note = t("monitoring.subscription_codex_session_note")
        updateSettings(reconfigureProxy: false) { settings in
            for index in settings.monitorTargets.indices {
                guard Self.isCodexMonitorTarget(settings.monitorTargets[index]) ||
                        (
                            settings.monitorTargets[index].accountKind == .subscriptionUser &&
                            settings.monitorTargets[index].provider == .openAI &&
                            settings.monitorTargets[index].quotaWindows.isEmpty
                        )
                else {
                    continue
                }

                let preservedWindows = settings.monitorTargets[index].quotaWindows.filter {
                    $0.note != Self.codexQuotaNote
                }
                settings.monitorTargets[index].quotaWindows = windows + preservedWindows
                settings.monitorTargets[index].note = note
            }
        }
    }

    private func defaultCodexMonthlyFee(snapshots: [CodexUsageSnapshot]) -> Decimal {
        let planTypes = snapshots.compactMap { $0.planType?.lowercased() }
        if planTypes.contains("pro") {
            return 100
        }
        if planTypes.contains("plus") {
            return 20
        }
        return 100
    }

    private func codexQuotaWindows(from snapshots: [CodexUsageSnapshot]) -> [SubscriptionQuotaWindow] {
        snapshots.flatMap { snapshot -> [SubscriptionQuotaWindow] in
            let trimmedName = snapshot.limitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let baseName = trimmedName.isEmpty ? t("quota.codex_general") : trimmedName

            return [
                SubscriptionQuotaWindow(
                    name: "\(baseName) \(t("quota.window_5h"))",
                    kind: .fiveHours,
                    includedUnits: 0,
                    quotaUnit: .tokens,
                    providerRemainingRatio: snapshot.primary.remainingRatio,
                    providerResetAt: snapshot.primary.resetsAt,
                    providerResetLabel: quotaResetLabel(for: snapshot.primary.resetsAt),
                    providerReportedAt: snapshot.timestamp,
                    note: Self.codexQuotaNote
                ),
                SubscriptionQuotaWindow(
                    name: "\(baseName) \(t("quota.window_weekly"))",
                    kind: .weekly,
                    includedUnits: 0,
                    quotaUnit: .tokens,
                    providerRemainingRatio: snapshot.secondary.remainingRatio,
                    providerResetAt: snapshot.secondary.resetsAt,
                    providerResetLabel: quotaResetLabel(for: snapshot.secondary.resetsAt),
                    providerReportedAt: snapshot.timestamp,
                    note: Self.codexQuotaNote
                )
            ]
        }
    }

    private func quotaResetLabel(for date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) || (date > Date() && date.timeIntervalSinceNow < 24 * 60 * 60) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    func reloadRecords() {
        do {
            replaceRecords(try database.fetchRecords(since: recentRecordsStartDate()))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func recentRecordsStartDate() -> Date? {
        Calendar.current.date(byAdding: .month, value: -3, to: Date())
    }

    private func replaceRecords(_ nextRecords: [UsageRecord]) {
        records = nextRecords
        recordsVersion += 1
        refreshMonitoringDerivedState()
    }

    private func mergeRecordIntoMemory(_ record: UsageRecord) {
        if let startDate = recentRecordsStartDate(), record.timestamp < startDate {
            return
        }

        if let existingIndex = records.firstIndex(where: { $0.id == record.id }) {
            records[existingIndex] = record
        } else if let insertIndex = records.firstIndex(where: { $0.timestamp < record.timestamp }) {
            records.insert(record, at: insertIndex)
        } else {
            records.append(record)
        }
        recordsVersion += 1
        refreshMonitoringDerivedState()
    }

    private func refreshMonitoringDerivedState() {
        monitoringAnalytics = MonitoringAnalytics.make(records: records)
        monitorTargetSummaries = settings.monitorTargets.map { target in
            MonitorTargetSummary(target: target, records: records)
        }
    }

    func removeDemoData() {
        do {
            updateSettings(reconfigureProxy: false) { settings in
                settings.monitorTargets.removeAll(where: Self.isDemoMonitorTarget)
            }
            try database.deleteRecords(project: Self.demoProjectLabel)
            reloadRecords()
            statusMessage = t("monitoring.demo_removed")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func providerConfiguration(for provider: ProviderKind) -> ProviderConfiguration {
        settings.providers.first(where: { $0.provider == provider }) ?? ProviderConfiguration(provider: provider)
    }

    func updateProvider(_ provider: ProviderKind, mutate: (inout ProviderConfiguration) -> Void) {
        updateSettings {
            if let index = $0.providers.firstIndex(where: { $0.provider == provider }) {
                mutate(&$0.providers[index])
            } else {
                var configuration = ProviderConfiguration(provider: provider)
                mutate(&configuration)
                $0.providers.append(configuration)
            }
        }
    }

    func addMonitorTarget(template: MonitorTarget? = nil) {
        updateSettings(reconfigureProxy: false) { settings in
            if var target = template {
                target.id = UUID()
                target.isEnabled = true
                settings.monitorTargets.append(target)
            } else {
                settings.monitorTargets.append(
                    MonitorTarget(
                        name: t("monitoring.new_target"),
                        provider: nil,
                        source: .manualEstimate,
                        scope: .project,
                        monthlyBudgetUSD: 25
                    )
                )
            }
        }
    }

    func createAPIMonitorTarget(
        provider: ProviderKind,
        name: String,
        apiKey: String,
        baseURLString: String,
        resourceID: String,
        monthlyBudgetUSD: Decimal,
        hardCapUSD: Decimal?,
        modelPattern: String,
        usesLocalProxy: Bool,
        networkProxy: NetworkProxyConfiguration? = nil
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            saveAPIKey(cleanKey, for: provider)
        }

        updateProvider(provider) { configuration in
            configuration.isEnabled = true
            configuration.monthlyBudgetUSD = monthlyBudgetUSD
            configuration.hardCapUSD = hardCapUSD
            configuration.resourceID = resourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let target = MonitorTarget(
            name: cleanName.isEmpty ? "\(provider.displayName) API" : cleanName,
            accountKind: .apiUser,
            provider: provider,
            source: defaultMonitorSource(for: provider),
            scope: defaultMonitorScope(for: provider),
            resourceLabel: resourceID.trimmingCharacters(in: .whitespacesAndNewlines),
            modelPattern: modelPattern.trimmingCharacters(in: .whitespacesAndNewlines),
            monthlyBudgetUSD: monthlyBudgetUSD,
            usesLocalProxy: usesLocalProxy,
            note: usesLocalProxy ? t("monitoring.api_with_proxy_note") : t("monitoring.api_official_note")
        )

        updateSettings(reconfigureProxy: false) { settings in
            settings.monitorTargets.append(target)
            if usesLocalProxy {
                settings.defaultProxyProvider = provider
            }
            if let networkProxy {
                settings.networkProxy = networkProxy
            }
        }

        if usesLocalProxy && !cleanKey.isEmpty {
            startProxy()
        }
    }

    func createSubscriptionMonitorTarget(
        provider: ProviderKind,
        name: String,
        monthlyBudgetUSD: Decimal,
        modelPattern: String,
        usesLocalProxy: Bool,
        quotaWindows: [SubscriptionQuotaWindow] = [],
        networkProxy: NetworkProxyConfiguration? = nil
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = MonitorTarget(
            name: cleanName.isEmpty ? "\(provider.displayName) \(t("monitoring.account_subscription"))" : cleanName,
            accountKind: .subscriptionUser,
            provider: provider,
            source: .subscriptionPlan,
            scope: .subscription,
            modelPattern: modelPattern.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceLabel: Host.current().localizedName ?? "This Mac",
            monthlyBudgetUSD: monthlyBudgetUSD,
            usesLocalProxy: usesLocalProxy,
            quotaWindows: quotaWindows,
            note: usesLocalProxy ? t("monitoring.subscription_with_proxy_note") : t("monitoring.subscription_browser_note")
        )

        updateSettings(reconfigureProxy: false) { settings in
            settings.monitorTargets.append(target)
            if usesLocalProxy {
                settings.defaultProxyProvider = provider
            }
            if let networkProxy {
                settings.networkProxy = networkProxy
            }
        }
    }

    func deleteMonitorTarget(id: UUID) {
        updateSettings(reconfigureProxy: false) {
            $0.monitorTargets.removeAll { $0.id == id }
        }
    }

    func updateMonitorTarget(_ id: UUID, mutate: (inout MonitorTarget) -> Void) {
        guard let index = settings.monitorTargets.firstIndex(where: { $0.id == id }) else { return }
        updateSettings(reconfigureProxy: false) {
            mutate(&$0.monitorTargets[index])
        }
    }

    func addSubscription() {
        addSubscription(
            SubscriptionPlan(
                name: t("subscription.new_plan"),
                provider: settings.defaultProxyProvider,
                modelPattern: "",
                monthlyFeeUSD: 20,
                includedUnits: 0,
                quotaUnit: .messages,
                resetDay: 1,
                syncSource: .manual
            )
        )
    }

    func addSubscription(_ plan: SubscriptionPlan) {
        updateSettings { settings in
            settings.subscriptions.append(plan)
        }
    }

    func deleteSubscription(id: UUID) {
        updateSettings {
            $0.subscriptions.removeAll { $0.id == id }
        }
    }

    func updateSubscription(_ id: UUID, mutate: (inout SubscriptionPlan) -> Void) {
        guard let index = settings.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        updateSettings {
            mutate(&$0.subscriptions[index])
        }
    }

    func providerSummary(for provider: ProviderKind) -> BudgetSummary {
        let config = providerConfiguration(for: provider)
        return BudgetCalculator.summarize(
            records: records.filter { $0.provider == provider },
            monthlyBudgetUSD: config.monthlyBudgetUSD,
            thresholds: settings.alertThresholds
        )
    }

    func spendByModel(limit: Int = 8) -> [(model: String, provider: ProviderKind, spend: Decimal, tokens: Int)] {
        let monthStart = DateRanges.startOfMonth()
        let grouped = Dictionary(grouping: records.filter { $0.timestamp >= monthStart }) { record in
            "\(record.provider.rawValue)|\(record.model)"
        }
        return grouped
            .compactMap { _, records in
                guard let first = records.first else { return nil }
                let spend = records.reduce(Decimal(0)) { $0 + $1.costUSD }
                let tokens = records.reduce(0) { $0 + $1.totalTokens }
                return (model: first.model, provider: first.provider, spend: spend, tokens: tokens)
            }
            .sorted { $0.spend > $1.spend }
            .prefix(limit)
            .map { $0 }
    }

    var codexUsageRecords: [UsageRecord] {
        records.filter(isCodexUsageRecord)
    }

    var codexTotalObservedTokens: Int {
        codexUsageRecords.reduce(0) { $0 + codexObservedTokens($1) }
    }

    var codexCachedInputTokens: Int {
        codexUsageRecords.reduce(0) { $0 + $1.cachedInputTokens }
    }

    var codexReasoningOutputTokens: Int {
        codexUsageRecords.reduce(0) { $0 + $1.reasoningOutputTokens }
    }

    var codexPeakObservedTokens: Int {
        codexUsageRecords.map(codexObservedTokens).max() ?? 0
    }

    var codexActiveDays: Int {
        Set(codexUsageRecords.map { DateRanges.startOfDay(containing: $0.timestamp) }).count
    }

    func codexDailyTokenSeries(days: Int = 35) -> [(date: Date, tokens: Int)] {
        let calendar = Calendar.current
        let today = DateRanges.startOfDay()
        let starts = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)
        }

        return starts.map { start in
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let tokens = codexUsageRecords
                .filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(0) { $0 + codexObservedTokens($1) }
            return (date: start, tokens: tokens)
        }
    }

    func codexModelUsage(limit: Int = 5) -> [(model: String, tokens: Int, runs: Int, lastSeen: Date?)] {
        Dictionary(grouping: codexUsageRecords, by: \.model)
            .map { model, records in
                (
                    model: model,
                    tokens: records.reduce(0) { $0 + codexObservedTokens($1) },
                    runs: records.count,
                    lastSeen: records.map(\.timestamp).max()
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.model < rhs.model
                }
                return lhs.tokens > rhs.tokens
            }
            .prefix(limit)
            .map { $0 }
    }

    func codexActivitySummary(days: Int = 35, modelLimit: Int = 5) -> CodexActivitySummary {
        let codexRecords = records.filter(isCodexUsageRecord)
        guard !codexRecords.isEmpty else { return .empty }

        let calendar = Calendar.current
        let today = DateRanges.startOfDay()
        let starts = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)
        }

        var totalObservedTokens = 0
        var cachedInputTokens = 0
        var reasoningOutputTokens = 0
        var peakObservedTokens = 0
        var activeDays = Set<Date>()
        var dailyTokens: [Date: Int] = [:]
        var modelUsage: [String: CodexModelUsageRow] = [:]

        for record in codexRecords {
            let observedTokens = codexObservedTokens(record)
            totalObservedTokens += observedTokens
            cachedInputTokens += record.cachedInputTokens
            reasoningOutputTokens += record.reasoningOutputTokens
            peakObservedTokens = max(peakObservedTokens, observedTokens)

            let day = DateRanges.startOfDay(containing: record.timestamp)
            activeDays.insert(day)
            dailyTokens[day, default: 0] += observedTokens

            var modelRow = modelUsage[record.model] ?? CodexModelUsageRow(
                model: record.model,
                tokens: 0,
                runs: 0,
                lastSeen: nil
            )
            modelRow.tokens += observedTokens
            modelRow.runs += 1
            if modelRow.lastSeen.map({ record.timestamp > $0 }) ?? true {
                modelRow.lastSeen = record.timestamp
            }
            modelUsage[record.model] = modelRow
        }

        let dailySeries = starts.map { start in
            CodexDailyTokenPoint(date: start, tokens: dailyTokens[start] ?? 0)
        }
        let modelRows = modelUsage.values
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.model < rhs.model
                }
                return lhs.tokens > rhs.tokens
            }
            .prefix(modelLimit)
            .map { $0 }

        return CodexActivitySummary(
            hasHistory: true,
            totalObservedTokens: totalObservedTokens,
            cachedInputTokens: cachedInputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            peakObservedTokens: peakObservedTokens,
            activeDays: activeDays.count,
            dailyTokenSeries: dailySeries,
            modelUsage: modelRows
        )
    }

    func dailySpendSeries(days: Int = 14) -> [(date: Date, spend: Decimal)] {
        let calendar = Calendar.current
        let today = DateRanges.startOfDay()
        let starts = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)
        }

        return starts.map { start in
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let spend = records
                .filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(Decimal(0)) { $0 + $1.costUSD }
            return (date: start, spend: spend)
        }
    }

    func providerSpendDistribution(limit: Int = 6) -> [(provider: ProviderKind, spend: Decimal, ratio: Decimal)] {
        let monthStart = DateRanges.startOfMonth()
        let grouped = Dictionary(grouping: records.filter { $0.timestamp >= monthStart }, by: \.provider)
        let rows = grouped.map { provider, records in
            (provider: provider, spend: records.reduce(Decimal(0)) { $0 + $1.costUSD })
        }
        let total = max(rows.reduce(Decimal(0)) { $0 + $1.spend }, Decimal(string: "0.0001")!)
        return rows
            .sorted { $0.spend > $1.spend }
            .prefix(limit)
            .map { row in (provider: row.provider, spend: row.spend, ratio: row.spend / total) }
    }

    func recentSpikeRecords(limit: Int = 5) -> [UsageRecord] {
        let monthRecords = records.filter { $0.timestamp >= DateRanges.startOfMonth() }
        guard !monthRecords.isEmpty else { return [] }
        let average = monthRecords.reduce(Decimal(0)) { $0 + $1.costUSD } / Decimal(monthRecords.count)
        return monthRecords
            .filter { $0.costUSD > max(average * 3, Decimal(string: "0.25")!) }
            .sorted { $0.costUSD > $1.costUSD }
            .prefix(limit)
            .map { $0 }
    }

    func trackedModelCoverage() -> [(model: TrackedModel, spend: Decimal, tokens: Int, lastSeen: Date?)] {
        ModelCatalog.imageRanking.map { tracked in
            let matches = records.filter { record in
                tracked.matches(modelName: record.model) || tracked.matches(modelName: record.model, provider: record.provider)
            }
            let spend = matches.reduce(Decimal(0)) { $0 + $1.costUSD }
            let tokens = matches.reduce(0) { $0 + $1.totalTokens }
            let lastSeen = matches.map(\.timestamp).max()
            return (model: tracked, spend: spend, tokens: tokens, lastSeen: lastSeen)
        }
    }

    private func reloadCredentialState() {
        credentialState = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { provider in
            let hasKey = ((try? keychain.readAPIKey(for: provider)) ?? nil)?.isEmpty == false
            return (provider, hasKey)
        })
    }

    private static let demoProjectLabel = "token-radar-demo"

    private static func isDemoMonitorTarget(_ target: MonitorTarget) -> Bool {
        target.isDemo ||
        target.resourceLabel == "proj_token_radar_demo" ||
        target.resourceLabel == "chatgpt-codex-quota-demo"
    }

    private func providerSnapshotDetail(_ snapshot: ProviderUsageSnapshot) -> String {
        let tokens = snapshot.inputTokens + snapshot.outputTokens
        var parts = [
            "\(t("dashboard.month")) \(MoneyFormatter.usd(snapshot.spendUSD))"
        ]
        if let remaining = snapshot.remainingUSD {
            parts.append("\(t("dashboard.remaining")) \(MoneyFormatter.usd(remaining))")
        }
        if snapshot.requestCount > 0 {
            parts.append("\(snapshot.requestCount) \(t("monitoring.requests"))")
        }
        if tokens > 0 {
            parts.append("\(tokens) tok")
        }
        if !snapshot.groups.isEmpty {
            parts.append("\(snapshot.groups.count) group(s)")
        }
        return parts.joined(separator: " · ")
    }

    private func isCodexUsageRecord(_ record: UsageRecord) -> Bool {
        record.provider == .openAI &&
        record.source == .cliSessionLog &&
        (
            record.apiKeyLabel == "Codex" ||
            record.model.localizedCaseInsensitiveContains("codex")
        )
    }

    private func codexObservedTokens(_ record: UsageRecord) -> Int {
        record.inputTokens + record.cachedInputTokens + record.outputTokens
    }

    private func persistCodexImportCache(_ fileModificationTimes: [String: Double]) {
        guard !fileModificationTimes.isEmpty else { return }
        var next = settings
        next.codexImportedSessionFiles.merge(fileModificationTimes) { _, new in new }
        settings = next
        do {
            try settingsStore.save(next)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func truncated(_ text: String, limit: Int = 360) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    private static func normalizedSettings(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        if !normalized.monitorTargets.isEmpty,
           normalized.monitorTargets.allSatisfy({ !$0.isEnabled && $0.isLegacyStarterTarget }) {
            normalized.monitorTargets = []
        }
        normalized.monitorTargets.removeAll(where: Self.isDemoMonitorTarget)
        return normalized
    }

    private func defaultMonitorSource(for provider: ProviderKind) -> MonitorSourceKind {
        switch provider {
        case .vercelAIGateway:
            .providerUsageAPI
        case .cloudflareAIGateway:
            .aiGatewayLogs
        case .cloudflareWorkersAI, .gemini:
            .cloudBilling
        default:
            provider.supportsProviderBillingAPI ? .providerUsageAPI : .manualEstimate
        }
    }

    private func defaultMonitorScope(for provider: ProviderKind) -> MonitorScope {
        switch provider {
        case .vercelAIGateway, .cloudflareAIGateway:
            .gateway
        case .cloudflareWorkersAI:
            .worker
        default:
            .account
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func evaluateNotifications() {
        guard let alert = summary.alert else { return }
        let content = UNMutableNotificationContent()
        content.title = "Token Radar"
        content.body = budgetAlertMessage(alert)
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

}

private enum LiveTestError: LocalizedError {
    case invalidProxyURL
    case proxyNotRunning
    case httpStatus(Int, String)
    case noUsage

    var errorDescription: String? {
        switch self {
        case .invalidProxyURL:
            "Invalid local proxy URL."
        case .proxyNotRunning:
            "Local proxy did not start. Check the upstream credential, base URL, and port."
        case .httpStatus(let status, let body):
            "Local proxy returned HTTP \(status): \(body)"
        case .noUsage:
            "Upstream request succeeded but no usage object was returned, so Token Radar could not record this request."
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case monitoring
    case providers
    case proxy
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .monitoring:
            "Monitoring"
        case .providers:
            "Providers"
        case .proxy:
            "Local Proxy"
        case .settings:
            "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            "chart.xyaxis.line"
        case .monitoring:
            "scope"
        case .providers:
            "server.rack"
        case .proxy:
            "point.3.connected.trianglepath.dotted"
        case .settings:
            "gearshape"
        }
    }
}
