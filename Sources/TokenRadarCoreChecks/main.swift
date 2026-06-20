import Foundation
import Darwin
import Network
import TokenRadarCore

try checkOpenAIParser()
try checkAnthropicParser()
try checkOpenRouterParser()
try checkVercelParser()
try checkCloudflareAIGatewayParser()
try checkDeepSeekParser()
try checkBudgetCalculator()
try checkMonitorTargets()
try checkNetworkProxyConfiguration()
try checkQuotaWindowCalculator()
try checkSubscriptionCalculator()
try checkSubscriptionDecodingDefaults()
try checkAppSettingsDecodingDefaults()
try checkProxyCore()
try checkStreamingProxyForwarding()
try checkClaudeCodeSessionImporter()
try checkCodexSessionImporter()
try checkSQLiteRoundTrip()
print("TokenRadarCoreChecks passed")

private enum CoreCheckError: Error {
    case portUnavailable
    case listenerNotReady
    case clientRequestFailed
    case clientResponseMissing
}

private func checkOpenAIParser() throws {
        let snapshot = try ProviderParsers.parseOpenAICosts(fixture("openai-costs"))
        expect(snapshot.provider == .openAI, "OpenAI provider mismatch")
        expect(snapshot.spendUSD == Decimal(string: "12.34"), "OpenAI spend mismatch")
        expect(snapshot.groups.first?.project == "proj_token_radar", "OpenAI project mismatch")
    }

private func checkAnthropicParser() throws {
        let snapshot = try ProviderParsers.parseAnthropicMessagesUsage(fixture("anthropic-usage"))
        expect(snapshot.provider == .anthropic, "Anthropic provider mismatch")
        expect(snapshot.inputTokens == 3200, "Anthropic input tokens mismatch")
        expect(snapshot.outputTokens == 800, "Anthropic output tokens mismatch")
        expect(snapshot.spendUSD > 0, "Anthropic estimated spend should be positive")
        expect(snapshot.quotaConfidence == .estimateOnly, "Anthropic confidence mismatch")
    }

private func checkOpenRouterParser() throws {
        let snapshot = try ProviderParsers.parseOpenRouterKey(fixture("openrouter-key"))
        expect(snapshot.provider == .openRouter, "OpenRouter provider mismatch")
        expect(snapshot.spendUSD == Decimal(string: "7.25"), "OpenRouter spend mismatch")
        expect(snapshot.remainingUSD == Decimal(string: "42.75"), "OpenRouter remaining mismatch")
        expect(snapshot.quotaConfidence == .exact, "OpenRouter confidence mismatch")
    }

private func checkVercelParser() throws {
        let snapshot = try ProviderParsers.parseVercelCredits(fixture("vercel-credits"))
        expect(snapshot.provider == .vercelAIGateway, "Vercel provider mismatch")
        expect(snapshot.spendUSD == Decimal(string: "2.7"), "Vercel spend mismatch")
        expect(snapshot.remainingUSD == Decimal(string: "10.25"), "Vercel remaining mismatch")
    }

private func checkCloudflareAIGatewayParser() throws {
        let now = ISO8601DateFormatter().date(from: "2026-06-08T10:00:00Z")!
        let snapshot = try ProviderParsers.parseCloudflareAIGatewayLogs(fixture("cloudflare-ai-gateway-logs"), now: now)
        expect(snapshot.provider == .cloudflareAIGateway, "Cloudflare AI Gateway provider mismatch")
        expect(snapshot.inputTokens == 3_200, "Cloudflare AI Gateway input tokens mismatch")
        expect(snapshot.outputTokens == 800, "Cloudflare AI Gateway output tokens mismatch")
        expect(snapshot.requestCount == 2, "Cloudflare AI Gateway request count mismatch")
        expect(snapshot.spendUSD > Decimal(string: "0.013")!, "Cloudflare AI Gateway spend should parse logged cost")
        expect(snapshot.groups.contains { $0.model == "gpt-4o-mini" && $0.project == "openai" }, "Cloudflare AI Gateway group mismatch")
    }

