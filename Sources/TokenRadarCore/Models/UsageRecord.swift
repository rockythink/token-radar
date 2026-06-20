import Foundation

public struct UsageRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var provider: ProviderKind
    public var model: String
    public var project: String?
    public var apiKeyLabel: String?
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int
    public var costUSD: Decimal
    public var source: UsageSource

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        provider: ProviderKind,
        model: String,
        project: String? = nil,
        apiKeyLabel: String? = nil,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int,
        reasoningOutputTokens: Int = 0,
        costUSD: Decimal,
        source: UsageSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.project = project
        self.apiKeyLabel = apiKeyLabel
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.costUSD = costUSD
        self.source = source
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case provider
        case model
        case project
        case apiKeyLabel
        case inputTokens
        case cachedInputTokens
        case outputTokens
        case reasoningOutputTokens
        case costUSD
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        provider = try container.decode(ProviderKind.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        apiKeyLabel = try container.decodeIfPresent(String.self, forKey: .apiKeyLabel)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        reasoningOutputTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        costUSD = try container.decode(Decimal.self, forKey: .costUSD)
        source = try container.decode(UsageSource.self, forKey: .source)
    }
}
