import Foundation
import Network

public final class LocalProxyServer {
    public struct Configuration: Equatable {
        public var port: Int
        public var upstreamBaseURL: URL
        public var upstreamAPIKey: String
        public var provider: ProviderKind
        public var projectLabel: String?
        public var apiKeyLabel: String?
        public var networkProxy: NetworkProxyConfiguration

        public init(
            port: Int,
            upstreamBaseURL: URL,
            upstreamAPIKey: String,
            provider: ProviderKind,
            projectLabel: String? = "Local Proxy",
            apiKeyLabel: String? = "Proxy",
            networkProxy: NetworkProxyConfiguration = NetworkProxyConfiguration()
        ) {
            self.port = port
            self.upstreamBaseURL = upstreamBaseURL
            self.upstreamAPIKey = upstreamAPIKey
            self.provider = provider
            self.projectLabel = projectLabel
            self.apiKeyLabel = apiKeyLabel
            self.networkProxy = networkProxy
        }
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.elazer.TokenRadar.LocalProxyServer")
    private var configuration: Configuration?
    private var shouldBlockRequest: (() -> Bool)?
    private var onRecord: ((UsageRecord) -> Void)?
    private var onError: ((Error) -> Void)?
    private var activeStreamForwarders: [UUID: StreamingForwarder] = [:]

    public private(set) var isRunning = false

    public init() {}

    public func start(
        configuration: Configuration,
        shouldBlockRequest: @escaping () -> Bool,
        onRecord: @escaping (UsageRecord) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        stop()
        guard let port = NWEndpoint.Port(rawValue: UInt16(configuration.port)) else {
            throw ProxyError.invalidUpstreamURL
        }

        self.configuration = configuration
        self.shouldBlockRequest = shouldBlockRequest
        self.onRecord = onRecord
        self.onError = onError

        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed(let error):
                self?.isRunning = false
                self?.onError?(error)
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        activeStreamForwarders.values.forEach { $0.cancel() }
        activeStreamForwarders.removeAll()
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 10 * 1024 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.onError?(error)
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            nextBuffer.append(data)
            if self.isCompleteHTTPRequest(nextBuffer) {
                self.process(nextBuffer, connection: connection)
            } else {
                self.receiveRequest(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }
        let headerEnd = separatorRange.upperBound
        let headerData = data[..<separatorRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return false
        }

        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0
        return data.count >= headerEnd + contentLength
    }

    private func process(_ data: Data, connection: NWConnection) {
        do {
            guard let configuration else {
                throw ProxyError.invalidUpstreamURL
            }
            let request = try HTTPMessageParser.parseRequest(data)
            guard request.path == "/v1/chat/completions" || request.path == "/v1/responses" else {
                throw ProxyError.unsupportedPath(request.path)
            }
            if shouldBlockRequest?() == true {
                throw ProxyError.blockedByBudget
            }
            if request.isStreamingRequest {
                try forwardStream(request, configuration: configuration, connection: connection)
                return
            }
            try forward(request, configuration: configuration, connection: connection)
        } catch ProxyError.blockedByBudget {
            send(
                HTTPMessageParser.response(
                    statusCode: 402,
                    reason: "Payment Required",
                    json: [
                        "error": [
                            "message": "Token Radar blocked this request because the provider hard cap is exhausted.",
                            "type": "budget_cap_exceeded"
                        ]
                    ]
                ),
                on: connection
            )
        } catch {
            onError?(error)
            send(
                HTTPMessageParser.response(
                    statusCode: 400,
                    reason: "Bad Request",
                    json: ["error": ["message": error.localizedDescription]]
                ),
                on: connection
            )
        }
    }

    private func forwardStream(
        _ request: ProxyHTTPRequest,
        configuration: Configuration,
        connection: NWConnection
    ) throws {
        let upstream = try makeUpstreamRequest(from: request, configuration: configuration)
        let id = UUID()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1

        let forwarder = StreamingForwarder(
            requestID: id,
            request: request,
            configuration: configuration,
            onData: { [weak self] data, close in
                self?.send(data, on: connection, close: close)
            },
            onUsage: { [weak self] usage in
                self?.recordUsage(usage, configuration: configuration)
            },
            onError: { [weak self] error in
                self?.onError?(error)
            },
            onComplete: { [weak self] requestID in
                self?.queue.async {
                    self?.activeStreamForwarders.removeValue(forKey: requestID)
                }
            }
        )
        activeStreamForwarders[id] = forwarder
        forwarder.start(request: upstream, delegateQueue: delegateQueue)
    }

    private func forward(
        _ request: ProxyHTTPRequest,
        configuration: Configuration,
        connection: NWConnection
    ) throws {
        let upstream = try makeUpstreamRequest(from: request, configuration: configuration)

        let session = URLSession(configuration: configuration.networkProxy.urlSessionConfiguration)
        session.dataTask(with: upstream) { [weak self] data, response, error in
            guard let self else { return }
            defer {
                session.finishTasksAndInvalidate()
            }
            if let error {
                self.onError?(error)
                let proxyResponse = HTTPMessageParser.response(
                    statusCode: 502,
                    reason: "Bad Gateway",
                    json: ["error": ["message": error.localizedDescription]]
                )
                self.send(proxyResponse, on: connection)
                return
            }

            let body = data ?? Data()
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"

            if (200..<300).contains(statusCode),
               let extracted = OpenAIUsageExtractor.extract(responseData: body, requestData: request.body) {
                self.recordUsage(extracted, configuration: configuration)
            }

            self.send(
                HTTPMessageParser.response(statusCode: statusCode, reason: reason, body: body, contentType: contentType),
                on: connection
            )
        }.resume()
    }

    private func makeUpstreamRequest(
        from request: ProxyHTTPRequest,
        configuration: Configuration
    ) throws -> URLRequest {
        let base = configuration.upstreamBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = normalizedUpstreamTarget(baseURL: configuration.upstreamBaseURL, target: request.target)
        guard let url = URL(string: base + target) else {
            throw ProxyError.invalidUpstreamURL
        }

        var body = request.body
        if request.path == "/v1/chat/completions", request.isStreamingRequest {
            body = requestBodyByRequestingUsageIfPossible(request.body, provider: configuration.provider)
        }

        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        upstream.httpBody = body
        upstream.setValue("Bearer \(configuration.upstreamAPIKey)", forHTTPHeaderField: "Authorization")
        upstream.setValue(request.headers["content-type"] ?? "application/json", forHTTPHeaderField: "Content-Type")
        upstream.setValue("TokenRadar/0.1", forHTTPHeaderField: "User-Agent")
        return upstream
    }

    private func requestBodyByRequestingUsageIfPossible(_ body: Data, provider: ProviderKind) -> Data {
        guard provider == .openAI else {
            return body
        }
        guard
            var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            object["stream"] as? Bool == true,
            object["stream_options"] == nil
        else {
            return body
        }

        object["stream_options"] = ["include_usage": true]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? body
    }

    private func recordUsage(
        _ usage: OpenAIUsageExtractor.ExtractedUsage,
        configuration: Configuration
    ) {
        let trackedModel = ModelCatalog.trackedModel(for: usage.model)
        let pricingProvider = trackedModel?.provider ?? configuration.provider
        let cost = PriceCatalog.estimateCost(
            provider: pricingProvider,
            model: usage.model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )
        let record = UsageRecord(
            provider: configuration.provider,
            model: usage.model,
            project: configuration.projectLabel,
            apiKeyLabel: configuration.apiKeyLabel,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            costUSD: cost,
            source: .localProxy
        )
        onRecord?(record)
    }

    private func send(_ data: Data, on connection: NWConnection, close: Bool = true) {
        connection.send(content: data, completion: .contentProcessed { _ in
            if close {
                connection.cancel()
            }
        })
    }

    private func normalizedUpstreamTarget(baseURL: URL, target: String) -> String {
        let basePath = baseURL.path
        guard target.hasPrefix("/v1/") else {
            return target
        }
        if basePath.hasSuffix("/v1") || basePath.hasSuffix("/api/v3") {
            return String(target.dropFirst(3))
        }
        return target
    }
}

private final class StreamingForwarder: NSObject, URLSessionDataDelegate {
    private let requestID: UUID
    private let request: ProxyHTTPRequest
    private let configuration: LocalProxyServer.Configuration
    private let onData: (Data, Bool) -> Void
    private let onUsage: (OpenAIUsageExtractor.ExtractedUsage) -> Void
    private let onError: (Error) -> Void
    private let onComplete: (UUID) -> Void
    private var responseBody = Data()
    private var didSendHeader = false
    private var session: URLSession?

