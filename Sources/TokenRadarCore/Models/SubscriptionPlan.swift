import Foundation

public enum SubscriptionQuotaUnit: String, CaseIterable, Codable, Identifiable {
    case messages
    case tokens
    case requests
    case usd

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .messages:
            "Messages"
        case .tokens:
            "Tokens"
        case .requests:
            "Requests"
        case .usd:
            "USD"
        }
    }
}

public enum QuotaWindowKind: String, CaseIterable, Codable, Identifiable {
    case fiveHours
    case daily
    case weekly
    case monthly
    case customHours

    public var id: String { rawValue }

    public var defaultName: String {
        switch self {
        case .fiveHours:
            "5-hour window"
        case .daily:
            "Daily quota"
        case .weekly:
            "Weekly quota"
        case .monthly:
            "Monthly quota"
        case .customHours:
            "Custom window"
        }
    }
}

public struct SubscriptionQuotaWindow: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var kind: QuotaWindowKind
    public var includedUnits: Decimal
    public var quotaUnit: SubscriptionQuotaUnit
    public var customHours: Int
    public var providerRemainingRatio: Decimal?
    public var providerResetAt: Date?
    public var providerResetLabel: String
    public var providerReportedAt: Date?
    public var note: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        kind: QuotaWindowKind = .monthly,
        includedUnits: Decimal = 0,
        quotaUnit: SubscriptionQuotaUnit = .messages,
        customHours: Int = 24,
        providerRemainingRatio: Decimal? = nil,
        providerResetAt: Date? = nil,
        providerResetLabel: String = "",
        providerReportedAt: Date? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name.isEmpty ? kind.defaultName : name
        self.isEnabled = isEnabled
        self.kind = kind
        self.includedUnits = max(0, includedUnits)
        self.quotaUnit = quotaUnit
        self.customHours = min(24 * 31, max(1, customHours))
        self.providerRemainingRatio = Self.clampedRatio(providerRemainingRatio)
        self.providerResetAt = providerResetAt
        self.providerResetLabel = providerResetLabel
        self.providerReportedAt = providerReportedAt
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case kind
        case includedUnits
        case quotaUnit
        case customHours
        case providerRemainingRatio
        case providerResetAt
        case providerResetLabel
        case providerReportedAt
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(QuotaWindowKind.self, forKey: .kind) ?? .monthly
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = name.isEmpty ? kind.defaultName : name
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.kind = kind
        self.includedUnits = max(0, try container.decodeIfPresent(Decimal.self, forKey: .includedUnits) ?? 0)
        self.quotaUnit = try container.decodeIfPresent(SubscriptionQuotaUnit.self, forKey: .quotaUnit) ?? .messages
        self.customHours = min(24 * 31, max(1, try container.decodeIfPresent(Int.self, forKey: .customHours) ?? 24))
        self.providerRemainingRatio = Self.clampedRatio(try container.decodeIfPresent(Decimal.self, forKey: .providerRemainingRatio))
        self.providerResetAt = try container.decodeIfPresent(Date.self, forKey: .providerResetAt)
        self.providerResetLabel = try container.decodeIfPresent(String.self, forKey: .providerResetLabel) ?? ""
        self.providerReportedAt = try container.decodeIfPresent(Date.self, forKey: .providerReportedAt)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    private static func clampedRatio(_ ratio: Decimal?) -> Decimal? {
        guard let ratio else { return nil }
        return min(Decimal(1), max(Decimal(0), ratio))
    }
}

public enum SubscriptionSyncSource: String, CaseIterable, Codable, Identifiable {
    case manual
    case localProxy
    case cliSessionLog
    case providerAPI
    case browserSession

    public var id: String { rawValue }
}

public enum ProviderAuthMethod: String, Codable {
    case apiKey
    case adminAPIKey
    case aiGatewayKey
    case browserSession
    case notAvailable
}

