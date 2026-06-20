import Foundation

public enum ProviderParsers {
    public static func parseOpenAICosts(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        guard let buckets = root["data"] as? [[String: Any]] else {
            throw ProviderParsingError.unsupportedShape("OpenAI costs response did not include data buckets.")
        }

        var groups: [UsageGroup] = []
        var totalSpend = Decimal(0)
        var periodStart = now
        var periodEnd = now

        for bucket in buckets {
            if let start = bucket["start_time"] as? NSNumber {
                periodStart = Date(timeIntervalSince1970: start.doubleValue)
            }
            if let end = bucket["end_time"] as? NSNumber {
                periodEnd = Date(timeIntervalSince1970: end.doubleValue)
            }
            let results = bucket["results"] as? [[String: Any]] ?? []
            for result in results {
                let amount = result["amount"] as? [String: Any]
                let spend = DecimalCoding.decimal(from: amount?["value"] ?? result["cost"])
                totalSpend += spend
                groups.append(
                    UsageGroup(
                        provider: .openAI,
                        project: result["project_id"] as? String,
                        apiKeyLabel: result["api_key_id"] as? String,
                        spendUSD: spend
                    )
                )
            }
        }

        return ProviderUsageSnapshot(
            provider: .openAI,
            periodStart: periodStart,
            periodEnd: periodEnd,
            spendUSD: totalSpend,
            quotaConfidence: .budgetDerived,
            source: .providerAPI,
            groups: compactGroups(groups),
            note: "Costs are authoritative for billing; remaining quota is derived from configured budget."
        )
    }

    public static func parseOpenAIUsage(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        guard let buckets = root["data"] as? [[String: Any]] else {
            throw ProviderParsingError.unsupportedShape("OpenAI usage response did not include data buckets.")
        }

        var groups: [UsageGroup] = []
        var inputTokens = 0
        var outputTokens = 0
        var requestCount = 0
        var periodStart = now
        var periodEnd = now

        for bucket in buckets {
            if let start = bucket["start_time"] as? NSNumber {
                periodStart = Date(timeIntervalSince1970: start.doubleValue)
            }
            if let end = bucket["end_time"] as? NSNumber {
                periodEnd = Date(timeIntervalSince1970: end.doubleValue)
            }
            let results = bucket["results"] as? [[String: Any]] ?? []
            for result in results {
                let groupInput = DecimalCoding.int(from: result["input_tokens"])
                let groupOutput = DecimalCoding.int(from: result["output_tokens"])
                let requests = DecimalCoding.int(from: result["num_model_requests"] ?? result["requests"])
                inputTokens += groupInput
                outputTokens += groupOutput
                requestCount += requests
                groups.append(
                    UsageGroup(
                        provider: .openAI,
                        model: result["model"] as? String,
                        project: result["project_id"] as? String,
                        apiKeyLabel: result["api_key_id"] as? String,
                        spendUSD: 0,
                        inputTokens: groupInput,
                        outputTokens: groupOutput,
                        requestCount: requests
                    )
                )
            }
        }

        return ProviderUsageSnapshot(
            provider: .openAI,
            periodStart: periodStart,
            periodEnd: periodEnd,
            spendUSD: 0,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            requestCount: requestCount,
            quotaConfidence: .estimateOnly,
            source: .providerAPI,
            groups: compactGroups(groups)
        )
    }

    public static func parseAnthropicMessagesUsage(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        guard let buckets = root["data"] as? [[String: Any]] else {
            throw ProviderParsingError.unsupportedShape("Anthropic usage report did not include data buckets.")
        }

        var groups: [UsageGroup] = []
        var inputTokens = 0
        var outputTokens = 0
        var periodStart = now
        var periodEnd = now

        for bucket in buckets {
            if let start = bucket["starting_at"] as? String, let date = ISO8601DateFormatter().date(from: start) {
                periodStart = date
            }
            if let end = bucket["ending_at"] as? String, let date = ISO8601DateFormatter().date(from: end) {
                periodEnd = date
            }
            let results = bucket["results"] as? [[String: Any]] ?? []
            for result in results {
                let uncached = DecimalCoding.int(from: result["uncached_input_tokens"])
                let cachedRead = DecimalCoding.int(from: result["cache_read_input_tokens"])
                let cacheCreation = result["cache_creation"] as? [String: Any]
                let cache1h = DecimalCoding.int(from: cacheCreation?["ephemeral_1h_input_tokens"])
                let cache5m = DecimalCoding.int(from: cacheCreation?["ephemeral_5m_input_tokens"])
                let groupInput = uncached + cachedRead + cache1h + cache5m
                let groupOutput = DecimalCoding.int(from: result["output_tokens"])
                inputTokens += groupInput
                outputTokens += groupOutput
                let model = result["model"] as? String
                let spend = PriceCatalog.estimateCost(
                    provider: .anthropic,
                    model: model ?? "unknown",
                    inputTokens: groupInput,
                    outputTokens: groupOutput
                )
                groups.append(
                    UsageGroup(
                        provider: .anthropic,
                        model: model,
                        project: result["workspace_id"] as? String,
                        apiKeyLabel: result["api_key_id"] as? String,
                        spendUSD: spend,
                        inputTokens: groupInput,
                        outputTokens: groupOutput
                    )
                )
            }
        }

        let totalSpend = groups.reduce(Decimal(0)) { $0 + $1.spendUSD }
        return ProviderUsageSnapshot(
            provider: .anthropic,
            periodStart: periodStart,
            periodEnd: periodEnd,
            spendUSD: totalSpend,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            quotaConfidence: .estimateOnly,
            source: .providerAPI,
            groups: compactGroups(groups),
            note: "Anthropic messages usage exposes tokens; cost is estimated from the local price catalog."
        )
    }