    init(
        requestID: UUID,
        request: ProxyHTTPRequest,
        configuration: LocalProxyServer.Configuration,
        onData: @escaping (Data, Bool) -> Void,
        onUsage: @escaping (OpenAIUsageExtractor.ExtractedUsage) -> Void,
        onError: @escaping (Error) -> Void,
        onComplete: @escaping (UUID) -> Void
    ) {
        self.requestID = requestID
        self.request = request
        self.configuration = configuration
        self.onData = onData
        self.onUsage = onUsage
        self.onError = onError
        self.onComplete = onComplete
    }

    func start(request: URLRequest, delegateQueue: OperationQueue) {
        let session = URLSession(
            configuration: configuration.networkProxy.urlSessionConfiguration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? 200
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
        let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "text/event-stream"
        let header = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: \(contentType)",
            "Cache-Control: no-cache",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        didSendHeader = true
        onData(Data(header.utf8), false)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if !didSendHeader {
            let header = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/event-stream",
                "Cache-Control: no-cache",
                "Connection: close",
                "",
                ""
            ].joined(separator: "\r\n")
            didSendHeader = true
            onData(Data(header.utf8), false)
        }

        responseBody.append(data)
        onData(data, false)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            onComplete(requestID)
        }

        if let error {
            onError(error)
            if didSendHeader {
                onData(Data(), true)
                return
            }
            let response = HTTPMessageParser.response(
                statusCode: 502,
                reason: "Bad Gateway",
                json: ["error": ["message": error.localizedDescription]]
            )
            onData(response, true)
            return
        }

        if let http = task.response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let usage = OpenAIUsageExtractor.extractEventStream(
            responseData: responseBody,
            requestData: request.body
           ) {
            onUsage(usage)
        }

        onData(Data(), true)
    }
}
