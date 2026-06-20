import Foundation

public struct ProviderUsageSnapshot: Identifiable, Codable, Equatable {
    public var id: UUID
    public var provider: ProviderKind
    public var fetchedAt: Date
    public var periodStart: Date
    public var periodEnd: Date
    public var spendUSD: Decimal
    public var inputTokens: Int
    public var outputTokens: Int
    public var requestCount: Int
    public var remainingUSD: Decimal?
    public var monthlyBudgetUSD: Decimal?
    public var quotaConfidence: QuotaConfidence
    public var source: UsageSource
    public var groups: [UsageGroup]
    public var note: String?

    public init(
        id: UUID = UUID(),
        provider: ProviderKind,
        fetchedAt: Date = Date(),
        periodStart: Date,
        periodEnd: Date,
        spendUSD: Decimal,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        requestCount: Int = 0,
        remainingUSD: Decimal? = nil,
        monthlyBudgetUSD: Decimal? = nil,
        quotaConfidence: QuotaConfidence,
        source: UsageSource,
        groups: [UsageGroup] = [],
        note: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.spendUSD = spendUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestCount = requestCount
        self.remainingUSD = remainingUSD
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.quotaConfidence = quotaConfidence
        self.source = source
        self.groups = groups
        self.note = note
    }
}

public struct UsageGroup: Identifiable, Codable, Equatable {
    public var id: UUID
    public var provider: ProviderKind
    public var model: String?
    public var project: String?
    public var apiKeyLabel: String?
    public var spendUSD: Decimal
    public var inputTokens: Int
    public var outputTokens: Int
    public var requestCount: Int

    public init(
        id: UUID = UUID(),
        provider: ProviderKind,
        model: String? = nil,
        project: String? = nil,
        apiKeyLabel: String? = nil,
        spendUSD: Decimal,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        requestCount: Int = 0
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.project = project
        self.apiKeyLabel = apiKeyLabel
        self.spendUSD = spendUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestCount = requestCount
    }

    public var title: String {
        if let model, !model.isEmpty {
            return model
        }
        if let project, !project.isEmpty {
            return project
        }
        if let apiKeyLabel, !apiKeyLabel.isEmpty {
            return apiKeyLabel
        }
        return provider.displayName
    }
}

