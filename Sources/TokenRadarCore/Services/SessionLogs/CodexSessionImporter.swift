import Foundation
import Darwin

public struct CodexRateLimitWindow: Equatable {
    public var usedPercent: Decimal
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Decimal, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowMinutes = max(0, windowMinutes)
        self.resetsAt = resetsAt
    }

    public var remainingRatio: Decimal {
        min(1, max(0, Decimal(1) - (usedPercent / Decimal(100))))
    }
}

public struct CodexCreditsSnapshot: Equatable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: Decimal?

    public init(hasCredits: Bool, unlimited: Bool, balance: Decimal?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct CodexUsageSnapshot: Identifiable, Equatable {
    public var id: String { limitID }
    public var limitID: String
    public var limitName: String?
    public var timestamp: Date
    public var planType: String?
    public var primary: CodexRateLimitWindow
    public var secondary: CodexRateLimitWindow
    public var credits: CodexCreditsSnapshot?

    public init(
        limitID: String,
        limitName: String?,
        timestamp: Date,
        planType: String?,
        primary: CodexRateLimitWindow,
        secondary: CodexRateLimitWindow,
        credits: CodexCreditsSnapshot?
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.timestamp = timestamp
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }
}

public struct CodexLocalDiscovery: Equatable {
    public var cliURL: URL?
    public var authFileExists: Bool
    public var sessionsDirectoryExists: Bool
    public var sessionFilesExist: Bool

    public init(
        cliURL: URL? = nil,
        authFileExists: Bool = false,
        sessionsDirectoryExists: Bool = false,
        sessionFilesExist: Bool = false
    ) {
        self.cliURL = cliURL
        self.authFileExists = authFileExists
        self.sessionsDirectoryExists = sessionsDirectoryExists
        self.sessionFilesExist = sessionFilesExist
    }

    public var isDetected: Bool {
        cliURL != nil || authFileExists || sessionsDirectoryExists || sessionFilesExist
    }

    public static let empty = CodexLocalDiscovery()
}

public struct CodexSessionImporter {
    public struct HistoryImportResult: Equatable {
        public var imported: Int
        public var skipped: Int
        public var filesScanned: Int
        public var filesSkipped: Int
        public var fileModificationTimes: [String: Double]
        public var errors: [String]

        public init(
            imported: Int = 0,
            skipped: Int = 0,
            filesScanned: Int = 0,
            filesSkipped: Int = 0,
            fileModificationTimes: [String: Double] = [:],
            errors: [String] = []
        ) {
            self.imported = imported
            self.skipped = skipped
            self.filesScanned = filesScanned
            self.filesSkipped = filesSkipped
            self.fileModificationTimes = fileModificationTimes
            self.errors = errors
        }
    }

    public struct SyncResult: Equatable {
        public var snapshots: [CodexUsageSnapshot]
        public var filesScanned: Int
        public var errors: [String]

        public init(
            snapshots: [CodexUsageSnapshot] = [],
            filesScanned: Int = 0,
            errors: [String] = []
        ) {
            self.snapshots = snapshots
            self.filesScanned = filesScanned
            self.errors = errors
        }
    }

    private let sessionsDirectory: URL
    private let fileManager: FileManager
    private let maxFileAgeDays: Int
    private let maxFiles: Int
    private let maxSnapshotScanBytes = 8 * 1024 * 1024
    private let maxIncrementalUsageScanBytes = 16 * 1024 * 1024

    public init(
        sessionsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        maxFileAgeDays: Int = 7,
        maxFiles: Int = 3
    ) {
        self.sessionsDirectory = sessionsDirectory ?? fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.maxFileAgeDays = max(1, maxFileAgeDays)
        self.maxFiles = max(1, maxFiles)
    }

    public func sync() -> SyncResult {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return SyncResult()
        }

        var result = SyncResult()
        var latestByLimitID: [String: CodexUsageSnapshot] = [:]
        let files = recentJSONLFiles()
        result.filesScanned = files.count

        for file in files {
            do {
                for snapshot in try snapshots(from: file) {
                    if let existing = latestByLimitID[snapshot.limitID] {
                        if snapshot.timestamp > existing.timestamp {
                            latestByLimitID[snapshot.limitID] = snapshot
                        }
                    } else {
                        latestByLimitID[snapshot.limitID] = snapshot
                    }
                }
            } catch {
                result.errors.append("\(file.path): \(error.localizedDescription)")
            }
        }

        result.snapshots = latestByLimitID.values.sorted { lhs, rhs in
            if lhs.limitID == "codex" {
                return true
            }
            if rhs.limitID == "codex" {
                return false
            }
            return lhs.limitID < rhs.limitID
        }
        return result
    }

    public func importUsageRecords(
        into database: UsageDatabase,
        knownFileModificationTimes: [String: Double] = [:],
        force: Bool = false
    ) throws -> HistoryImportResult {
        var result = HistoryImportResult()
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return result
        }

        let files = recentJSONLFiles(maxAgeDays: 365, maxCount: 400)

        for file in files {
            let fileKey = file.path
            let modifiedAt = modificationTime(for: file)
            if !force,
               let knownModifiedAt = knownFileModificationTimes[fileKey],
               let modifiedAt,
               abs(knownModifiedAt - modifiedAt) < 0.001 {
                result.filesSkipped += 1
                result.fileModificationTimes[fileKey] = modifiedAt
                continue
            }

            do {
                result.filesScanned += 1
                let shouldImportTailOnly = !force && knownFileModificationTimes[fileKey] != nil
                let records: [UsageRecord]
                if shouldImportTailOnly {
                    records = try usageRecords(
                        fromTailOf: file,
                        fileIdentifier: file.path,
                        maxBytes: maxIncrementalUsageScanBytes
                    )
                } else {
                    records = try usageRecords(from: file, fileIdentifier: file.path)
                }
                for record in records {
                    if try database.insertIfAbsent(record, matchingExistingUsage: shouldImportTailOnly) {
                        result.imported += 1
                    } else {
                        result.skipped += 1
                    }
                }
                if let modifiedAt {
                    result.fileModificationTimes[fileKey] = modifiedAt
                }
            } catch {
                result.errors.append("\(file.path): \(error.localizedDescription)")
            }
        }

        return result
    }

    public static func detectLocalInstallation(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexLocalDiscovery {
        let home = fileManager.homeDirectoryForCurrentUser
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        return CodexLocalDiscovery(
            cliURL: detectCLI(fileManager: fileManager, home: home, environment: environment),
            authFileExists: fileManager.fileExists(atPath: codexDirectory.appendingPathComponent("auth.json").path),
            sessionsDirectoryExists: fileManager.fileExists(atPath: sessionsDirectory.path),
            sessionFilesExist: hasJSONLFile(in: sessionsDirectory, fileManager: fileManager)
        )
    }

    public static func snapshots(fromJSONL content: String) -> [CodexUsageSnapshot] {
        var latestByLimitID: [String: CodexUsageSnapshot] = [:]

        content.enumerateLines { line, _ in
            guard line.contains("\"rate_limits\""),
                  let snapshot = snapshot(fromLine: line)
            else {
                return
            }
            if let existing = latestByLimitID[snapshot.limitID] {
                if snapshot.timestamp > existing.timestamp {
                    latestByLimitID[snapshot.limitID] = snapshot
                }
            } else {
                latestByLimitID[snapshot.limitID] = snapshot
            }
        }

        return latestByLimitID.values.sorted { $0.limitID < $1.limitID }
    }

    private func snapshots(from file: URL) throws -> [CodexUsageSnapshot] {
        var latestByLimitID: [String: CodexUsageSnapshot] = [:]

        let content = try tailContent(in: file, maxBytes: maxSnapshotScanBytes)
        content.enumerateLines { line, _ in
            guard line.contains("\"rate_limits\""),
                  let snapshot = Self.snapshot(fromLine: line)
            else {
                return
            }
            if let existing = latestByLimitID[snapshot.limitID] {
                if snapshot.timestamp > existing.timestamp {
                    latestByLimitID[snapshot.limitID] = snapshot
                }
            } else {
                latestByLimitID[snapshot.limitID] = snapshot
            }
        }

        return latestByLimitID.values.sorted { $0.limitID < $1.limitID }
    }

    public static func usageRecords(
        fromJSONL content: String,
        project: String? = nil,
        fileIdentifier: String = "codex-session"
    ) -> [UsageRecord] {
        var records: [UsageRecord] = []

        content.enumerateLines { line, _ in
            let lineIndex = records.count
            guard line.contains("\"token_count\""),
                  line.contains("\"last_token_usage\""),
                  let record = usageRecord(
                    fromLine: line,
                    project: project,
                    fileIdentifier: fileIdentifier,
                    lineIndex: lineIndex
                  )
            else {
                return
            }
            records.append(record)
        }

        return records.sorted { $0.timestamp < $1.timestamp }
    }

    private func usageRecords(from file: URL, fileIdentifier: String) throws -> [UsageRecord] {
        var project: String?
        var records: [UsageRecord] = []

        try enumerateLines(in: file) { line in
            if project == nil, line.contains("\"session_meta\"") {
                project = Self.projectLabel(fromLine: line)
            }

            let lineIndex = records.count
            guard line.contains("\"token_count\""),
                  line.contains("\"last_token_usage\""),
                  let record = Self.usageRecord(
                    fromLine: line,
                    project: project,
                    fileIdentifier: fileIdentifier,
                    lineIndex: lineIndex
                  )
            else {
                return
            }
            records.append(record)
        }

        return records.sorted { $0.timestamp < $1.timestamp }
    }

    private func usageRecords(fromTailOf file: URL, fileIdentifier: String, maxBytes: Int) throws -> [UsageRecord] {
        let project = try projectLabel(in: file)
        var records: [UsageRecord] = []
        let content = try tailContent(in: file, maxBytes: maxBytes)

        content.enumerateLines { line, _ in
            let lineIndex = records.count
            guard line.contains("\"token_count\""),
                  line.contains("\"last_token_usage\""),
                  let record = Self.usageRecord(
                    fromLine: line,
                    project: project,
                    fileIdentifier: fileIdentifier,
                    lineIndex: lineIndex
                  )
            else {
                return
            }
            records.append(record)
        }

        return records.sorted { $0.timestamp < $1.timestamp }
    }

    private func recentJSONLFiles(maxAgeDays: Int? = nil, maxCount: Int? = nil) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let ageDays = maxAgeDays ?? maxFileAgeDays
        let count = maxCount ?? maxFiles
        let cutoff = Date().addingTimeInterval(TimeInterval(-ageDays * 24 * 60 * 60))
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jsonl" }
            .compactMap { file -> (url: URL, modifiedAt: Date)? in
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true
                else {
                    return nil
                }
                let modifiedAt = values.contentModificationDate ?? .distantPast
                guard modifiedAt >= cutoff else {
                    return nil
                }
                return (file, modifiedAt)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(count)
            .map(\.url)
    }

    private func modificationTime(for file: URL) -> Double? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate
        else {
            return nil
        }
        return modifiedAt.timeIntervalSince1970
    }

    private static func projectLabel(fromJSONL content: String) -> String? {
        var label: String?
        content.enumerateLines { line, stop in
            guard line.contains("\"session_meta\""),
                  let parsed = projectLabel(fromLine: line)
            else {
                return
            }
            label = parsed
            stop = true
        }
        return label
    }

    private static func projectLabel(fromLine line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String
        else {
            return nil
        }
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? trimmed : name
    }

    private func enumerateLines(in file: URL, _ body: (String) -> Void) throws {
        guard let handle = fopen(file.path, "r") else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: file.path]
            )
        }
        defer { fclose(handle) }

        var linePointer: UnsafeMutablePointer<CChar>?
        var lineCapacity = 0
        defer {
            if let linePointer {
                free(linePointer)
            }
        }

        while getline(&linePointer, &lineCapacity, handle) > 0 {
            guard let linePointer else { continue }
            body(String(cString: linePointer))
        }

        if ferror(handle) != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: file.path]
            )
        }
    }

    private func tailContent(in file: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let byteCount = UInt64(max(1, maxBytes))
        let startOffset = fileSize > byteCount ? fileSize - byteCount : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func projectLabel(in file: URL) throws -> String? {
        guard let handle = fopen(file.path, "r") else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: file.path]
            )
        }
        defer { fclose(handle) }

        var linePointer: UnsafeMutablePointer<CChar>?
        var lineCapacity = 0
        defer {
            if let linePointer {
                free(linePointer)
            }
        }

        while getline(&linePointer, &lineCapacity, handle) > 0 {
            guard let linePointer else { continue }
            let line = String(cString: linePointer)
            guard line.contains("\"session_meta\"") else { continue }
            return Self.projectLabel(fromLine: line)
        }

        if ferror(handle) != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: file.path]
            )
        }
        return nil
    }

    private static func detectCLI(
        fileManager: FileManager,
        home: URL,
        environment: [String: String]
    ) -> URL? {
        var candidates: [URL] = []

        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        candidates.append(contentsOf: pathEntries)
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            home.appendingPathComponent(".local/bin/codex")
        ])

        let nvmDirectory = home
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
        if let nodeVersions = try? fileManager.contentsOfDirectory(
            at: nvmDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: nodeVersions.map { $0.appendingPathComponent("bin/codex") })
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func hasJSONLFile(in directory: URL, fileManager: FileManager) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let file as URL in enumerator {
            guard file.pathExtension.lowercased() == "jsonl",
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            return true
        }
        return false
    }

    private static func snapshot(fromLine line: String) -> CodexUsageSnapshot? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg"
        else {
            return nil
        }

        let payload = object["payload"] as? [String: Any]
        let rateLimitsObject = object["rate_limits"] ?? payload?["rate_limits"]
        guard let rateLimits = rateLimitsObject as? [String: Any],
              let primaryObject = rateLimits["primary"] as? [String: Any],
              let secondaryObject = rateLimits["secondary"] as? [String: Any],
              let primary = rateLimitWindow(from: primaryObject),
              let secondary = rateLimitWindow(from: secondaryObject)
        else {
            return nil
        }

        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()
        return CodexUsageSnapshot(
            limitID: rateLimits["limit_id"] as? String ?? "codex",
            limitName: rateLimits["limit_name"] as? String,
            timestamp: timestamp,
            planType: rateLimits["plan_type"] as? String,
            primary: primary,
            secondary: secondary,
            credits: creditsSnapshot(from: rateLimits["credits"] as? [String: Any])
        )
    }

    private static func usageRecord(
        fromLine line: String,
        project: String?,
        fileIdentifier: String,
        lineIndex: Int
    ) -> UsageRecord? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any]
        else {
            return nil
        }

        var inputTokens = intValue(usage["input_tokens"])
        let cachedInputTokens = intValue(usage["cached_input_tokens"])
        let outputTokens = intValue(usage["output_tokens"])
        let reasoningOutputTokens = intValue(usage["reasoning_output_tokens"])
        let reportedTotalTokens = intValue(usage["total_tokens"])
        if inputTokens + outputTokens == 0, reportedTotalTokens > 0 {
            inputTokens = reportedTotalTokens
        }

        guard inputTokens + cachedInputTokens + outputTokens + reasoningOutputTokens > 0 else {
            return nil
        }

        let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()
        let rateLimitsObject = object["rate_limits"] ?? payload["rate_limits"]
        let rateLimits = rateLimitsObject as? [String: Any]
        let limitName = (rateLimits?["limit_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (limitName?.isEmpty == false) ? limitName! : "Codex"
        let seed = [
            "codex-history",
            fileIdentifier,
            "\(lineIndex)",
            "\(timestamp.timeIntervalSince1970)",
            model,
            "\(inputTokens)",
            "\(cachedInputTokens)",
            "\(outputTokens)",
            "\(reasoningOutputTokens)"
        ].joined(separator: ":")

        return UsageRecord(
            id: stableUUID(for: seed),
            timestamp: timestamp,
            provider: .openAI,
            model: model,
            project: project,
            apiKeyLabel: "Codex",
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            costUSD: 0,
            source: .cliSessionLog
        )
    }

    private static func rateLimitWindow(from object: [String: Any]) -> CodexRateLimitWindow? {
        guard let usedPercent = decimalValue(object["used_percent"]) else {
            return nil
        }
        let resetSeconds = doubleValue(object["resets_at"])
        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: intValue(object["window_minutes"]),
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func creditsSnapshot(from object: [String: Any]?) -> CodexCreditsSnapshot? {
        guard let object else { return nil }
        return CodexCreditsSnapshot(
            hasCredits: boolValue(object["has_credits"]),
            unlimited: boolValue(object["unlimited"]),
            balance: decimalValue(object["balance"])
        )
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            value == "true"
        default:
            false
        }
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

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            value
        case let value as Int:
            Double(value)
        case let value as Int64:
            Double(value)
        case let value as NSNumber:
            value.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }

    private static func decimalValue(_ value: Any?) -> Decimal? {
        switch value {
        case let value as Decimal:
            value
        case let value as Double:
            Decimal(value)
        case let value as Int:
            Decimal(value)
        case let value as Int64:
            Decimal(value)
        case let value as NSNumber:
            value.decimalValue
        case let value as String:
            Decimal(string: value)
        default:
            nil
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        if let date = fractionalTimestampFormatter.date(from: raw) {
            return date
        }

        return plainTimestampFormatter.date(from: raw)
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

    private static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