private func checkDeepSeekParser() throws {
        let snapshot = try ProviderParsers.parseDeepSeekBalance(fixture("deepseek-balance"))
        expect(snapshot.provider == .deepSeek, "DeepSeek provider mismatch")
        expect(snapshot.remainingUSD == Decimal(string: "110.00"), "DeepSeek balance mismatch")
        expect(snapshot.quotaConfidence == .exact, "DeepSeek confidence mismatch")
    }

private func checkBudgetCalculator() throws {
        let now = Date()
        let records = [
            UsageRecord(timestamp: now, provider: .openAI, model: "gpt-4.1", inputTokens: 100, outputTokens: 20, costUSD: 120, source: .providerAPI)
        ]
        let summary = BudgetCalculator.summarize(records: records, monthlyBudgetUSD: 100, thresholds: [], now: now)
        expect(summary.remainingBudgetUSD == 0, "Budget remaining should be zero")
        expect(summary.alert?.severity == .critical, "Budget exhaustion should be critical")
    }

private func checkMonitorTargets() throws {
        let proxyRecord = UsageRecord(provider: .openAI, model: "gpt-4o-mini", inputTokens: 100, outputTokens: 20, costUSD: 1, source: .localProxy)
        let providerRecord = UsageRecord(provider: .vercelAIGateway, model: "Vercel AI Gateway", inputTokens: 0, outputTokens: 0, costUSD: 2, source: .providerAPI)
        let cloudBillingRecord = UsageRecord(provider: .cloudflareWorkersAI, model: "Workers AI", inputTokens: 0, outputTokens: 0, costUSD: 3, source: .estimate)

        let localTarget = MonitorTarget(name: "This Mac", source: .localProxyDevice, scope: .device)
        expect(localTarget.matches(proxyRecord), "Local proxy target should match local proxy records")
        expect(!localTarget.matches(providerRecord), "Local proxy target should not match remote provider records")

        let gatewayTarget = MonitorTarget(name: "Vercel Gateway", provider: .vercelAIGateway, source: .providerUsageAPI, scope: .gateway)
        expect(gatewayTarget.matches(providerRecord), "Provider target should match provider API records")
        expect(!gatewayTarget.matches(proxyRecord), "Provider target should not match local proxy records")

        let workerTarget = MonitorTarget(name: "Worker", provider: .cloudflareWorkersAI, source: .cloudBilling, scope: .worker)
        expect(workerTarget.matches(cloudBillingRecord), "Cloud billing target should match delayed estimate records")

        let subscriptionTarget = MonitorTarget(
            name: "OpenAI Plus",
            accountKind: .subscriptionUser,
            provider: .openAI,
            source: .subscriptionPlan,
            scope: .subscription,
            monthlyBudgetUSD: 0,
            monthlyFeeUSD: 100,
            usesLocalProxy: true,
            quotaWindows: [
                SubscriptionQuotaWindow(name: "5h", kind: .fiveHours, includedUnits: 10, quotaUnit: .messages)
            ]
        )
        expect(subscriptionTarget.matches(proxyRecord), "Subscription target with local proxy should match local proxy records")
        let summary = MonitorTargetSummary(target: subscriptionTarget, records: [proxyRecord])
        expect(summary.quotaWindowSummaries.count == 1, "Subscription monitor should summarize quota windows")
        expect(subscriptionTarget.fixedMonthlyFeeUSD == 100, "Subscription monitor should store fixed monthly fee separately")
        expect(subscriptionTarget.budgetLimitUSD == 0, "Subscription monitor should not expose a budget limit")
        let feeOnlyTarget = MonitorTarget(
            name: "Fee Only",
            accountKind: .subscriptionUser,
            source: .subscriptionPlan,
            scope: .subscription,
            monthlyFeeUSD: 20
        )
        expect(feeOnlyTarget.monthlyBudgetUSD == 0, "Subscription monitor should not keep default API budget")
        expect(summary.remainingBudgetUSD == 0, "Subscription monitor should not consume budget remaining")
        expect(summary.utilization == 0, "Subscription monitor should not report budget utilization")

        let legacyJSON = Data("""
        {
          "name": "Legacy ChatGPT Pro",
          "accountKind": "subscriptionUser",
          "provider": "openAI",
          "source": "subscriptionPlan",
          "scope": "subscription",
          "monthlyBudgetUSD": 200
        }
        """.utf8)
        let legacyTarget = try JSONDecoder().decode(MonitorTarget.self, from: legacyJSON)
        expect(legacyTarget.fixedMonthlyFeeUSD == 200, "Legacy subscription budget should migrate to monthly fee")
        expect(legacyTarget.monthlyBudgetUSD == 0, "Legacy subscription budget should clear after fee migration")
    }

