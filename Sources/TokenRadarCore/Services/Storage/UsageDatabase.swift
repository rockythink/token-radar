import Foundation
import SQLite3

public final class UsageDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.elazer.TokenRadar.UsageDatabase")

    public init(url: URL? = nil) throws {
        let databaseURL = try url ?? Self.defaultURL()
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw SQLiteStoreError.open(message: currentErrorMessage)
        }
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    public func insert(_ record: UsageRecord) throws {
        try queue.sync {
            let sql = """
            INSERT OR REPLACE INTO usage_records (
                id, timestamp, provider, model, project, api_key_label,
                input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                cost_usd, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            try prepare(sql, &statement)
            defer { sqlite3_finalize(statement) }

            bindText(statement, index: 1, value: record.id.uuidString)
            sqlite3_bind_double(statement, 2, record.timestamp.timeIntervalSince1970)
            bindText(statement, index: 3, value: record.provider.rawValue)
            bindText(statement, index: 4, value: record.model)
            bindOptionalText(statement, index: 5, value: record.project)
            bindOptionalText(statement, index: 6, value: record.apiKeyLabel)
            sqlite3_bind_int64(statement, 7, Int64(record.inputTokens))
            sqlite3_bind_int64(statement, 8, Int64(record.cachedInputTokens))
            sqlite3_bind_int64(statement, 9, Int64(record.outputTokens))
            sqlite3_bind_int64(statement, 10, Int64(record.reasoningOutputTokens))
            sqlite3_bind_double(statement, 11, DecimalCoding.double(record.costUSD))
            bindText(statement, index: 12, value: record.source.rawValue)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.step(message: currentErrorMessage)
            }
        }
    }

    @discardableResult
    public func insertIfAbsent(_ record: UsageRecord, matchingExistingUsage: Bool = false) throws -> Bool {
        try queue.sync {
            if matchingExistingUsage, try recordExistsMatchingUsage(record) {
                return false
            }

            let sql = """
            INSERT OR IGNORE INTO usage_records (
                id, timestamp, provider, model, project, api_key_label,
                input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
                cost_usd, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            try prepare(sql, &statement)
            defer { sqlite3_finalize(statement) }

            bindText(statement, index: 1, value: record.id.uuidString)
            sqlite3_bind_double(statement, 2, record.timestamp.timeIntervalSince1970)
            bindText(statement, index: 3, value: record.provider.rawValue)
            bindText(statement, index: 4, value: record.model)
            bindOptionalText(statement, index: 5, value: record.project)
            bindOptionalText(statement, index: 6, value: record.apiKeyLabel)
            sqlite3_bind_int64(statement, 7, Int64(record.inputTokens))
            sqlite3_bind_int64(statement, 8, Int64(record.cachedInputTokens))
            sqlite3_bind_int64(statement, 9, Int64(record.outputTokens))
            sqlite3_bind_int64(statement, 10, Int64(record.reasoningOutputTokens))
            sqlite3_bind_double(statement, 11, DecimalCoding.double(record.costUSD))
            bindText(statement, index: 12, value: record.source.rawValue)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.step(message: currentErrorMessage)
            }

            return sqlite3_changes(db) > 0
        }
    }

    private func recordExistsMatchingUsage(_ record: UsageRecord) throws -> Bool {
        let sql = """
        SELECT 1 FROM usage_records
        WHERE ABS(timestamp - ?) < 0.001
          AND provider = ?
          AND model = ?
          AND COALESCE(project, '') = COALESCE(?, '')
          AND COALESCE(api_key_label, '') = COALESCE(?, '')
          AND input_tokens = ?
          AND cached_input_tokens = ?
          AND output_tokens = ?
          AND reasoning_output_tokens = ?
          AND source = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        try prepare(sql, &statement)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, record.timestamp.timeIntervalSince1970)
        bindText(statement, index: 2, value: record.provider.rawValue)
        bindText(statement, index: 3, value: record.model)
        bindOptionalText(statement, index: 4, value: record.project)
        bindOptionalText(statement, index: 5, value: record.apiKeyLabel)
        sqlite3_bind_int64(statement, 6, Int64(record.inputTokens))
        sqlite3_bind_int64(statement, 7, Int64(record.cachedInputTokens))
        sqlite3_bind_int64(statement, 8, Int64(record.outputTokens))
        sqlite3_bind_int64(statement, 9, Int64(record.reasoningOutputTokens))
        bindText(statement, index: 10, value: record.source.rawValue)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    public func insert(snapshot: ProviderUsageSnapshot) throws {
        let groups = snapshot.groups.isEmpty
            ? [UsageGroup(provider: snapshot.provider, spendUSD: snapshot.spendUSD, inputTokens: snapshot.inputTokens, outputTokens: snapshot.outputTokens, requestCount: snapshot.requestCount)]
            : snapshot.groups

        for group in groups {
            let record = UsageRecord(
                timestamp: snapshot.fetchedAt,
                provider: snapshot.provider,
                model: group.model ?? snapshot.provider.displayName,
                project: group.project,
                apiKeyLabel: group.apiKeyLabel,
                inputTokens: group.inputTokens,
                outputTokens: group.outputTokens,
                costUSD: group.spendUSD,
                source: snapshot.source
            )
            try insert(record)
        }
    }

    public func fetchRecords(since startDate: Date? = nil) throws -> [UsageRecord] {
        try queue.sync {
            var records: [UsageRecord] = []
            let hasStart = startDate != nil
            let sql = hasStart
                ? "SELECT id, timestamp, provider, model, project, api_key_label, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, cost_usd, source FROM usage_records WHERE timestamp >= ? ORDER BY timestamp DESC;"
                : "SELECT id, timestamp, provider, model, project, api_key_label, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, cost_usd, source FROM usage_records ORDER BY timestamp DESC;"

            var statement: OpaquePointer?
            try prepare(sql, &statement)
            defer { sqlite3_finalize(statement) }

            if let startDate {
                sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = columnText(statement, index: 0)
                let providerRaw = columnText(statement, index: 2)
                let sourceRaw = columnText(statement, index: 11)
                guard
                    let id = UUID(uuidString: idString),
                    let provider = ProviderKind(rawValue: providerRaw),
                    let source = UsageSource(rawValue: sourceRaw)
                else {
                    continue
                }

                records.append(
                    UsageRecord(
                        id: id,
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        provider: provider,
                        model: columnText(statement, index: 3),
                        project: columnOptionalText(statement, index: 4),
                        apiKeyLabel: columnOptionalText(statement, index: 5),
                        inputTokens: Int(sqlite3_column_int64(statement, 6)),
                        cachedInputTokens: Int(sqlite3_column_int64(statement, 7)),
                        outputTokens: Int(sqlite3_column_int64(statement, 8)),
                        reasoningOutputTokens: Int(sqlite3_column_int64(statement, 9)),
                        costUSD: Decimal(sqlite3_column_double(statement, 10)),
                        source: source
                    )
                )
            }

            return records
        }
    }

    public func deleteAll() throws {
        try queue.sync {
            guard sqlite3_exec(db, "DELETE FROM usage_records;", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteStoreError.step(message: currentErrorMessage)
            }
        }
    }

    public func deleteRecords(project: String) throws {
        try queue.sync {
            let sql = "DELETE FROM usage_records WHERE project = ?;"
            var statement: OpaquePointer?
            try prepare(sql, &statement)
            defer { sqlite3_finalize(statement) }

            bindText(statement, index: 1, value: project)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.step(message: currentErrorMessage)
            }
        }
    }

    public static func defaultURL() throws -> URL {
        let directory = try SettingsStore.applicationSupportDirectory()
        return directory.appendingPathComponent("token-radar.sqlite3")
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS usage_records (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            project TEXT,
            api_key_label TEXT,
            input_tokens INTEGER NOT NULL,
            cached_input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL,
            reasoning_output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL,
            source TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_usage_records_timestamp ON usage_records(timestamp);
        CREATE INDEX IF NOT EXISTS idx_usage_records_provider ON usage_records(provider);
        CREATE INDEX IF NOT EXISTS idx_usage_records_provider_timestamp ON usage_records(provider, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_usage_records_source_timestamp ON usage_records(source, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_usage_records_model ON usage_records(model);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError.schema(message: currentErrorMessage)
        }
        try ensureColumn(
            table: "usage_records",
            name: "cached_input_tokens",
            definition: "cached_input_tokens INTEGER NOT NULL DEFAULT 0"
        )
        try ensureColumn(
            table: "usage_records",
            name: "reasoning_output_tokens",
            definition: "reasoning_output_tokens INTEGER NOT NULL DEFAULT 0"
        )
    }

    private func prepare(_ sql: String, _ statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepare(message: currentErrorMessage)
        }
    }

    private func ensureColumn(table: String, name: String, definition: String) throws {
        guard !table.contains("'"), !name.contains("'"), !definition.contains(";") else {
            throw SQLiteStoreError.schema(message: "Invalid migration identifier.")
        }

        var statement: OpaquePointer?
        try prepare("PRAGMA table_info('\(table)');", &statement)

        var exists = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, index: 1) == name {
                exists = true
                break
            }
        }
        sqlite3_finalize(statement)

        guard !exists else { return }
        guard sqlite3_exec(db, "ALTER TABLE \(table) ADD COLUMN \(definition);", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError.schema(message: currentErrorMessage)
        }
    }

    private var currentErrorMessage: String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "Unknown SQLite error."
    }
}

public enum SQLiteStoreError: Error, LocalizedError {
    case open(message: String)
    case schema(message: String)
    case prepare(message: String)
    case step(message: String)

    public var errorDescription: String? {
        switch self {
        case .open(let message), .schema(let message), .prepare(let message), .step(let message):
            message
        }
    }
}

private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
    if let value {
        bindText(statement, index: index, value: value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func columnText(_ statement: OpaquePointer?, index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: pointer)
}

private func columnOptionalText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnText(statement, index: index)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
