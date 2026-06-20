import SwiftUI
import TokenRadarCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    var isEmbedded = false
    @State private var apiKeyInputs: [ProviderKind: String] = [:]

    private var providerRefreshIntervalOptions: [Int] {
        Array(Set([15, 30, 60, 120, 360, store.settings.providerRefreshIntervalMinutes]))
            .map { min(24 * 60, max(5, $0)) }
            .sorted()
    }

    private var manualSubscriptionTemplates: [ManualSubscriptionTemplate] {
        [
            ManualSubscriptionTemplate(name: "ChatGPT Plus", provider: .openAI, monthlyFeeUSD: 20),
            ManualSubscriptionTemplate(name: "ChatGPT Pro $100", provider: .openAI, monthlyFeeUSD: 100),
            ManualSubscriptionTemplate(name: "ChatGPT Pro $200", provider: .openAI, monthlyFeeUSD: 200),
            ManualSubscriptionTemplate(name: "Claude Pro", provider: .anthropic, monthlyFeeUSD: 20),
            ManualSubscriptionTemplate(name: "Claude Max 5x", provider: .anthropic, monthlyFeeUSD: 100),
            ManualSubscriptionTemplate(name: "Claude Max 20x", provider: .anthropic, monthlyFeeUSD: 200)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isEmbedded {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.t("settings.control_center"))
                            .font(.system(size: 26, weight: .semibold))
                        Text(store.t("settings.control_center_subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.selectedSection = .monitoring
                    } label: {
                        Label(store.t("nav.monitoring"), systemImage: "scope")
                    }
                    Button {
                        store.toggleProxy()
                    } label: {
                        Label(store.isProxyRunning ? store.t("menu.pause_proxy") : store.t("menu.start_proxy"), systemImage: store.isProxyRunning ? "pause.circle" : "play.circle")
                    }
                }
                SettingsControlStrip(store: store)
            }

            TabView {
                generalTab
                    .tabItem {
                        Label(store.t("settings.language"), systemImage: "globe")
                    }

                authTab
                    .tabItem {
                        Label(store.t("auth.title"), systemImage: "key.viewfinder")
                    }

                providersTab
                    .tabItem {
                        Label(store.t("settings.providers"), systemImage: "server.rack")
                    }

                subscriptionsTab
                    .tabItem {
                        Label(store.t("subscription.title"), systemImage: "creditcard")
                    }

                proxyTab
                    .tabItem {
                        Label(store.t("settings.proxy"), systemImage: "point.3.connected.trianglepath.dotted")
                    }

                alertsTab
                    .tabItem {
                        Label(store.t("settings.alerts"), systemImage: "bell")
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(.background)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    HStack(spacing: 14) {
                        Label(store.t("settings.language"), systemImage: "globe")
                            .font(.headline)
                        Spacer()
                        Picker(store.t("settings.language_subtitle"), selection: Binding(
                            get: { store.settings.language },
                            set: { value in
                                store.setLanguage(value)
                            }
                        )) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName)
                                    .tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(store.t("settings.refresh_automation"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)

                        Toggle(store.t("settings.realtime_local_sources"), isOn: Binding(
                            get: { store.settings.realtimeLocalSourceRefreshEnabled },
                            set: { value in
                                store.updateSettings(reconfigureProxy: false) {
                                    $0.realtimeLocalSourceRefreshEnabled = value
                                }
                            }
                        ))
                        .toggleStyle(.switch)

                        Text(store.t("settings.realtime_local_sources_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Toggle(store.t("settings.auto_provider_refresh"), isOn: Binding(
                            get: { store.settings.automaticProviderRefreshEnabled },
                            set: { value in
                                store.updateSettings(reconfigureProxy: false) {
                                    $0.automaticProviderRefreshEnabled = value
                                }
                            }
                        ))
                        .toggleStyle(.switch)

                        HStack {
                            Text(store.t("settings.provider_refresh_interval"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker(store.t("settings.provider_refresh_interval"), selection: Binding(
                                get: { store.settings.providerRefreshIntervalMinutes },
                                set: { value in
                                    store.updateSettings(reconfigureProxy: false) {
                                        $0.providerRefreshIntervalMinutes = min(24 * 60, max(5, value))
                                    }
                                }
                            )) {
                                ForEach(providerRefreshIntervalOptions, id: \.self) { minutes in
                                    Text(intervalLabel(minutes)).tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                            .disabled(!store.settings.automaticProviderRefreshEnabled)
                        }

                        Text(store.t("settings.auto_provider_refresh_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        return "\(hours) h"
    }

    private var authTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.t("auth.title"))
                        .font(.title3.weight(.semibold))
                    Text(store.t("auth.subtitle"))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(ProviderKind.allCases) { provider in
                        AuthProviderCard(
                            provider: provider,
                            hasCredential: store.credentialState[provider] == true,
                            usageAuthText: store.authMethodLabel(provider.usageAuthMethod),
                            officialUsageText: provider.supportsProviderBillingAPI ? store.t("auth.official_usage_yes") : store.t("auth.official_usage_no"),
                            officialSubscriptionText: provider.supportsOfficialSubscriptionSync ? store.t("auth.subscription_yes") : store.t("auth.subscription_no"),
                            credentialSavedText: store.t("providers.credential_saved"),
                            noCredentialText: store.t("providers.no_credential"),
                            authLabel: store.t("auth.label_auth"),
                            usageLabel: store.t("auth.label_usage"),
                            subscriptionLabel: store.t("auth.label_subscription"),
                            credentialLabel: store.t("auth.label_credential")
                        )
                    }
                }

                StatusBanner(
                    title: store.t("auth.consumer_title"),
                    message: store.t("auth.consumer_note"),
                    symbol: "person.crop.circle.badge.exclamationmark",
                    tint: .orange
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(store.t("auth.local_session_title"), systemImage: "terminal")
                            .font(.headline)
                        Spacer()
                        Button {
                            store.syncCodexSessionQuotas()
                        } label: {
                            Label(store.t("auth.import_codex_quota"), systemImage: "gauge.with.dots.needle.50percent")
                        }
                        Button {
                            store.syncLocalSessionLogs()
                        } label: {
                            Label(store.t("auth.import_sessions"), systemImage: "arrow.down.doc")
                        }
                    }

                    Text(store.t("auth.local_session_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let result = store.lastSessionImportResult {
                        Text("\(store.t("status.session_imported_prefix")) \(result.imported) \(store.t("status.session_imported_suffix")) · \(result.filesScanned) JSONL")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let result = store.lastCodexQuotaSyncResult {
                        Text("\(store.t("status.codex_quota_synced_prefix")) \(result.snapshots.count) \(store.t("status.codex_quota_synced_suffix")) · \(result.filesScanned) JSONL")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.trailing, 8)
        }
    }

    private var providersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProviderKind.allCases) { provider in
                    ProviderSettingsRow(
                        provider: provider,
                        configuration: store.providerConfiguration(for: provider),
                        hasCredential: store.credentialState[provider] == true,
                        apiKeyText: Binding(
                            get: { apiKeyInputs[provider] ?? "" },
                            set: { apiKeyInputs[provider] = $0 }
                        ),
                        onConfigurationChange: { mutate in
                            store.updateProvider(provider, mutate: mutate)
                        },
                        onSaveKey: {
                            let key = apiKeyInputs[provider] ?? ""
                            guard !key.isEmpty else { return }
                            store.saveAPIKey(key, for: provider)
                            apiKeyInputs[provider] = ""
                        },
                        onDeleteKey: {
                            store.deleteAPIKey(for: provider)
                        },
                        enabledText: store.t("providers.enabled"),
                        saveKeyText: store.t("settings.save_key"),
                        deleteText: store.t("settings.delete"),
                        savedText: store.t("settings.saved"),
                        missingText: store.t("settings.missing"),
                        baseURLText: store.t("settings.base_url"),
                        resourceIDText: store.t("settings.resource_id"),
                        budgetText: store.t("settings.budget"),
                        hardCapText: store.t("settings.hard_cap"),
                        officialText: store.t("providers.official"),
                        estimateText: store.t("providers.estimate")
                    )
                }
            }
            .padding(.trailing, 8)
        }
    }

    private var subscriptionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("subscription.title"))
                            .font(.title3.weight(.semibold))
                        Text(store.t("subscription.settings_subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.addSubscription()
                    } label: {
                        Label(store.t("subscription.add"), systemImage: "plus")
                    }
                }

                ManualSubscriptionTemplatePanel(
                    store: store,
                    templates: manualSubscriptionTemplates,
                    onAdd: { template in
                        store.addSubscription(template.makePlan())
                    }
                )

                if store.settings.subscriptions.isEmpty {
                    Text(store.t("subscription.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    ForEach(store.settings.subscriptions) { plan in
                        SubscriptionSettingsRow(
                            plan: plan,
                            store: store,
                            onUpdate: { mutate in
                                store.updateSubscription(plan.id, mutate: mutate)
                            },
                            onDelete: {
                                store.deleteSubscription(id: plan.id)
                            }
                        )
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    private var proxyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(store.t("settings.enable_proxy"), isOn: Binding(
                            get: { store.settings.proxyEnabled },
                            set: { value in
                                store.updateSettings(reconfigureProxy: false) { $0.proxyEnabled = value }
                                value ? store.startProxy() : store.stopProxy()
                            }
                        ))
                        .toggleStyle(.switch)

                        HStack {
                            Text(store.t("settings.default_upstream"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker(store.t("settings.default_upstream"), selection: Binding(
                                get: { store.settings.defaultProxyProvider },
                                set: { value in
                                    store.updateSettings { $0.defaultProxyProvider = value }
                                }
                            )) {
                                ForEach(ProviderKind.allCases) { provider in
                                    ProviderPickerItem(provider: provider)
                                        .tag(provider)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        Stepper(value: Binding(
                            get: { store.settings.proxyPort },
                            set: { value in
                                store.updateSettings { $0.proxyPort = value }
                            }
                        ), in: 1024...65535) {
                            Text("\(store.t("settings.port")) \(store.settings.proxyPort)")
                        }

                        Text("\(store.t("settings.proxy_hint")) `http://localhost:\(store.settings.proxyPort)`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.t("network_proxy.section"))
                            .font(.headline)

                        Picker(store.t("network_proxy.title"), selection: Binding(
                            get: { store.settings.networkProxy.mode },
                            set: { mode in
                                store.updateSettings {
                                    $0.networkProxy.mode = mode
                                }
                            }
                        )) {
                            ForEach(NetworkProxyMode.allCases) { mode in
                                Text(store.networkProxyModeLabel(mode)).tag(mode)
                            }
                        }
                        .frame(maxWidth: 280)

                        if store.settings.networkProxy.mode == .http || store.settings.networkProxy.mode == .socks {
                            HStack {
                                TextField(store.t("network_proxy.host"), text: Binding(
                                    get: { store.settings.networkProxy.host },
                                    set: { value in
                                        store.updateSettings {
                                            $0.networkProxy.host = value
                                        }
                                    }
                                ))
                                TextField(store.t("network_proxy.port"), value: Binding(
                                    get: { store.settings.networkProxy.port },
                                    set: { value in
                                        store.updateSettings {
                                            $0.networkProxy.port = max(1, min(65535, value))
                                        }
                                    }
                                ), format: .number)
                                .frame(width: 100)
                            }

                            HStack {
                                Button("Clash 7890") {
                                    store.updateSettings {
                                        $0.networkProxy.mode = .http
                                        $0.networkProxy.host = "127.0.0.1"
                                        $0.networkProxy.port = 7890
                                    }
                                }
                                Button("Surge 6152") {
                                    store.updateSettings {
                                        $0.networkProxy.mode = .http
                                        $0.networkProxy.host = "127.0.0.1"
                                        $0.networkProxy.port = 6152
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(store.t("network_proxy.help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    private var alertsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ThresholdToggle(store: store, threshold: Decimal(string: "0.5")!, label: store.t("settings.threshold_50"))
                        ThresholdToggle(store: store, threshold: Decimal(string: "0.8")!, label: store.t("settings.threshold_80"))
                        ThresholdToggle(store: store, threshold: Decimal(string: "0.95")!, label: store.t("settings.threshold_95"))
                        Text(store.t("settings.projected_note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsControlStrip: View {
    @ObservedObject var store: AppStore

    private var enabledMonitorCount: Int {
        store.settings.monitorTargets.filter(\.isEnabled).count
    }

    private var savedCredentialCount: Int {
        store.credentialState.values.filter { $0 }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsControlMetric(
                title: store.t("sidebar.monitors"),
                value: "\(enabledMonitorCount)/\(store.settings.monitorTargets.count)",
                symbol: "scope",
                tint: .orange
            )
            SettingsControlMetric(
                title: store.t("auth.label_credential"),
                value: "\(savedCredentialCount)",
                symbol: "key.viewfinder",
                tint: .cyan
            )
            SettingsControlMetric(
                title: store.t("dashboard.fixed_cost"),
                value: MoneyFormatter.compactUSD(store.monthlySubscriptionFeesUSD),
                symbol: "creditcard",
                tint: .blue
            )
            SettingsControlMetric(
                title: store.t("nav.proxy"),
                value: store.isProxyRunning ? store.t("proxy.running") : store.t("proxy.paused"),
                symbol: store.isProxyRunning ? "checkmark.circle.fill" : "pause.circle",
                tint: store.isProxyRunning ? .green : .secondary
            )
        }
    }
}

private struct SettingsControlMetric: View {
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

private struct ManualSubscriptionTemplate: Identifiable {
    var id: String { name }
    var name: String
    var provider: ProviderKind
    var monthlyFeeUSD: Decimal

    func makePlan() -> SubscriptionPlan {
        SubscriptionPlan(
            name: name,
            provider: provider,
            modelPattern: "",
            monthlyFeeUSD: monthlyFeeUSD,
            includedUnits: 0,
            quotaUnit: .messages,
            resetDay: 1,
            syncSource: .manual
        )
    }
}

private struct ManualSubscriptionTemplatePanel: View {
    @ObservedObject var store: AppStore
    var templates: [ManualSubscriptionTemplate]
    var onAdd: (ManualSubscriptionTemplate) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 10)
    ]

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("subscription.manual_config_title"))
                            .font(.headline)
                        Text(store.t("subscription.manual_config_note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("subscription.quick_templates"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(templates) { template in
                            Button {
                                onAdd(template)
                            } label: {
                                HStack(spacing: 8) {
                                    ProviderIconView(provider: template.provider, size: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        Text("\(MoneyFormatter.usd(template.monthlyFeeUSD)) / \(store.t("monitoring.per_month")) · \(store.t("subscription.sync_manual"))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Text(store.t("subscription.template_fee_editable"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SubscriptionSettingsRow: View {
    var plan: SubscriptionPlan
    @ObservedObject var store: AppStore
    var onUpdate: ((inout SubscriptionPlan) -> Void) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(store.t("subscription.name"), text: Binding(
                    get: { plan.name },
                    set: { value in onUpdate { $0.name = value } }
                ))
                .font(.headline)
                .textFieldStyle(.roundedBorder)

                Toggle(store.t("providers.enabled"), isOn: Binding(
                    get: { plan.isEnabled },
                    set: { value in onUpdate { $0.isEnabled = value } }
                ))
                .toggleStyle(.switch)

                Button(store.t("settings.delete"), role: .destructive, action: onDelete)
            }

            HStack {
                Picker(store.t("subscription.provider"), selection: Binding(
                    get: { plan.provider?.rawValue ?? "any" },
                    set: { value in
                        onUpdate { $0.provider = value == "any" ? nil : ProviderKind(rawValue: value) }
                    }
                )) {
                    Text(store.t("subscription.any_provider")).tag("any")
                    ForEach(ProviderKind.allCases) { provider in
                        ProviderPickerItem(provider: provider).tag(provider.rawValue)
                    }
                }
                .frame(maxWidth: 240)

                TextField(store.t("subscription.model_pattern"), text: Binding(
                    get: { plan.modelPattern },
                    set: { value in onUpdate { $0.modelPattern = value } }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                TextField(store.t("subscription.monthly_fee"), value: Binding(
                    get: { plan.monthlyFeeUSD.doubleValue },
                    set: { value in onUpdate { $0.monthlyFeeUSD = Decimal(value) } }
                ), format: .currency(code: "USD"))
                .frame(width: 130)

                TextField(store.t("subscription.included_units"), value: Binding(
                    get: { plan.includedUnits.doubleValue },
                    set: { value in onUpdate { $0.includedUnits = max(0, Decimal(value)) } }
                ), format: .number)
                .frame(width: 150)

                Picker(store.t("subscription.unit"), selection: Binding(
                    get: { plan.quotaUnit },
                    set: { value in onUpdate { $0.quotaUnit = value } }
                )) {
                    ForEach(SubscriptionQuotaUnit.allCases) { unit in
                        Text(store.quotaUnitLabel(unit)).tag(unit)
                    }
                }
                .frame(width: 150)
            }

            HStack {
                Stepper(value: Binding(
                    get: { plan.resetDay },
                    set: { value in onUpdate { $0.resetDay = min(28, max(1, value)) } }
                ), in: 1...28) {
                    Text("\(store.t("subscription.reset_day")) \(plan.resetDay)")
                }

                TextField(store.t("subscription.overage_price"), value: Binding(
                    get: { plan.overageUnitPriceUSD?.doubleValue ?? 0 },
                    set: { value in onUpdate { $0.overageUnitPriceUSD = value > 0 ? Decimal(value) : nil } }
                ), format: .currency(code: "USD"))
                .frame(width: 150)
            }

            HStack {
                Picker(store.t("subscription.sync_source"), selection: Binding(
                    get: { plan.syncSource },
                    set: { value in onUpdate { $0.syncSource = value } }
                )) {
                    ForEach(SubscriptionSyncSource.allCases) { source in
                        Text(store.subscriptionSyncLabel(source)).tag(source)
                    }
                }
                .frame(maxWidth: 260)

                let authStatus = store.subscriptionAuthStatus(for: plan)
                Label(authStatus.message, systemImage: authStatus.symbol)
                    .font(.caption)
                    .foregroundStyle(authStatus.isReady ? .green : .orange)
                    .lineLimit(2)
            }

            if let summary = store.subscriptionSummaries.first(where: { $0.plan.id == plan.id }) {
                VStack(alignment: .leading, spacing: 6) {
                    if plan.includedUnits > 0 {
                        HStack {
                            Text("\(store.t("subscription.used")) \(formatUnits(summary.usedUnits, unit: plan.quotaUnit))")
                            Spacer()
                            Text("\(store.t("subscription.remaining")) \(formatUnits(summary.remainingUnits, unit: plan.quotaUnit))")
                            Spacer()
                            Text(MoneyFormatter.percent(summary.utilization))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        SpendProgressBar(value: summary.usedUnits, maxValue: plan.includedUnits, tint: summary.utilization > Decimal(string: "0.9")! ? .orange : .blue)
                    } else {
                        Label(store.t("subscription.quota_not_set"), systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatUnits(_ units: Decimal, unit: SubscriptionQuotaUnit) -> String {
        switch unit {
        case .messages:
            return "\(Int(units.doubleValue))"
        case .tokens:
            let value = units.doubleValue
            if value >= 1_000_000 {
                return String(format: "%.1fM", value / 1_000_000)
            }
            if value >= 1_000 {
                return String(format: "%.0fk", value / 1_000)
            }
            return "\(Int(value))"
        case .requests:
            return "\(Int(units.doubleValue))"
        case .usd:
            return MoneyFormatter.usd(units)
        }
    }
}

struct AuthProviderCard: View {
    var provider: ProviderKind
    var hasCredential: Bool
    var usageAuthText: String
    var officialUsageText: String
    var officialSubscriptionText: String
    var credentialSavedText: String
    var noCredentialText: String
    var authLabel: String
    var usageLabel: String
    var subscriptionLabel: String
    var credentialLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProviderIconView(provider: provider, size: 24)
                Text(provider.displayName)
                    .font(.headline)
                    .foregroundStyle(hasCredential ? .green : .primary)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(hasCredential ? .green : .secondary)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                AuthLine(title: authLabel, value: usageAuthText, symbol: "key.horizontal")
                AuthLine(title: usageLabel, value: officialUsageText, symbol: "chart.bar")
                AuthLine(title: subscriptionLabel, value: officialSubscriptionText, symbol: "creditcard")
                AuthLine(title: credentialLabel, value: hasCredential ? credentialSavedText : noCredentialText, symbol: hasCredential ? "lock.fill" : "lock.open")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AuthLine: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(title)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct ProviderSettingsRow: View {
    var provider: ProviderKind
    var configuration: ProviderConfiguration
    var hasCredential: Bool
    @Binding var apiKeyText: String
    var onConfigurationChange: ((inout ProviderConfiguration) -> Void) -> Void
    var onSaveKey: () -> Void
    var onDeleteKey: () -> Void
    var enabledText: String
    var saveKeyText: String
    var deleteText: String
    var savedText: String
    var missingText: String
    var baseURLText: String
    var resourceIDText: String
    var budgetText: String
    var hardCapText: String
    var officialText: String
    var estimateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProviderIconView(provider: provider, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.headline)
                    Text(provider.supportsProviderBillingAPI ? officialText : estimateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(enabledText, isOn: Binding(
                    get: { configuration.isEnabled },
                    set: { value in
                        onConfigurationChange { $0.isEnabled = value }
                    }
                ))
                .toggleStyle(.switch)
            }

            HStack {
                SecureField(provider.credentialLabel, text: $apiKeyText)
                Button(saveKeyText, action: onSaveKey)
                Button(deleteText, role: .destructive, action: onDeleteKey)
                Label(hasCredential ? savedText : missingText, systemImage: hasCredential ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(hasCredential ? .green : .secondary)
            }

            HStack {
                TextField(baseURLText, text: Binding(
                    get: { configuration.baseURL?.absoluteString ?? "" },
                    set: { value in
                        onConfigurationChange { $0.baseURL = URL(string: value) }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                TextField(resourceIDText, text: Binding(
                    get: { configuration.resourceID },
                    set: { value in
                        onConfigurationChange { $0.resourceID = value }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                TextField(budgetText, value: Binding(
                    get: { configuration.monthlyBudgetUSD.doubleValue },
                    set: { value in
                        onConfigurationChange { $0.monthlyBudgetUSD = Decimal(value) }
                    }
                ), format: .currency(code: "USD"))
                .frame(width: 120)

                TextField(hardCapText, value: Binding(
                    get: { configuration.hardCapUSD?.doubleValue ?? 0 },
                    set: { value in
                        onConfigurationChange { $0.hardCapUSD = value > 0 ? Decimal(value) : nil }
                    }
                ), format: .currency(code: "USD"))
                .frame(width: 120)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ThresholdToggle: View {
    @ObservedObject var store: AppStore
    var threshold: Decimal
    var label: String

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { store.settings.alertThresholds.contains(threshold) },
            set: { enabled in
                if enabled {
                    store.updateSettings(reconfigureProxy: false) { settings in
                        if !settings.alertThresholds.contains(threshold) {
                            settings.alertThresholds.append(threshold)
                        }
                    }
                } else {
                    store.updateSettings(reconfigureProxy: false) { settings in
                        settings.alertThresholds.removeAll { $0 == threshold }
                    }
                }
            }
        ))
    }
}