    public static func parseOpenRouterKey(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        guard let payload = root["data"] as? [String: Any] else {
            throw ProviderParsingError.unsupportedShape("OpenRouter key response did not include data.")
        }

        let monthlyUsage = DecimalCoding.decimal(from: payload["usage_monthly"] ?? payload["usage"])
        let remaining = optionalDecimal(payload["limit_remaining"])
        let limit = optionalDecimal(payload["limit"])

        return ProviderUsageSnapshot(
            provider: .openRouter,
            fetchedAt: now,
            periodStart: DateRanges.startOfMonth(containing: now),
            periodEnd: now,
            spendUSD: monthlyUsage,
            remainingUSD: remaining,
            monthlyBudgetUSD: limit,
            quotaConfidence: remaining == nil ? .budgetDerived : .exact,
            source: .providerAPI,
            groups: [
                UsageGroup(
                    provider: .openRouter,
                    apiKeyLabel: payload["label"] as? String,
                    spendUSD: monthlyUsage
                )
            ],
            note: "OpenRouter returns key usage and remaining credits for the current key."
        )
    }

    public static func parseVercelCredits(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        let payload = (root["data"] as? [String: Any]) ?? root
        let credits = (payload["credits"] as? [String: Any]) ?? payload

        let remaining = optionalDecimal(
            credits["remaining"] ??
            credits["balance"] ??
            payload["remainingCredits"] ??
            payload["balance"]
        )
        let used = DecimalCoding.decimal(
            from: credits["used"] ??
            credits["usage"] ??
            credits["total_used"] ??
            payload["usedCredits"] ??
            payload["usage"] ??
            payload["total_used"]
        )
        let limit = optionalDecimal(credits["limit"] ?? payload["limit"])

        return ProviderUsageSnapshot(
            provider: .vercelAIGateway,
            fetchedAt: now,
            periodStart: DateRanges.startOfMonth(containing: now),
            periodEnd: now,
            spendUSD: used,
            remainingUSD: remaining,
            monthlyBudgetUSD: limit,
            quotaConfidence: remaining == nil ? .budgetDerived : .exact,
            source: .providerAPI,
            groups: [
                UsageGroup(provider: .vercelAIGateway, spendUSD: used)
            ],
            note: "Vercel AI Gateway credits endpoint shape is normalized defensively for MVP."
        )
    }

