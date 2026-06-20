import Foundation

public final class SettingsStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL? = nil) throws {
        if let url {
            self.url = url
        } else {
            self.url = try Self.defaultURL()
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppSettings()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    public static func defaultURL() throws -> URL {
        let directory = try applicationSupportDirectory()
        return directory.appendingPathComponent("settings.json")
    }

    public static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("TokenRadar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

