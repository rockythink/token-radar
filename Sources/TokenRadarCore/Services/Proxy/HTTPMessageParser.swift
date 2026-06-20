import Foundation

public struct ProxyHTTPRequest: Equatable {
    public var method: String
    public var target: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, target: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.target = target
        self.path = path
        self.headers = headers
        self.body = body
    }

    public var jsonBody: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    public var isStreamingRequest: Bool {
        jsonBody?["stream"] as? Bool == true
    }
}

public enum HTTPMessageParser {
    public static func parseRequest(_ data: Data) throws -> ProxyHTTPRequest {
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw ProxyError.invalidHTTPRequest
        }

        let headerData = data[..<separatorRange.lowerBound]
        let bodyStart = separatorRange.upperBound
        let body = Data(data[bodyStart...])

        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ProxyError.invalidHTTPRequest
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw ProxyError.invalidHTTPRequest
        }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw ProxyError.invalidHTTPRequest
        }

        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        let target = requestParts[1]
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target

        return ProxyHTTPRequest(
            method: requestParts[0],
            target: target,
            path: path,
            headers: headers,
            body: body
        )
    }

    public static func response(statusCode: Int, reason: String, json: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])) ?? Data("{}".utf8)
        let headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(headers.utf8) + body
    }

    public static func response(statusCode: Int, reason: String, body: Data, contentType: String = "application/json") -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(headers.utf8) + body
    }
}

public enum ProxyError: Error, LocalizedError {
    case invalidHTTPRequest
    case unsupportedPath(String)
    case invalidUpstreamURL
    case blockedByBudget

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPRequest:
            "Invalid HTTP request."
        case .unsupportedPath(let path):
            "Unsupported proxy path: \(path)."
        case .invalidUpstreamURL:
            "Invalid upstream URL."
        case .blockedByBudget:
            "Request blocked by configured hard budget cap."
        }
    }
}

