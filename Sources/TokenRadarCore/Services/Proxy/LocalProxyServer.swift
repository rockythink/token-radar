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
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
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
            self.process(data, connection: connection)
        }
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
                let response = HTTPMessageParser.response(
                    statusCode: 400,
                    reason: "Bad Request",
                    json: [
                        "error": [
                            "message": "Token Radar MVP proxy does not support streaming requests yet.",
                            "type": "unsupported_streaming"
                        ]
                    ]
                )
                send(response, on: connection)
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

    private func forward(
        _ request: ProxyHTTPRequest,
        configuration: Configuration,
        connection: NWConnection
    ) throws {
        let base = configuration.upstreamBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = normalizedUpstreamTarget(baseURL: configuration.upstreamBaseURL, target: request.target)
        guard let url = URL(string: base + target) else {
            throw ProxyError.invalidUpstreamURL
        }

        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        upstream.httpBody = request.body
        upstream.setValue("Bearer \(configuration.upstreamAPIKey)", forHTTPHeaderField: "Authorization")
        upstream.setValue(request.headers["content-type"] ?? "application/json", forHTTPHeaderField: "Content-Type")
        upstream.setValue("TokenRadar/0.1", forHTTPHeaderField: "User-Agent")

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
                let trackedModel = ModelCatalog.trackedModel(for: extracted.model)
                let pricingProvider = trackedModel?.provider ?? configuration.provider
                let cost = PriceCatalog.estimateCost(
                    provider: pricingProvider,
                    model: extracted.model,
                    inputTokens: extracted.inputTokens,
                    outputTokens: extracted.outputTokens
                )
                let record = UsageRecord(
                    provider: configuration.provider,
                    model: extracted.model,
                    project: configuration.projectLabel,
                    apiKeyLabel: configuration.apiKeyLabel,
                    inputTokens: extracted.inputTokens,
                    outputTokens: extracted.outputTokens,
                    costUSD: cost,
                    source: .localProxy
                )
                self.onRecord?(record)
            }

            self.send(
                HTTPMessageParser.response(statusCode: statusCode, reason: reason, body: body, contentType: contentType),
                on: connection
            )
        }.resume()
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
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