    public static func parseCloudflareAIGatewayLogs(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        let logs = cloudflareLogEntries(from: root)
        let monthStart = DateRanges.startOfMonth(containing: now)

        var groups: [UsageGroup] = []
        var totalSpend = Decimal(0)
        var inputTokens = 0
        var outputTokens = 0
        var requestCount = 0
        var periodStart = now
        var periodEnd = monthStart

        for log in logs {
            let createdAt = date(fromISO8601: log["created_at"] as? String) ?? now
            guard createdAt >= monthStart else { continue }

            let model = (log["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Cloudflare AI Gateway"
            let providerName = (log["provider"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let groupInput = DecimalCoding.int(
                from: log["tokens_in"] ??
                log["input_tokens"] ??
                log["prompt_tokens"]
            )
            let groupOutput = DecimalCoding.int(
                from: log["tokens_out"] ??
                log["output_tokens"] ??
                log["completion_tokens"]
            )
            let loggedCost = optionalDecimal(log["cost"])
            let spend = loggedCost ?? PriceCatalog.estimateCost(
                provider: providerKind(fromCloudflareProvider: providerName),
                model: model,
                inputTokens: groupInput,
                outputTokens: groupOutput
            )

            totalSpend += spend
            inputTokens += groupInput
            outputTokens += groupOutput
            requestCount += 1
            periodStart = min(periodStart, createdAt)
            periodEnd = max(periodEnd, createdAt)

            groups.append(
                UsageGroup(
                    provider: .cloudflareAIGateway,
                    model: model,
                    project: providerName,
                    spendUSD: spend,
                    inputTokens: groupInput,
                    outputTokens: groupOutput,
                    requestCount: 1
                )
            )
        }

        return ProviderUsageSnapshot(
            provider: .cloudflareAIGateway,
            fetchedAt: now,
            periodStart: groups.isEmpty ? monthStart : periodStart,
            periodEnd: groups.isEmpty ? now : periodEnd,
            spendUSD: totalSpend,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            requestCount: requestCount,
            quotaConfidence: .budgetDerived,
            source: .providerAPI,
            groups: compactGroups(groups),
            note: "Cloudflare AI Gateway logs include provider, model, token counts, status, and optional cost; budget remaining is derived locally."
        )
    }

    public static func parseGeminiUsageMetadata(_ data: Data, model: String = "gemini", now: Date = Date()) throws -> UsageRecord {
        let root = try jsonObject(data)
        let metadata = (root["usageMetadata"] as? [String: Any]) ?? (root["usage_metadata"] as? [String: Any]) ?? root
        let inputTokens = DecimalCoding.int(from: metadata["promptTokenCount"] ?? metadata["prompt_token_count"])
        let outputTokens = DecimalCoding.int(from: metadata["candidatesTokenCount"] ?? metadata["candidates_token_count"])
        let cost = PriceCatalog.estimateCost(provider: .gemini, model: model, inputTokens: inputTokens, outputTokens: outputTokens)
        return UsageRecord(
            provider: .gemini,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: cost,
            source: .estimate
        )
    }

    public static func parseDeepSeekBalance(_ data: Data, now: Date = Date()) throws -> ProviderUsageSnapshot {
        let root = try jsonObject(data)
        let balances = root["balance_infos"] as? [[String: Any]] ?? []
        let usd = balances.first { ($0["currency"] as? String)?.uppercased() == "USD" }
        let cny = balances.first { ($0["currency"] as? String)?.uppercased() == "CNY" }
        let selected = usd ?? cny
        let rawBalance = DecimalCoding.decimal(from: selected?["total_balance"])
        let normalizedUSD = usd == nil && cny != nil ? rawBalance * Decimal(string: "0.14")! : rawBalance
        let isAvailable = (root["is_available"] as? Bool) ?? (normalizedUSD > 0)

        return ProviderUsageSnapshot(
            provider: .deepSeek,
            fetchedAt: now,
            periodStart: DateRanges.startOfMonth(containing: now),
            periodEnd: now,
            spendUSD: 0,
            remainingUSD: normalizedUSD,
            quotaConfidence: .exact,
            source: .providerAPI,
            groups: [
                UsageGroup(provider: .deepSeek, spendUSD: 0)
            ],
            note: isAvailable
                ? "DeepSeek balance is available. CNY balances are converted with a static MVP estimate."
                : "DeepSeek reports insufficient balance."
        )
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw ProviderParsingError.invalidJSON
        }
        return dictionary
    }

    private static func optionalDecimal(_ value: Any?) -> Decimal? {
        guard value != nil, !(value is NSNull) else { return nil }
        return DecimalCoding.decimal(from: value)
    }

    private static func cloudflareLogEntries(from root: [String: Any]) -> [[String: Any]] {
        if let result = root["result"] as? [[String: Any]] {
            return result
        }
        if let result = root["result"] as? [String: Any] {
            if let data = result["data"] as? [[String: Any]] {
                return data
            }
            if let logs = result["logs"] as? [[String: Any]] {
                return logs
            }
        }
        if let data = root["data"] as? [[String: Any]] {
            return data
        }
        if let logs = root["logs"] as? [[String: Any]] {
            return logs
        }
        return []
    }

    private static func date(fromISO8601 raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func providerKind(fromCloudflareProvider raw: String?) -> ProviderKind {
        let normalized = raw?.lowercased() ?? ""
        if normalized.contains("anthropic") || normalized.contains("claude") {
            return .anthropic
        }
        if normalized.contains("openrouter") {
            return .openRouter
        }
        if normalized.contains("google") || normalized.contains("gemini") {
            return .gemini
        }
        if normalized.contains("deepseek") {
            return .deepSeek
        }
        if normalized.contains("moonshot") || normalized.contains("kimi") {
            return .moonshotKimi
        }
        if normalized.contains("zhipu") || normalized.contains("glm") {
            return .zhipuGLM
        }
        if normalized.contains("dashscope") || normalized.contains("qwen") || normalized.contains("alibaba") {
            return .alibabaQwen
        }
        if normalized.contains("xai") || normalized.contains("grok") {
            return .xAI
        }
        return .openAI
    }

    private static func compactGroups(_ groups: [UsageGroup]) -> [UsageGroup] {
        var merged: [String: UsageGroup] = [:]
        for group in groups {
            let key = [
                group.provider.rawValue,
                group.model ?? "",
                group.project ?? "",
                group.apiKeyLabel ?? ""
            ].joined(separator: "|")

            if var existing = merged[key] {
                existing.spendUSD += group.spendUSD
                existing.inputTokens += group.inputTokens
                existing.outputTokens += group.outputTokens
                existing.requestCount += group.requestCount
                merged[key] = existing
            } else {
                merged[key] = group
            }
        }
        return Array(merged.values).sorted { $0.spendUSD > $1.spendUSD }
    }
}
