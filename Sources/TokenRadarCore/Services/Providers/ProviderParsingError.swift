import Foundation

public enum ProviderParsingError: Error, LocalizedError {
    case invalidJSON
    case unsupportedShape(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The provider response was not valid JSON."
        case .unsupportedShape(let message):
            message
        }
    }
}