public struct SubscriptionPlan: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var provider: ProviderKind?
    public var modelPattern: String
    public var monthlyFeeUSD: Decimal
    public var includedUnits: Decimal
    public var quotaUnit: SubscriptionQuotaUnit
    public var resetDay: Int
    public var overageUnitPriceUSD: Decimal?
    public var syncSource: SubscriptionSyncSource
    public var quotaWindows: [SubscriptionQuotaWindow]

    public init(
        id: UUID = UUID(),
        name: String = "New Subscription",
        isEnabled: Bool = true,
        provider: ProviderKind? = nil,
        modelPattern: String = "",
        monthlyFeeUSD: Decimal = 20,
        includedUnits: Decimal = 1_000_000,
        quotaUnit: SubscriptionQuotaUnit = .tokens,
        resetDay: Int = 1,
        overageUnitPriceUSD: Decimal? = nil,
        syncSource: SubscriptionSyncSource = .manual,
        quotaWindows: [SubscriptionQuotaWindow] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.provider = provider
        self.modelPattern = modelPattern
        self.monthlyFeeUSD = monthlyFeeUSD
        self.includedUnits = includedUnits
        self.quotaUnit = quotaUnit
        self.resetDay = min(28, max(1, resetDay))
        self.overageUnitPriceUSD = overageUnitPriceUSD
        self.syncSource = syncSource
        self.quotaWindows = quotaWindows
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case provider
        case modelPattern
        case monthlyFeeUSD
        case includedUnits
        case quotaUnit
        case resetDay
        case overageUnitPriceUSD
        case syncSource
        case quotaWindows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Subscription"
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.provider = try container.decodeIfPresent(ProviderKind.self, forKey: .provider)
        self.modelPattern = try container.decodeIfPresent(String.self, forKey: .modelPattern) ?? ""
        self.monthlyFeeUSD = try container.decodeIfPresent(Decimal.self, forKey: .monthlyFeeUSD) ?? 20
        self.includedUnits = try container.decodeIfPresent(Decimal.self, forKey: .includedUnits) ?? 1_000_000
        self.quotaUnit = try container.decodeIfPresent(SubscriptionQuotaUnit.self, forKey: .quotaUnit) ?? .tokens
        self.resetDay = min(28, max(1, try container.decodeIfPresent(Int.self, forKey: .resetDay) ?? 1))
        self.overageUnitPriceUSD = try container.decodeIfPresent(Decimal.self, forKey: .overageUnitPriceUSD)
        self.syncSource = try container.decodeIfPresent(SubscriptionSyncSource.self, forKey: .syncSource) ?? .manual
        self.quotaWindows = try container.decodeIfPresent([SubscriptionQuotaWindow].self, forKey: .quotaWindows) ?? []
    }
}

public struct SubscriptionSummary: Identifiable, Equatable {
    public var id: UUID { plan.id }
    public var plan: SubscriptionPlan
    public var periodStart: Date
    public var periodEnd: Date
    public var usedUnits: Decimal
    public var remainingUnits: Decimal
    public var utilization: Decimal
    public var projectedUnits: Decimal
    public var amortizedCostToDateUSD: Decimal
    public var effectiveUnitCostUSD: Decimal?
    public var projectedOverageUnits: Decimal
    public var projectedOverageCostUSD: Decimal

    public init(
        plan: SubscriptionPlan,
        periodStart: Date,
        periodEnd: Date,
        usedUnits: Decimal,
        remainingUnits: Decimal,
        utilization: Decimal,
        projectedUnits: Decimal,
        amortizedCostToDateUSD: Decimal,
        effectiveUnitCostUSD: Decimal?,
        projectedOverageUnits: Decimal,
        projectedOverageCostUSD: Decimal
    ) {
        self.plan = plan
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.usedUnits = usedUnits
        self.remainingUnits = remainingUnits
        self.utilization = utilization
        self.projectedUnits = projectedUnits
        self.amortizedCostToDateUSD = amortizedCostToDateUSD
        self.effectiveUnitCostUSD = effectiveUnitCostUSD
        self.projectedOverageUnits = projectedOverageUnits
        self.projectedOverageCostUSD = projectedOverageCostUSD
    }
}
