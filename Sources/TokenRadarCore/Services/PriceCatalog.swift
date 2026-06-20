import Foundation

public struct ModelPrice: Equatable {
    public var inputPerMillionUSD: Decimal
    public var outputPerMillionUSD: Decimal

    public init(inputPerMillionUSD: Decimal, outputPerMillionUSD: Decimal) {
        self.inputPerMillionUSD = inputPerMillionUSD
        self.outputPerMillionUSD = outputPerMillionUSD
    }
}

public enum PriceCatalog {
    private static let prices: [ProviderKind: [String: ModelPrice]] = [
        .openAI: [
            "gpt-4.1": ModelPrice(inputPerMillionUSD: 2, outputPerMillionUSD: 8),
            "gpt-4.1-mini": ModelPrice(inputPerMillionUSD: Decimal(string: "0.4")!, outputPerMillionUSD: Decimal(string: "1.6")!),
            "gpt-4o": ModelPrice(inputPerMillionUSD: Decimal(string: "2.5")!, outputPerMillionUSD: 10),
            "gpt-4o-mini": ModelPrice(inputPerMillionUSD: Decimal(string: "0.15")!, outputPerMillionUSD: Decimal(string: "0.6")!)
        ],
        .anthropic: [
            "claude-sonnet-4": ModelPrice(inputPerMillionUSD: 3, outputPerMillionUSD: 15),
            "claude-3-5-haiku": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: 4)
        ],
        .gemini: [
            "gemini-2.0-flash": ModelPrice(inputPerMillionUSD: Decimal(string: "0.1")!, outputPerMillionUSD: Decimal(string: "0.4")!),
            "gemini-2.5-flash": ModelPrice(inputPerMillionUSD: Decimal(string: "0.3")!, outputPerMillionUSD: Decimal(string: "2.5")!)
        ],
        .deepSeek: [
            "deepseek-v4-flash": ModelPrice(inputPerMillionUSD: Decimal(string: "0.14")!, outputPerMillionUSD: Decimal(string: "0.28")!),
            "deepseek-v4-pro": ModelPrice(inputPerMillionUSD: Decimal(string: "0.435")!, outputPerMillionUSD: Decimal(string: "0.87")!),
            "deepseek-chat": ModelPrice(inputPerMillionUSD: Decimal(string: "0.14")!, outputPerMillionUSD: Decimal(string: "0.28")!),
            "deepseek-reasoner": ModelPrice(inputPerMillionUSD: Decimal(string: "0.435")!, outputPerMillionUSD: Decimal(string: "0.87")!)
        ],
        .moonshotKimi: [
            "moonshot-v1": ModelPrice(inputPerMillionUSD: 2, outputPerMillionUSD: 5),
            "kimi-k2": ModelPrice(inputPerMillionUSD: 2, outputPerMillionUSD: 5)
        ],
        .zhipuGLM: [
            "glm": ModelPrice(inputPerMillionUSD: 1, outputPerMillionUSD: 3)
        ],
        .volcengineDoubao: [
            "doubao": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.0")!)
        ],
        .alibabaQwen: [
            "qwen": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.4")!)
        ],
        .minimax: [
            "minimax": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.4")!),
            "m2.7": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.4")!)
        ],
        .tencentHunyuan: [
            "hunyuan": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.4")!)
        ],
        .xAI: [
            "grok": ModelPrice(inputPerMillionUSD: 3, outputPerMillionUSD: 15)
        ],
        .xiaomiMimo: [
            "mimo": ModelPrice(inputPerMillionUSD: Decimal(string: "0.8")!, outputPerMillionUSD: Decimal(string: "2.4")!)
        ]
    ]

    public static func estimateCost(
        provider: ProviderKind,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Decimal {
        let price = price(for: provider, model: model)
        let input = Decimal(inputTokens) / 1_000_000 * price.inputPerMillionUSD
        let output = Decimal(outputTokens) / 1_000_000 * price.outputPerMillionUSD
        return input + output
    }

    public static func price(for provider: ProviderKind, model: String) -> ModelPrice {
        let normalized = model.lowercased()
        if let exact = prices[provider]?[normalized] {
            return exact
        }
        if let match = prices[provider]?.first(where: { normalized.contains($0.key) })?.value {
            return match
        }
        return ModelPrice(inputPerMillionUSD: 1, outputPerMillionUSD: 3)
    }
}
