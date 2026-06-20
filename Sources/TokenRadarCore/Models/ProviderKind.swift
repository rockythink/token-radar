import Foundation

public enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAI
    case anthropic
    case openRouter
    case siliconFlow
    case vercelAIGateway
    case cloudflareAIGateway
    case cloudflareWorkersAI
    case gemini
    case deepSeek
    case moonshotKimi
    case zhipuGLM
    case volcengineDoubao
    case alibabaQwen
    case minimax
    case tencentHunyuan
    case xAI
    case xiaomiMimo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .openRouter:
            "OpenRouter"
        case .siliconFlow:
            "SiliconFlow"
        case .vercelAIGateway:
            "Vercel AI Gateway"
        case .cloudflareAIGateway:
            "Cloudflare AI Gateway"
        case .cloudflareWorkersAI:
            "Cloudflare Workers AI"
        case .gemini:
            "Gemini"
        case .deepSeek:
            "DeepSeek"
        case .moonshotKimi:
            "Kimi / Moonshot"
        case .zhipuGLM:
            "Zhipu GLM"
        case .volcengineDoubao:
            "Doubao / Volcengine"
        case .alibabaQwen:
            "Qwen / DashScope"
        case .minimax:
            "MiniMax"
        case .tencentHunyuan:
            "Tencent Hunyuan"
        case .xAI:
            "xAI Grok"
        case .xiaomiMimo:
            "Xiaomi MiMo"
        }
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .openAI:
            URL(string: "https://api.openai.com")
        case .anthropic:
            URL(string: "https://api.anthropic.com")
        case .openRouter:
            URL(string: "https://openrouter.ai")
        case .siliconFlow:
            URL(string: "https://api.siliconflow.cn/v1")
        case .vercelAIGateway:
            URL(string: "https://ai-gateway.vercel.sh")
        case .cloudflareAIGateway:
            URL(string: "https://api.cloudflare.com/client/v4")
        case .cloudflareWorkersAI:
            URL(string: "https://api.cloudflare.com/client/v4")
        case .gemini:
            URL(string: "https://generativelanguage.googleapis.com")
        case .deepSeek:
            URL(string: "https://api.deepseek.com")
        case .moonshotKimi:
            URL(string: "https://api.moonshot.cn")
        case .zhipuGLM:
            URL(string: "https://open.bigmodel.cn")
        case .volcengineDoubao:
            URL(string: "https://ark.cn-beijing.volces.com/api/v3")
        case .alibabaQwen:
            URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode")
        case .minimax:
            URL(string: "https://api.minimax.io")
        case .tencentHunyuan:
            URL(string: "https://hunyuan.tencentcloudapi.com")
        case .xAI:
            URL(string: "https://api.x.ai")
        case .xiaomiMimo:
            URL(string: "https://api.mimo.mi.com")
        }
    }

    public var credentialLabel: String {
        switch self {
        case .openAI:
            "Admin API Key"
        case .anthropic:
            "Admin API Key"
        case .openRouter:
            "API Key"
        case .siliconFlow:
            "API Key"
        case .vercelAIGateway:
            "AI Gateway API Key"
        case .cloudflareAIGateway:
            "Cloudflare API Token"
        case .cloudflareWorkersAI:
            "Cloudflare API Token"
        case .gemini:
            "API Key"
        case .deepSeek:
            "API Key"
        case .moonshotKimi:
            "API Key"
        case .zhipuGLM:
            "API Key"
        case .volcengineDoubao:
            "ARK API Key"
        case .alibabaQwen:
            "DashScope API Key"
        case .minimax:
            "API Key"
        case .tencentHunyuan:
            "API Key"
        case .xAI:
            "API Key"
        case .xiaomiMimo:
            "API Key"
        }
    }

    public var supportsProviderBillingAPI: Bool {
        switch self {
        case .openAI, .anthropic, .openRouter, .vercelAIGateway, .cloudflareAIGateway, .deepSeek:
            true
        case .cloudflareWorkersAI, .gemini, .siliconFlow, .moonshotKimi, .zhipuGLM, .volcengineDoubao, .alibabaQwen, .minimax, .tencentHunyuan, .xAI, .xiaomiMimo:
            false
        }
    }

    public var usageAuthMethod: ProviderAuthMethod {
        switch self {
        case .openAI, .anthropic:
            .adminAPIKey
        case .vercelAIGateway:
            .aiGatewayKey
        case .cloudflareAIGateway, .cloudflareWorkersAI, .openRouter, .siliconFlow, .deepSeek, .gemini, .moonshotKimi, .zhipuGLM, .volcengineDoubao, .alibabaQwen, .minimax, .tencentHunyuan, .xAI, .xiaomiMimo:
            .apiKey
        }
    }

    public var supportsOfficialSubscriptionSync: Bool {
        switch self {
        case .openAI, .anthropic, .openRouter, .vercelAIGateway, .cloudflareAIGateway, .deepSeek:
            true
        case .cloudflareWorkersAI, .gemini, .siliconFlow, .moonshotKimi, .zhipuGLM, .volcengineDoubao, .alibabaQwen, .minimax, .tencentHunyuan, .xAI, .xiaomiMimo:
            false
        }
    }
}

public enum QuotaConfidence: String, Codable {
    case exact
    case budgetDerived
    case estimateOnly

    public var displayName: String {
        switch self {
        case .exact:
            "Exact"
        case .budgetDerived:
            "Budget-derived"
        case .estimateOnly:
            "Estimate only"
        }
    }
}

public enum UsageSource: String, Codable {
    case providerAPI
    case localProxy
    case cliSessionLog
    case estimate
    case fixture
}
