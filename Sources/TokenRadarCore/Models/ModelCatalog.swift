import Foundation

public struct TrackedModel: Identifiable, Codable, Equatable {
    public var id: String
    public var rank: Int
    public var displayName: String
    public var score: Int
    public var provider: ProviderKind
    public var aliases: [String]
    public var defaultModelID: String
    public var note: String

    public init(
        id: String,
        rank: Int,
        displayName: String,
        score: Int,
        provider: ProviderKind,
        aliases: [String],
        defaultModelID: String,
        note: String
    ) {
        self.id = id
        self.rank = rank
        self.displayName = displayName
        self.score = score
        self.provider = provider
        self.aliases = aliases
        self.defaultModelID = defaultModelID
        self.note = note
    }

    public func matches(modelName: String, provider: ProviderKind? = nil) -> Bool {
        let normalized = Self.normalize(modelName)
        let providerMatches = provider == nil || provider == self.provider
        return providerMatches && aliases.contains { normalized.contains(Self.normalize($0)) }
    }

    public static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

public enum ModelCatalog {
    public static let imageRanking: [TrackedModel] = [
        TrackedModel(
            id: "gpt-5-5",
            rank: 1,
            displayName: "GPT-5.5",
            score: 144,
            provider: .openAI,
            aliases: ["gpt-5.5", "gpt-5", "gpt-4.1", "gpt-4o"],
            defaultModelID: "gpt-5.5",
            note: "Tracked through OpenAI Costs/Usage API when available, or proxy usage."
        ),
        TrackedModel(
            id: "deepseek-v4",
            rank: 1,
            displayName: "Deepseek_v4",
            score: 144,
            provider: .deepSeek,
            aliases: ["deepseek-v4", "deepseek_v4", "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner"],
            defaultModelID: "deepseek-v4-pro",
            note: "DeepSeek exposes balance directly; per-model usage is captured through proxy or exported provider data."
        ),
        TrackedModel(
            id: "gemini",
            rank: 3,
            displayName: "Gemini",
            score: 142,
            provider: .gemini,
            aliases: ["gemini", "gemini-2.5", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
            defaultModelID: "gemini-2.5-pro",
            note: "Gemini remains estimate-first unless Google billing data is connected separately."
        ),
        TrackedModel(
            id: "opus-4-8",
            rank: 3,
            displayName: "Opus 4.8",
            score: 142,
            provider: .anthropic,
            aliases: ["opus-4.8", "claude-opus-4.8", "claude-opus", "opus"],
            defaultModelID: "claude-opus-4.8",
            note: "Tracked through Anthropic usage reports and proxy usage."
        ),
        TrackedModel(
            id: "kimi-2-6",
            rank: 5,
            displayName: "Kimi 2.6",
            score: 139,
            provider: .moonshotKimi,
            aliases: ["kimi-2.6", "kimi-k2", "kimi-k2.5", "moonshot-v1", "kimi"],
            defaultModelID: "kimi-k2.5",
            note: "Kimi is OpenAI-compatible; proxy usage is the primary MVP tracking path."
        ),
        TrackedModel(
            id: "sonnet-4-6",
            rank: 6,
            displayName: "Sonnet 4.6",
            score: 134,
            provider: .anthropic,
            aliases: ["sonnet-4.6", "claude-sonnet-4.6", "claude-sonnet", "sonnet"],
            defaultModelID: "claude-sonnet-4.6",
            note: "Tracked through Anthropic usage reports and proxy usage."
        ),
        TrackedModel(
            id: "glm-5-1",
            rank: 7,
            displayName: "GLM 5.1",
            score: 131,
            provider: .zhipuGLM,
            aliases: ["glm-5.1", "glm5.1", "glm-4.6", "glm-4-plus", "glm"],
            defaultModelID: "glm-5.1",
            note: "Tracked through proxy/OpenRouter-style usage until direct billing APIs are configured."
        ),
        TrackedModel(
            id: "doubao",
            rank: 7,
            displayName: "Doubao",
            score: 131,
            provider: .volcengineDoubao,
            aliases: ["doubao", "doubao-1-5", "doubao-1.5", "doubao-seed"],
            defaultModelID: "doubao-1-5-pro-32k-250115",
            note: "Tracked through ARK/OpenAI-compatible proxy usage."
        ),
        TrackedModel(
            id: "qwen-3-7",
            rank: 9,
            displayName: "Qwen 3.7",
            score: 130,
            provider: .alibabaQwen,
            aliases: ["qwen-3.7", "qwen3.7", "qwen3", "qwen-plus", "qwen-max", "qwen"],
            defaultModelID: "qwen-plus",
            note: "Tracked through DashScope compatible-mode proxy usage."
        ),
        TrackedModel(
            id: "minimax",
            rank: 10,
            displayName: "Minimax",
            score: 129,
            provider: .minimax,
            aliases: ["minimax", "minimax-m2.7", "m2.7", "abab"],
            defaultModelID: "minimax-m2.7",
            note: "Tracked through proxy usage."
        ),
        TrackedModel(
            id: "yuanbao",
            rank: 11,
            displayName: "Yuanbao",
            score: 118,
            provider: .tencentHunyuan,
            aliases: ["yuanbao", "hunyuan", "tencent-hunyuan", "hunyuan-turbos"],
            defaultModelID: "hunyuan-turbos-latest",
            note: "Yuanbao is mapped to Tencent Hunyuan API usage for monitoring."
        ),
        TrackedModel(
            id: "mimo",
            rank: 12,
            displayName: "Mimo",
            score: 102,
            provider: .xiaomiMimo,
            aliases: ["mimo", "mimo-v2.5", "mimo-v2-pro", "mimo-v2"],
            defaultModelID: "mimo-v2.5-pro",
            note: "Tracked through proxy usage while Xiaomi API billing support is normalized."
        ),
        TrackedModel(
            id: "gork",
            rank: 13,
            displayName: "Gork",
            score: 99,
            provider: .xAI,
            aliases: ["gork", "grok", "grok-4.3", "grok-4"],
            defaultModelID: "grok-4.3",
            note: "The image spells Gork; Token Radar also matches Grok/xAI model IDs."
        )
    ]

    public static func trackedModel(for modelName: String, provider: ProviderKind? = nil) -> TrackedModel? {
        imageRanking.first { $0.matches(modelName: modelName, provider: provider) }
            ?? imageRanking.first { $0.matches(modelName: modelName) }
    }
}

