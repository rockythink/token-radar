import Foundation

public protocol ProviderClient {
    var provider: ProviderKind { get }
    func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot
}

public enum ProviderClientError: Error, LocalizedError {
    case invalidBaseURL(ProviderKind)
    case httpStatus(Int, String)
    case missingCredential(ProviderKind)
    case missingResourceID(ProviderKind, String)
    case unsupportedProvider(ProviderKind)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let provider):
            "Invalid base URL for \(provider.displayName)."
        case .httpStatus(let status, let body):
            "Provider returned HTTP \(status): \(body)"
        case .missingCredential(let provider):
            "Missing credential for \(provider.displayName)."
        case .missingResourceID(let provider, let expected):
            "Missing resource identifier for \(provider.displayName). Expected \(expected)."
        case .unsupportedProvider(let provider):
            "\(provider.displayName) does not expose a supported billing endpoint in Token Radar MVP."
        }
    }
}

public struct ProviderClientFactory {
    public init() {}

    public func client(for provider: ProviderKind) -> ProviderClient {
        switch provider {
        case .openAI:
            OpenAIProviderClient()
        case .anthropic:
            AnthropicProviderClient()
        case .openRouter:
            OpenRouterProviderClient()
        case .vercelAIGateway:
            VercelAIGatewayProviderClient()
        case .cloudflareAIGateway:
            CloudflareAIGatewayProviderClient()
        case .cloudflareWorkersAI:
            CloudflareWorkersAIEstimateProviderClient()
        case .gemini:
            GeminiEstimateProviderClient()
        case .deepSeek:
            DeepSeekProviderClient()
        case .siliconFlow, .moonshotKimi, .zhipuGLM, .volcengineDoubao, .alibabaQwen, .minimax, .tencentHunyuan, .xAI, .xiaomiMimo:
            GenericOpenAICompatibleEstimateClient(provider: provider)
        }
    }
}

public struct OpenAIProviderClient: ProviderClient {
    public let provider: ProviderKind = .openAI

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.openAI)
        }

        let monthStart = DateRanges.startOfMonth()
        let startTime = Int(monthStart.timeIntervalSince1970)
        let url = try makeURL(
            baseURL: baseURL,
            path: "/v1/organization/costs",
            queryItems: [
                URLQueryItem(name: "start_time", value: "\(startTime)"),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "group_by[]", value: "project_id"),
                URLQueryItem(name: "limit", value: "31")
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseOpenAICosts(data)
        snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        if snapshot.remainingUSD == nil {
            snapshot.remainingUSD = max(0, configuration.monthlyBudgetUSD - snapshot.spendUSD)
        }
        return snapshot
    }
}

public struct AnthropicProviderClient: ProviderClient {
    public let provider: ProviderKind = .anthropic

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.anthropic)
        }

        let formatter = ISO8601DateFormatter()
        let startingAt = formatter.string(from: DateRanges.startOfMonth())
        let url = try makeURL(
            baseURL: baseURL,
            path: "/v1/organizations/usage_report/messages",
            queryItems: [
                URLQueryItem(name: "starting_at", value: startingAt),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "group_by[]", value: "model"),
                URLQueryItem(name: "group_by[]", value: "workspace_id"),
                URLQueryItem(name: "group_by[]", value: "api_key_id"),
                URLQueryItem(name: "limit", value: "31")
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseAnthropicMessagesUsage(data)
        snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        snapshot.remainingUSD = max(0, configuration.monthlyBudgetUSD - snapshot.spendUSD)
        return snapshot
    }
}

public struct OpenRouterProviderClient: ProviderClient {
    public let provider: ProviderKind = .openRouter

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.openRouter)
        }

        let url = try makeURL(baseURL: baseURL, path: "/api/v1/key")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseOpenRouterKey(data)
        if snapshot.monthlyBudgetUSD == nil {
            snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        }
        if snapshot.remainingUSD == nil {
            snapshot.remainingUSD = max(0, configuration.monthlyBudgetUSD - snapshot.spendUSD)
        }
        return snapshot
    }
}