private func checkNetworkProxyConfiguration() throws {
        let defaultProxy = NetworkProxyConfiguration()
        expect(defaultProxy.mode == .system, "Network proxy should default to system mode")
        expect(defaultProxy.urlSessionConfiguration.connectionProxyDictionary == nil, "System proxy should not override URLSession proxy dictionary")

        let httpProxy = NetworkProxyConfiguration(mode: .http, host: "127.0.0.1", port: 7890)
        let dictionary = httpProxy.urlSessionConfiguration.connectionProxyDictionary
        expect(dictionary?[kCFNetworkProxiesHTTPProxy as String] as? String == "127.0.0.1", "HTTP proxy host mismatch")
        expect(dictionary?[kCFNetworkProxiesHTTPPort as String] as? Int == 7890, "HTTP proxy port mismatch")
    }

private func checkQuotaWindowCalculator() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-06-08T06:00:00Z")!
        let records = [
            UsageRecord(timestamp: formatter.date(from: "2026-06-08T05:30:00Z")!, provider: .anthropic, model: "claude-sonnet-4", inputTokens: 100, outputTokens: 50, costUSD: 1, source: .cliSessionLog),
            UsageRecord(timestamp: formatter.date(from: "2026-06-08T04:59:00Z")!, provider: .anthropic, model: "claude-sonnet-4", inputTokens: 100, outputTokens: 50, costUSD: 1, source: .cliSessionLog),
            UsageRecord(timestamp: formatter.date(from: "2026-06-07T23:59:00Z")!, provider: .anthropic, model: "claude-sonnet-4", inputTokens: 100, outputTokens: 50, costUSD: 1, source: .cliSessionLog)
        ]

        let fiveHour = SubscriptionQuotaWindow(name: "5h", kind: .fiveHours, includedUnits: 3, quotaUnit: .messages)
        let fiveHourSummary = QuotaWindowCalculator.summarize(window: fiveHour, records: records, now: now, calendar: calendar)
        expect(fiveHourSummary.usedUnits == 1, "5-hour quota should only count records inside the current fixed window")
        expect(fiveHourSummary.remainingUnits == 2, "5-hour quota remaining mismatch")

        let weekly = SubscriptionQuotaWindow(name: "Week", kind: .weekly, includedUnits: 1_000, quotaUnit: .tokens)
        let weeklySummary = QuotaWindowCalculator.summarize(window: weekly, records: records, now: now, calendar: calendar)
        expect(weeklySummary.usedUnits == 300, "Weekly quota should count Monday records only")
        expect(weeklySummary.periodStart == formatter.date(from: "2026-06-08T00:00:00Z")!, "Weekly quota should start on Monday")

        let providerWindow = SubscriptionQuotaWindow(
            name: "Official 5h",
            kind: .fiveHours,
            includedUnits: 0,
            quotaUnit: .messages,
            providerRemainingRatio: Decimal(string: "0.82"),
            providerResetAt: formatter.date(from: "2026-06-08T08:30:00Z")!,
            providerResetLabel: "03:34",
            providerReportedAt: now
        )
        let providerSummary = QuotaWindowCalculator.summarize(window: providerWindow, records: records, now: now, calendar: calendar)
        expect(providerSummary.isProviderReported, "Provider quota should be marked as reported")
        expect(providerSummary.remainingRatio == Decimal(string: "0.82"), "Provider remaining ratio mismatch")
        expect(providerSummary.usedRatio == Decimal(string: "0.18"), "Provider used ratio mismatch")
        expect(providerSummary.periodEnd == formatter.date(from: "2026-06-08T08:30:00Z")!, "Provider quota should use reported reset time as period end")
        expect(abs(providerSummary.remainingSeconds - 9_000) < 0.01, "Provider quota remaining seconds mismatch")
        expect(providerSummary.timeRemainingRatio > Decimal(string: "0.49")! && providerSummary.timeRemainingRatio < Decimal(string: "0.51")!, "Provider quota time remaining ratio mismatch")
        expect(providerSummary.quotaTimeRatio > Decimal(string: "1.63")! && providerSummary.quotaTimeRatio < Decimal(string: "1.65")!, "Provider quota pace ratio mismatch")
        expect(providerSummary.providerResetLabel == "03:34", "Provider reset label mismatch")
    }

