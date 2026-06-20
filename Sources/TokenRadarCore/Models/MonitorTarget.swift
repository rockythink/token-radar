import Foundation

public enum MonitorSourceKind: String, CaseIterable, Codable, Identifiable {
    case providerUsageAPI
    case aiGatewayLogs
    case cloudBilling
    case localProxyDevice
    case cliSessionLog
    case subscriptionPlan
    case manualEstimate

    public var id: String { rawValue }
}

public enum MonitorScope: String, CaseIterable, Codable, Identifiable {
    case account
    case project
    case apiKey
    case gateway
    case worker
    case device
    case subscription

    public var id: String { rawValue }
}

public enum MonitorCoverage: String, Codable {
    case exactRemote
    case delayedRemote
    case localDeviceOnly
    case estimate
    case manual
}

public enum MonitorAccountKind: String, CaseIterable, Codable, Identifiable {
    case subscriptionUser
    case apiUser

    public var id: String { rawValue }
}

public struct MonitorTarget: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var accountKind: MonitorAccountKind
    public var provider: ProviderKind?
    public var source: MonitorSourceKind
    public var scope: MonitorScope
    public var resourceLabel: String
    public var modelPattern: String
    public var deviceLabel: String
    public var monthlyBudgetUSD: Decimal
    public var usesLocalProxy: Bool
    public var quotaWindows: [SubscriptionQuotaWindow]
    public var isDemo: Bool
    public var note: String

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        accountKind: MonitorAccountKind = .apiUser,
        provider: ProviderKind? = nil,
        source: MonitorSourceKind,
        scope: MonitorScope,
        resourceLabel: String = "",
        modelPattern: String = "",
        deviceLabel: String = "",
        monthlyBudgetUSD: Decimal = 25,
        usesLocalProxy: Bool = false,
        quotaWindows: [SubscriptionQuotaWindow] = [],
        isDemo: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.accountKind = accountKind
        self.provider = provider
        self.source = source
        self.scope = scope
        self.resourceLabel = resourceLabel
        self.modelPattern = modelPattern
        self.deviceLabel = deviceLabel
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.usesLocalProxy = usesLocalProxy
        self.quotaWindows = quotaWindows
        self.isDemo = isDemo
        self.note = note
    }

    public var coverage: MonitorCoverage {
        switch source {
        case .providerUsageAPI, .aiGatewayLogs:
            .exactRemote
        case .cloudBilling:
            .delayedRemote
        case .localProxyDevice, .cliSessionLog:
            .localDeviceOnly
        case .subscriptionPlan:
            .estimate
        case .manualEstimate:
            .manual
        }
    }

    public static let starterTargets: [MonitorTarget] = [
        MonitorTarget(
            name: "Vercel AI Gateway",
            isEnabled: false,
            provider: .vercelAIGateway,
            source: .providerUsageAPI,
            scope: .gateway,
            resourceLabel: "AI Gateway",
            monthlyBudgetUSD: 25,
            note: "Uses Vercel AI Gateway Usage & Billing API when credentials are configured."
        ),
        MonitorTarget(
            name: "Cloudflare AI Gateway",
            isEnabled: false,
            provider: .cloudflareAIGateway,
            source: .aiGatewayLogs,
            scope: .gateway,
            resourceLabel: "account_id/gateway_id",
            monthlyBudgetUSD: 25,
            note: "Uses Cloudflare AI Gateway logs, including model, tokens, cost, and status."
        ),
        MonitorTarget(
            name: "Cloudflare Workers AI",
            isEnabled: false,
            provider: .cloudflareWorkersAI,
            source: .cloudBilling,
            scope: .worker,
            resourceLabel: "Workers AI",
            monthlyBudgetUSD: 25,
            note: "Workers AI bills in Neurons; exact usage is visible in Cloudflare dashboard/analytics."
        ),
        MonitorTarget(
            name: "This Mac Local Proxy",
            isEnabled: false,
            source: .localProxyDevice,
            scope: .device,
            deviceLabel: Host.current().localizedName ?? "This Mac",
            monthlyBudgetUSD: 25,
            note: "Only covers requests routed through Token Radar on this Mac."
        ),
        MonitorTarget(
            name: "Claude Code Local Logs",
            isEnabled: false,
            accountKind: .subscriptionUser,
            provider: .anthropic,
            source: .cliSessionLog,
            scope: .device,
            resourceLabel: "~/.claude/projects",
            deviceLabel: Host.current().localizedName ?? "This Mac",
            monthlyBudgetUSD: 20,
            note: "Reads local Claude Code JSONL logs on this Mac."
        ),
        MonitorTarget(
            name: "GPT / Claude Subscription",
            isEnabled: false,
            accountKind: .subscriptionUser,
            source: .subscriptionPlan,
            scope: .subscription,
            monthlyBudgetUSD: 20,
            note: "Consumer subscriptions need OAuth/browser auth or manual quota entry."
        )
    ]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case accountKind
        case provider
        case source
        case scope
        case resourceLabel
        case modelPattern
        case deviceLabel
        case monthlyBudgetUSD
        case usesLocalProxy
        case quotaWindows
        case isDemo
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Monitor"
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.provider = try container.decodeIfPresent(ProviderKind.self, forKey: .provider)
        self.source = try container.decodeIfPresent(MonitorSourceKind.self, forKey: .source) ?? .manualEstimate
        self.scope = try container.decodeIfPresent(MonitorScope.self, forKey: .scope) ?? .project
        self.accountKind = try container.decodeIfPresent(MonitorAccountKind.self, forKey: .accountKind) ?? (source == .subscriptionPlan ? .subscriptionUser : .apiUser)
        self.resourceLabel = try container.decodeIfPresent(String.self, forKey: .resourceLabel) ?? ""
        self.modelPattern = try container.decodeIfPresent(String.self, forKey: .modelPattern) ?? ""
        self.deviceLabel = try container.decodeIfPresent(String.self, forKey: .deviceLabel) ?? ""
        self.monthlyBudgetUSD = try container.decodeIfPresent(Decimal.self, forKey: .monthlyBudgetUSD) ?? 25
        self.usesLocalProxy = try container.decodeIfPresent(Bool.self, forKey: .usesLocalProxy) ?? false
        self.quotaWindows = try container.decodeIfPresent([SubscriptionQuotaWindow].self, forKey: .quotaWindows) ?? []
        self.isDemo = try container.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public var isLegacyStarterTarget: Bool {
        Self.starterTargets.contains { template in
            template.name == name &&
            template.provider == provider &&
            template.source == source &&
            template.scope == scope &&
            template.resourceLabel == resourceLabel
        }
    }

    public func matches(_ record: UsageRecord) -> Bool {
        if let provider, record.provider != provider {
            return false
        }

        let trimmedPattern = modelPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPattern.isEmpty && !record.model.localizedCaseInsensitiveContains(trimmedPattern) {
            return false
        }

        if usesLocalProxy && record.source == .localProxy {
            return true
        }

        switch source {
        case .providerUsageAPI, .aiGatewayLogs:
            return record.source == .providerAPI
        case .cloudBilling:
            return record.source == .providerAPI || record.source == .estimate
        case .localProxyDevice:
            return record.source == .localProxy
        case .cliSessionLog:
            return record.source == .cliSessionLog
        case .subscriptionPlan:
            return record.source == .cliSessionLog || (usesLocalProxy && record.source == .localProxy)
        case .manualEstimate:
            return record.source == .estimate
        }
    }
}