public struct VercelAIGatewayProviderClient: ProviderClient {
    public let provider: ProviderKind = .vercelAIGateway

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.vercelAIGateway)
        }

        let url = try makeURL(baseURL: baseURL, path: "/v1/credits")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseVercelCredits(data)
        if snapshot.monthlyBudgetUSD == nil {
            snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        }
        if snapshot.remainingUSD == nil {
            snapshot.remainingUSD = max(0, configuration.monthlyBudgetUSD - snapshot.spendUSD)
        }
        return snapshot
    }
}

public struct CloudflareAIGatewayProviderClient: ProviderClient {
    public let provider: ProviderKind = .cloudflareAIGateway

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.cloudflareAIGateway)
        }

        let parts = configuration.resourceID
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count == 2 else {
            throw ProviderClientError.missingResourceID(.cloudflareAIGateway, "account_id/gateway_id")
        }

        let url = try makeURL(
            baseURL: baseURL,
            path: "/accounts/\(parts[0])/ai-gateway/gateways/\(parts[1])/logs",
            queryItems: [
                URLQueryItem(name: "per_page", value: "1000")
            ]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseCloudflareAIGatewayLogs(data)
        snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        snapshot.remainingUSD = max(0, configuration.monthlyBudgetUSD - snapshot.spendUSD)
        return snapshot
    }
}

public struct GeminiEstimateProviderClient: ProviderClient {
    public let provider: ProviderKind = .gemini

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .gemini,
            periodStart: DateRanges.startOfMonth(),
            periodEnd: Date(),
            spendUSD: 0,
            remainingUSD: configuration.monthlyBudgetUSD,
            monthlyBudgetUSD: configuration.monthlyBudgetUSD,
            quotaConfidence: .estimateOnly,
            source: .estimate,
            note: "Gemini billing is estimate-only in the MVP. Token metadata captured through the proxy is converted with the local price catalog."
        )
    }
}

public struct CloudflareWorkersAIEstimateProviderClient: ProviderClient {
    public let provider: ProviderKind = .cloudflareWorkersAI

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .cloudflareWorkersAI,
            periodStart: DateRanges.startOfMonth(),
            periodEnd: Date(),
            spendUSD: 0,
            remainingUSD: configuration.monthlyBudgetUSD,
            monthlyBudgetUSD: configuration.monthlyBudgetUSD,
            quotaConfidence: .estimateOnly,
            source: .estimate,
            note: "Cloudflare Workers AI usage is billed in Neurons and monitored through Cloudflare dashboard or billing exports in the MVP."
        )
    }
}

public struct DeepSeekProviderClient: ProviderClient {
    public let provider: ProviderKind = .deepSeek

    public init() {}

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        guard let baseURL = configuration.baseURL else {
            throw ProviderClientError.invalidBaseURL(.deepSeek)
        }

        let url = try makeURL(baseURL: baseURL, path: "/user/balance")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await HTTPProviderTransport.fetchData(request, networkProxy: networkProxy)
        var snapshot = try ProviderParsers.parseDeepSeekBalance(data)
        snapshot.monthlyBudgetUSD = configuration.monthlyBudgetUSD
        return snapshot
    }
}

public struct GenericOpenAICompatibleEstimateClient: ProviderClient {
    public let provider: ProviderKind

    public init(provider: ProviderKind) {
        self.provider = provider
    }

    public func fetchSnapshot(
        configuration: ProviderConfiguration,
        apiKey: String,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            periodStart: DateRanges.startOfMonth(),
            periodEnd: Date(),
            spendUSD: 0,
            remainingUSD: configuration.monthlyBudgetUSD,
            monthlyBudgetUSD: configuration.monthlyBudgetUSD,
            quotaConfidence: .estimateOnly,
            source: .estimate,
            note: "\(provider.displayName) is tracked through the local OpenAI-compatible proxy or OpenRouter in the MVP."
        )
    }
}

enum HTTPProviderTransport {
    static func fetchData(
        _ request: URLRequest,
        networkProxy: NetworkProxyConfiguration
    ) async throws -> Data {
        let session = URLSession(configuration: networkProxy.urlSessionConfiguration)
        defer {
            session.finishTasksAndInvalidate()
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return data
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderClientError.httpStatus(http.statusCode, body)
        }
        return data
    }
}

private func makeURL(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem] = []
) throws -> URL {
    let cleanBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard var components = URLComponents(string: cleanBase + path) else {
        throw ProviderClientError.invalidBaseURL(.openAI)
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
        throw ProviderClientError.invalidBaseURL(.openAI)
    }
    return url
}