private func checkSubscriptionCalculator() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let records = [
            UsageRecord(timestamp: now, provider: .deepSeek, model: "deepseek-v4-pro", inputTokens: 600, outputTokens: 400, costUSD: 1, source: .localProxy),
            UsageRecord(timestamp: now, provider: .openAI, model: "gpt-4.1", inputTokens: 100, outputTokens: 100, costUSD: 2, source: .localProxy)
        ]
        let plan = SubscriptionPlan(
            name: "DeepSeek Plan",
            provider: .deepSeek,
            modelPattern: "deepseek-v4",
            monthlyFeeUSD: 20,
            includedUnits: 2_000,
            quotaUnit: .tokens,
            resetDay: 1,
            overageUnitPriceUSD: Decimal(string: "0.001")
        )

        let summary = SubscriptionCalculator.summarize(plan: plan, records: records, now: now, calendar: calendar)

        expect(summary.usedUnits == 1_000, "Subscription used units mismatch")
        expect(summary.remainingUnits == 1_000, "Subscription remaining units mismatch")
        expect(summary.utilization == Decimal(string: "0.5"), "Subscription utilization mismatch")
        expect(summary.projectedUnits > 1_900, "Subscription projection should annualize current burn")
    }

private func checkSubscriptionDecodingDefaults() throws {
        let json = Data("""
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy Plan",
          "isEnabled": true,
          "monthlyFeeUSD": 20,
          "includedUnits": 1000,
          "quotaUnit": "tokens",
          "resetDay": 1
        }
        """.utf8)
        let plan = try JSONDecoder().decode(SubscriptionPlan.self, from: json)
        expect(plan.syncSource == .manual, "Legacy subscription should default to manual sync")
    }