public struct MonitorTargetSummary: Identifiable, Equatable {
    public var id: UUID { target.id }
    public var target: MonitorTarget
    public var spendUSD: Decimal
    public var tokenCount: Int
    public var requestCount: Int
    public var remainingBudgetUSD: Decimal
    public var utilization: Decimal
    public var quotaWindowSummaries: [QuotaWindowSummary]

    public init(
        target: MonitorTarget,
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.target = target
        let matched = records.filter(target.matches)
        let monthStart = DateRanges.startOfMonth(containing: now, calendar: calendar)
        let monthMatched = matched.filter { $0.timestamp >= monthStart }
        self.spendUSD = monthMatched.reduce(Decimal(0)) { $0 + $1.costUSD }
        self.tokenCount = monthMatched.reduce(0) { $0 + $1.totalTokens }
        self.requestCount = monthMatched.count
        self.remainingBudgetUSD = max(0, target.monthlyBudgetUSD - spendUSD)
        self.utilization = target.monthlyBudgetUSD > 0 ? min(1, spendUSD / target.monthlyBudgetUSD) : 0
        self.quotaWindowSummaries = QuotaWindowCalculator.summarizeAll(
            windows: target.quotaWindows,
            records: matched,
            now: now,
            calendar: calendar
        )
    }
}
