import Foundation

public enum NetworkProxyMode: String, CaseIterable, Codable, Identifiable {
    case system
    case direct
    case http
    case socks

    public var id: String { rawValue }
}

public struct NetworkProxyConfiguration: Codable, Equatable {
    public var mode: NetworkProxyMode
    public var host: String
    public var port: Int

    public init(
        mode: NetworkProxyMode = .system,
        host: String = "127.0.0.1",
        port: Int = 7890
    ) {
        self.mode = mode
        self.host = host
        self.port = port
    }

    public var urlSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        switch mode {
        case .system:
            break
        case .direct:
            configuration.connectionProxyDictionary = [:]
        case .http:
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port
            ]
        case .socks:
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port
            ]
        }
        return configuration
    }
}