private func checkAppSettingsDecodingDefaults() throws {
        let json = Data("""
        {
          "language": "english",
          "providers": [
            {
              "provider": "cloudflareAIGateway",
              "isEnabled": true,
              "monthlyBudgetUSD": 25,
              "apiKeyLabel": "Default",
              "pollIntervalMinutes": 60
            }
          ]
        }
        """.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        expect(settings.monitorTargets.isEmpty, "Legacy settings should start with empty monitor targets")
        expect(settings.providers.count == ProviderKind.allCases.count, "Legacy settings should merge missing providers")
        expect(settings.providers.first?.resourceID == "", "Legacy provider configuration should default resource ID")
        expect(settings.networkProxy.mode == .system, "Legacy settings should default network proxy to system")
        expect(settings.automaticProviderRefreshEnabled == false, "Legacy settings should default provider auto-refresh to off")
        expect(settings.providerRefreshIntervalMinutes == 60, "Legacy settings should default provider refresh interval")
        expect(settings.realtimeLocalSourceRefreshEnabled == true, "Legacy settings should default local source watcher to on")
    }

private func checkProxyCore() throws {
        let raw = """
        POST /v1/chat/completions HTTP/1.1\r
        Host: localhost:8787\r
        Content-Type: application/json\r
        Content-Length: 44\r
        \r
        {"model":"deepseek-v4-pro","messages":[]}
        """
        let request = try HTTPMessageParser.parseRequest(Data(raw.utf8))
        expect(request.method == "POST", "Proxy method mismatch")
        expect(request.path == "/v1/chat/completions", "Proxy path mismatch")
        expect(request.jsonBody?["model"] as? String == "deepseek-v4-pro", "Proxy model mismatch")

        let response = Data(#"{"model":"grok-4.3","usage":{"prompt_tokens":1000,"completion_tokens":250}}"#.utf8)
        let extracted = OpenAIUsageExtractor.extract(responseData: response, requestData: Data(#"{"model":"grok-4.3"}"#.utf8))
        expect(extracted?.model == "grok-4.3", "Usage model mismatch")
        expect(extracted?.inputTokens == 1000, "Usage input mismatch")
        expect(extracted?.outputTokens == 250, "Usage output mismatch")
        expect(ModelCatalog.trackedModel(for: "grok-4.3")?.displayName == "Gork", "Grok/Gork alias mismatch")
        expect(ModelCatalog.imageRanking.count == 13, "Tracked model count mismatch")

        let chatStream = Data("""
        data: {"id":"chatcmpl_demo","model":"gpt-4o-mini","choices":[{"delta":{"content":"hi"}}],"usage":null}

        data: {"id":"chatcmpl_demo","model":"gpt-4o-mini","choices":[],"usage":{"prompt_tokens":42,"completion_tokens":8}}

        data: [DONE]

        """.utf8)
        let chatStreamExtracted = OpenAIUsageExtractor.extractEventStream(
            responseData: chatStream,
            requestData: Data(#"{"model":"gpt-4o-mini","stream":true}"#.utf8)
        )
        expect(chatStreamExtracted?.model == "gpt-4o-mini", "Chat stream usage model mismatch")
        expect(chatStreamExtracted?.inputTokens == 42, "Chat stream usage input mismatch")
        expect(chatStreamExtracted?.outputTokens == 8, "Chat stream usage output mismatch")

        let responsesStream = Data("""
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"hi"}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_demo","model":"gpt-4.1","usage":{"input_tokens":77,"output_tokens":12}}}

        """.utf8)
        let responsesStreamExtracted = OpenAIUsageExtractor.extractEventStream(
            responseData: responsesStream,
            requestData: Data(#"{"model":"gpt-4.1","stream":true}"#.utf8)
        )
        expect(responsesStreamExtracted?.model == "gpt-4.1", "Responses stream usage model mismatch")
        expect(responsesStreamExtracted?.inputTokens == 77, "Responses stream usage input mismatch")
        expect(responsesStreamExtracted?.outputTokens == 12, "Responses stream usage output mismatch")
    }

private func checkStreamingProxyForwarding() throws {
        let upstreamPort = try reservePort()
        let proxyPort = try reservePort()
        let queue = DispatchQueue(label: "token-radar.streaming-proxy-check")
        let upstreamReady = DispatchSemaphore(value: 0)
        let upstreamListener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(upstreamPort))!)
        upstreamListener.stateUpdateHandler = { state in
            if case .ready = state {
                upstreamReady.signal()
            }
        }
        upstreamListener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { _, _, _, _ in
                let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/event-stream\r
                Connection: close\r
                \r
                data: {"id":"chatcmpl_proxy","model":"gpt-4o-mini","choices":[{"delta":{"content":"hi"}}],"usage":null}

                data: {"id":"chatcmpl_proxy","model":"gpt-4o-mini","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":4}}

                data: [DONE]

                """
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        upstreamListener.start(queue: queue)
        guard upstreamReady.wait(timeout: .now() + 3) == .success else {
            upstreamListener.cancel()
            throw CoreCheckError.listenerNotReady
        }

        var capturedRecords: [UsageRecord] = []
        let recordLock = NSLock()
        let recordReady = DispatchSemaphore(value: 0)
        let proxy = LocalProxyServer()
        try proxy.start(
            configuration: LocalProxyServer.Configuration(
                port: proxyPort,
                upstreamBaseURL: URL(string: "http://127.0.0.1:\(upstreamPort)")!,
                upstreamAPIKey: "test-key",
                provider: .openAI
            ),
            shouldBlockRequest: { false },
            onRecord: { record in
                recordLock.lock()
                capturedRecords.append(record)
                recordLock.unlock()
                recordReady.signal()
            },
            onError: { error in
                fatalError("Streaming proxy forwarding error: \(error)")
            }
        )
        defer {
            proxy.stop()
            upstreamListener.cancel()
        }

        Thread.sleep(forTimeInterval: 0.15)

        var clientRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(proxyPort)/v1/chat/completions")!)
        clientRequest.httpMethod = "POST"
        clientRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        clientRequest.httpBody = Data(#"{"model":"gpt-4o-mini","stream":true,"messages":[]}"#.utf8)

        let clientReady = DispatchSemaphore(value: 0)
        var clientData: Data?
        var clientError: Error?
        let task = URLSession.shared.dataTask(with: clientRequest) { data, _, error in
            clientData = data
            clientError = error
            clientReady.signal()
        }
        task.resume()

        guard clientReady.wait(timeout: .now() + 5) == .success else {
            throw CoreCheckError.clientRequestFailed
        }
        if let clientError {
            throw clientError
        }
        guard let clientData, let body = String(data: clientData, encoding: .utf8) else {
            throw CoreCheckError.clientResponseMissing
        }
        expect(body.contains("chatcmpl_proxy"), "Streaming proxy should forward SSE body")
        guard recordReady.wait(timeout: .now() + 5) == .success else {
            throw CoreCheckError.clientResponseMissing
        }

        recordLock.lock()
        let record = capturedRecords.first
        recordLock.unlock()
        expect(record?.source == .localProxy, "Streaming proxy record source mismatch")
        expect(record?.model == "gpt-4o-mini", "Streaming proxy record model mismatch")
        expect(record?.inputTokens == 9, "Streaming proxy input token mismatch")
        expect(record?.outputTokens == 4, "Streaming proxy output token mismatch")
    }

private func checkClaudeCodeSessionImporter() throws {
        let jsonl = """
        {"type":"assistant","timestamp":"2026-06-08T09:00:00.000Z","message":{"id":"msg_1","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"cache_read_input_tokens":30,"cache_creation_input_tokens":20,"output_tokens":10}}}
        {"type":"assistant","timestamp":"2026-06-08T09:00:01.000Z","message":{"id":"msg_1","model":"claude-sonnet-4-20250514","stop_reason":"end_turn","usage":{"input_tokens":100,"cache_read_input_tokens":30,"cache_creation_input_tokens":20,"output_tokens":40}}}
        {"type":"user","message":{"id":"user_1"}}
        """
        let records = ClaudeCodeSessionImporter.records(fromJSONL: jsonl, project: "demo-project")
        expect(records.count == 1, "Claude session importer should keep one final assistant message")
        let record = records[0]
        expect(record.provider == .anthropic, "Claude session provider mismatch")
        expect(record.model == "claude-sonnet-4-20250514", "Claude session model mismatch")
        expect(record.project == "demo-project", "Claude session project mismatch")
        expect(record.inputTokens == 150, "Claude session input should include cache tokens")
        expect(record.outputTokens == 40, "Claude session output mismatch")
        expect(record.source == .cliSessionLog, "Claude session source mismatch")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite3")
        let database = try UsageDatabase(url: url)
        let firstInsert = try database.insertIfAbsent(record)
        let secondInsert = try database.insertIfAbsent(record)
        let persistedCount = try database.fetchRecords().count
        expect(firstInsert, "First session insert should be new")
        expect(secondInsert == false, "Duplicate session insert should be ignored")
        expect(persistedCount == 1, "Duplicate session record should not be persisted")
    }

private func checkCodexSessionImporter() throws {
        let jsonl = """
        {"timestamp":"2026-06-08T20:06:04.250Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1780966206},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1781152220},"credits":{"has_credits":false,"unlimited":false,"balance":null},"plan_type":"pro","rate_limit_reached_type":null}}}
        {"timestamp":"2026-06-08T20:07:27.800Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1780967224},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1781554024},"credits":{"has_credits":false,"unlimited":false,"balance":null},"plan_type":null,"rate_limit_reached_type":null}}}
        """
        let snapshots = CodexSessionImporter.snapshots(fromJSONL: jsonl)
        expect(snapshots.count == 2, "Codex importer should parse general and model-specific limits")
        let general = snapshots.first { $0.limitID == "codex" }
        expect(general?.planType == "pro", "Codex plan type mismatch")
        expect(general?.primary.windowMinutes == 300, "Codex primary window mismatch")
        expect(general?.primary.remainingRatio == Decimal(string: "0.88"), "Codex primary remaining mismatch")
        expect(general?.secondary.remainingRatio == Decimal(string: "0.8"), "Codex weekly remaining mismatch")

        let modelSpecific = snapshots.first { $0.limitID == "codex_bengalfox" }
        expect(modelSpecific?.limitName == "GPT-5.3-Codex-Spark", "Codex model-specific limit name mismatch")
        expect(modelSpecific?.primary.remainingRatio == 1, "Codex model-specific primary remaining mismatch")

        let historyJSONL = """
        {"timestamp":"2026-06-08T13:22:00.000Z","type":"session_meta","payload":{"cwd":"/Volumes/MacData/Workspace/90_Dev/ai_limit","originator":"Codex Desktop"}}
        {"timestamp":"2026-06-08T13:22:36.623Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50000,"cached_input_tokens":10000,"output_tokens":2000,"reasoning_output_tokens":1200,"total_tokens":52000},"last_token_usage":{"input_tokens":30942,"cached_input_tokens":4992,"output_tokens":749,"reasoning_output_tokens":516,"total_tokens":31691},"model_context_window":258400}},"rate_limits":null}
        {"timestamp":"2026-06-08T13:30:36.623Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":1250}}},"rate_limits":{"limit_name":"GPT-5.3-Codex-Spark"}}
        """
        let records = CodexSessionImporter.usageRecords(fromJSONL: historyJSONL, project: "ai_limit", fileIdentifier: "codex-demo.jsonl")
        expect(records.count == 2, "Codex history importer should parse token_count usage records")
        expect(records[0].provider == .openAI, "Codex history provider mismatch")
        expect(records[0].source == .cliSessionLog, "Codex history source mismatch")
        expect(records[0].apiKeyLabel == "Codex", "Codex history label mismatch")
        expect(records[0].project == "ai_limit", "Codex history project mismatch")
        expect(records[0].model == "Codex", "Codex history default model mismatch")
        expect(records[0].inputTokens == 30942, "Codex history input tokens mismatch")
        expect(records[0].cachedInputTokens == 4992, "Codex history cached tokens mismatch")
        expect(records[0].outputTokens == 749, "Codex history output tokens mismatch")
        expect(records[0].reasoningOutputTokens == 516, "Codex history reasoning tokens mismatch")
        expect(records[0].costUSD == 0, "Codex subscription history should not create variable API cost")
        expect(records[1].model == "GPT-5.3-Codex-Spark", "Codex history should use limit_name when present")
        expect(records[1].inputTokens == 1250, "Codex history total-only fallback mismatch")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite3")
        let database = try UsageDatabase(url: url)
        let firstInsert = try database.insertIfAbsent(records[0])
        let secondInsert = try database.insertIfAbsent(records[0])
        expect(firstInsert, "First Codex history insert should be new")
        expect(secondInsert == false, "Duplicate Codex history insert should be ignored")
    }

private func checkSQLiteRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite3")
        let database = try UsageDatabase(url: url)
        let record = UsageRecord(
            provider: .deepSeek,
            model: "deepseek-v4-pro",
            inputTokens: 1000,
            cachedInputTokens: 300,
            outputTokens: 200,
            reasoningOutputTokens: 80,
            costUSD: Decimal(string: "0.001")!,
            source: .localProxy
        )
        try database.insert(record)
        let records = try database.fetchRecords()
        expect(records.count == 1, "SQLite record count mismatch")
        expect(records.first?.model == "deepseek-v4-pro", "SQLite model mismatch")
        expect(records.first?.provider == .deepSeek, "SQLite provider mismatch")
        expect(records.first?.cachedInputTokens == 300, "SQLite cached token roundtrip mismatch")
        expect(records.first?.reasoningOutputTokens == 80, "SQLite reasoning token roundtrip mismatch")
    }

private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

private func reservePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CoreCheckError.portUnavailable
        }
        defer {
            close(descriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw CoreCheckError.portUnavailable
        }

        var assignedAddress = sockaddr_in()
        var assignedLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assignedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &assignedLength)
            }
        }
        guard nameResult == 0 else {
            throw CoreCheckError.portUnavailable
        }

        return Int(UInt16(bigEndian: assignedAddress.sin_port))
    }

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
