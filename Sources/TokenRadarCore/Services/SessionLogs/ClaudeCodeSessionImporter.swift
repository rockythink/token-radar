import Foundation

public struct ClaudeCodeSessionImporter {
    public struct ImportResult: Equatable {
        public var imported: Int
        public var skipped: Int
        public var filesScanned: Int
        public var errors: [String]

        public init(imported: Int = 0, skipped: Int = 0, filesScanned: Int = 0, errors: [String] = []) {
            self.imported = imported
            self.skipped = skipped
            self.filesScanned = filesScanned
            self.errors = errors
        }
    }

    private struct Candidate {
        var messageID: String
        var timestamp: Date
        var model: String
        var project: String?
        var inputTokens: Int
        var outputTokens: Int
        var stopReason: String?

        var isFinal: Bool {
            stopReason?.isEmpty == false
        }
    }

    private let projectsDirectory: URL
    private let fileManager: FileManager

    public init(projectsDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.projectsDirectory = projectsDirectory ?? fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        self.fileManager = fileManager
    }

    public func importRecords(into database: UsageDatabase) throws -> ImportResult {
        var result = ImportResult()
        guard fileManager.fileExists(atPath: projectsDirectory.path) else {
            return result
        }

        let files = jsonlFiles()
        result.filesScanned = files.count

        for file in files {
            do {
                let records = try records(from: file)
                for record in records {
                    if try database.insertIfAbsent(record) {
                        result.imported += 1
                    } else {
                        result.skipped += 1
                    }
                }
            } catch {
                result.errors.append("\(file.path): \(error.localizedDescription)")
            }
        }

        return result
    }

    public func records(from file: URL) throws -> [UsageRecord] {
        let content = try String(contentsOf: file, encoding: .utf8)
        return Self.records(fromJSONL: content, project: projectLabel(for: file))
    }

    public static func records(fromJSONL content: String, project: String? = nil) -> [UsageRecord] {
        var candidates: [String: Candidate] = [:]

        for line in content.split(whereSeparator: \.isNewline) {
            guard let candidate = candidate(fromLine: String(line), project: project) else {
                continue
            }

            if let existing = candidates[candidate.messageID] {
                if shouldReplace(existing: existing, with: candidate) {
                    candidates[candidate.messageID] = candidate
                }
            } else {
                candidates[candidate.messageID] = candidate
            }
        }

        return candidates.values
            .filter { $0.isFinal && $0.outputTokens > 0 }
            .map(record(from:))
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func jsonlFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jsonl" }
            .sorted { $0.path < $1.path }
    }

    private func projectLabel(for file: URL) -> String? {
        let parent = file.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" {
            return parent
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .lastPathComponent
        }
        return parent.lastPathComponent.isEmpty ? nil : parent.lastPathComponent
    }

    private static func candidate(fromLine line: String, project: String?) -> Candidate? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let messageID = message["id"] as? String,
              let usage = message["usage"] as? [String: Any]
        else {
            return nil
        }

        let inputTokens = intValue(usage["input_tokens"])
        let cacheReadTokens = intValue(usage["cache_read_input_tokens"])
        let cacheCreationTokens = intValue(usage["cache_creation_input_tokens"])
        let totalInputTokens = inputTokens + cacheReadTokens + cacheCreationTokens
        let outputTokens = intValue(usage["output_tokens"])
        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()
        let model = message["model"] as? String ?? "claude"

        return Candidate(
            messageID: messageID,
            timestamp: timestamp,
            model: model,
            project: project,
            inputTokens: totalInputTokens,
            outputTokens: outputTokens,
            stopReason: message["stop_reason"] as? String
        )
    }

    private static func record(from candidate: Candidate) -> UsageRecord {
        let cost = PriceCatalog.estimateCost(
            provider: .anthropic,
            model: candidate.model,
            inputTokens: candidate.inputTokens,
            outputTokens: candidate.outputTokens
        )

        return UsageRecord(
            id: stableUUID(for: "claude-code:\(candidate.messageID)"),
            timestamp: candidate.timestamp,
            provider: .anthropic,
            model: candidate.model,
            project: candidate.project,
            apiKeyLabel: "Claude Code",
            inputTokens: candidate.inputTokens,
            outputTokens: candidate.outputTokens,
            costUSD: cost,
            source: .cliSessionLog
        )
    }

    private static func shouldReplace(existing: Candidate, with next: Candidate) -> Bool {
        if next.isFinal && !existing.isFinal {
            return true
        }
        if next.isFinal == existing.isFinal {
            return next.outputTokens > existing.outputTokens
        }
        return false
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            value
        case let value as Int64:
            Int(value)
        case let value as Double:
            Int(value)
        case let value as NSNumber:
            value.intValue
        default:
            0
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func stableUUID(for seed: String) -> UUID {
        var left: UInt64 = 0xcbf29ce484222325
        var right: UInt64 = 0x84222325cbf29ce4

        for byte in seed.utf8 {
            left ^= UInt64(byte)
            left = left &* 0x100000001b3
            right ^= UInt64(byte) &+ 0x9e
            right = right &* 0x100000001b3
        }

        var bytes = bigEndianBytes(left) + bigEndianBytes(right)
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func bigEndianBytes(_ value: UInt64) -> [UInt8] {
        (0..<8).map { offset in
            UInt8((value >> UInt64((7 - offset) * 8)) & 0xff)
        }
    }
}
