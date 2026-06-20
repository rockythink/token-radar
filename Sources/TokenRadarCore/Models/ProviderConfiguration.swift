import Foundation

public struct ProviderConfiguration: Identifiable, Codable, Equatable {
    public var id: ProviderKind { provider }
    public var provider: ProviderKind
    public var isEnabled: Bool
    public var monthlyBudgetUSD: Decimal
    public var hardCapUSD: Decimal?
    public var baseURL: URL?
    public var resourceID: String
    public var apiKeyLabel: String
    public var pollIntervalMinutes: Int

    public init(
        provider: ProviderKind,
        isEnabled: Bool = false,
        monthlyBudgetUSD: Decimal = 25,
        hardCapUSD: Decimal? = nil,
        baseURL: URL? = nil,
        resourceID: String = "",
        apiKeyLabel: String = "Default",
        pollIntervalMinutes: Int = 60
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.hardCapUSD = hardCapUSD
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.resourceID = resourceID
        self.apiKeyLabel = apiKeyLabel
        self.pollIntervalMinutes = pollIntervalMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case isEnabled
        case monthlyBudgetUSD
        case hardCapUSD
        case baseURL
        case resourceID
        case apiKeyLabel
        case pollIntervalMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decode(ProviderKind.self, forKey: .provider)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.monthlyBudgetUSD = try container.decodeIfPresent(Decimal.self, forKey: .monthlyBudgetUSD) ?? 25
        self.hardCapUSD = try container.decodeIfPresent(Decimal.self, forKey: .hardCapUSD)
        self.baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL) ?? provider.defaultBaseURL
        self.resourceID = try container.decodeIfPresent(String.self, forKey: .resourceID) ?? ""
        self.apiKeyLabel = try container.decodeIfPresent(String.self, forKey: .apiKeyLabel) ?? "Default"
        self.pollIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .pollIntervalMinutes) ?? 60
    }
}

public struct AppSettings: Codable, Equatable {
    public var language: AppLanguage
    public var proxyPort: Int
    public var proxyEnabled: Bool
    public var defaultProxyProvider: ProviderKind
    public var automaticProviderRefreshEnabled: Bool
    public var providerRefreshIntervalMinutes: Int
    public var realtimeLocalSourceRefreshEnabled: Bool
    public var alertThresholds: [Decimal]
    public var providers: [ProviderConfiguration]
    public var subscriptions: [SubscriptionPlan]
    public var monitorTargets: [MonitorTarget]
    public var networkProxy: NetworkProxyConfiguration
    public var codexImportedSessionFiles: [String: Double]

    public init(
        language: AppLanguage = .system,
        proxyPort: Int = 8787,
        proxyEnabled: Bool = false,
        defaultProxyProvider: ProviderKind = .openAI,
        automaticProviderRefreshEnabled: Bool = false,
        providerRefreshIntervalMinutes: Int = 60,
        realtimeLocalSourceRefreshEnabled: Bool = true,
        alertThresholds: [Decimal] = [0.5, 0.8, 0.95],
        providers: [ProviderConfiguration] = ProviderKind.allCases.map({ ProviderConfiguration(provider: $0) }),
        subscriptions: [SubscriptionPlan] = [],
        monitorTargets: [MonitorTarget] = [],
        networkProxy: NetworkProxyConfiguration = NetworkProxyConfiguration(),
        codexImportedSessionFiles: [String: Double] = [:]
    ) {
        self.language = language
        self.proxyPort = proxyPort
        self.proxyEnabled = proxyEnabled
        self.defaultProxyProvider = defaultProxyProvider
        self.automaticProviderRefreshEnabled = automaticProviderRefreshEnabled
        self.providerRefreshIntervalMinutes = max(5, providerRefreshIntervalMinutes)
        self.realtimeLocalSourceRefreshEnabled = realtimeLocalSourceRefreshEnabled
        self.alertThresholds = alertThresholds
        self.providers = providers
        self.subscriptions = subscriptions
        self.monitorTargets = monitorTargets
        self.networkProxy = networkProxy
        self.codexImportedSessionFiles = codexImportedSessionFiles
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case proxyPort
        case proxyEnabled
        case defaultProxyProvider
        case automaticProviderRefreshEnabled
        case providerRefreshIntervalMinutes
        case realtimeLocalSourceRefreshEnabled
        case alertThresholds
        case providers
        case subscriptions
        case monitorTargets
        case networkProxy
        case codexImportedSessionFiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? 8787
        self.proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? false
        self.defaultProxyProvider = try container.decodeIfPresent(ProviderKind.self, forKey: .defaultProxyProvider) ?? .openAI
        self.automaticProviderRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticProviderRefreshEnabled) ?? false
        let decodedRefreshInterval = try container.decodeIfPresent(Int.self, forKey: .providerRefreshIntervalMinutes) ?? 60
        self.providerRefreshIntervalMinutes = max(5, decodedRefreshInterval)
        self.realtimeLocalSourceRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .realtimeLocalSourceRefreshEnabled) ?? true
        self.alertThresholds = try container.decodeIfPresent([Decimal].self, forKey: .alertThresholds) ?? [0.5, 0.8, 0.95]
        let decodedProviders = try container.decodeIfPresent([ProviderConfiguration].self, forKey: .providers)
        if let decodedProviders {
            let existing = Set(decodedProviders.map(\.provider))
            let missing = ProviderKind.allCases
                .filter { !existing.contains($0) }
                .map { ProviderConfiguration(provider: $0) }
            self.providers = decodedProviders + missing
        } else {
            self.providers = ProviderKind.allCases.map({ ProviderConfiguration(provider: $0) })
        }
        self.subscriptions = try container.decodeIfPresent([SubscriptionPlan].self, forKey: .subscriptions) ?? []
        self.monitorTargets = try container.decodeIfPresent([MonitorTarget].self, forKey: .monitorTargets) ?? []
        self.networkProxy = try container.decodeIfPresent(NetworkProxyConfiguration.self, forKey: .networkProxy) ?? NetworkProxyConfiguration()
        self.codexImportedSessionFiles = try container.decodeIfPresent([String: Double].self, forKey: .codexImportedSessionFiles) ?? [:]
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        case .english:
            "English"
        }
    }

    public var localizationCode: String? {
        switch self {
        case .system:
            nil
        case .simplifiedChinese:
            "zh-Hans"
        case .traditionalChinese:
            "zh-Hant"
        case .english:
            "en"
        }
    }
}
