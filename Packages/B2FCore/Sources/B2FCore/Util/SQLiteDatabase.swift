import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public var int64: Int64? {
        switch self {
        case .integer(let v): return v
        case .real(let v): return Int64(v)
        case .text(let s): return Int64(s)
        default: return nil
        }
    }

    public var string: String? {
        switch self {
        case .text(let s): return s
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        case .blob(let d): return String(data: d, encoding: .utf8)
        case .null: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .real(let v): return v
        case .integer(let v): return Double(v)
        case .text(let s): return Double(s)
        default: return nil
        }
    }
}

public struct SQLiteError: Error, LocalizedError {
    public let code: Int32
    public let message: String
    public var errorDescription: String? { "SQLite error \(code): \(message)" }
}

/// Thin SQLite wrapper used to read and write Anki collections.
/// Not thread-safe: confine each instance to one task.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            handle = nil
            throw SQLiteError(code: status, message: message)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    public func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorPointer)
            throw SQLiteError(code: status, message: message)
        }
    }

    public func run(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw lastError(status) }
    }

    public func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: SQLiteValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw lastError(status) }
            var row: [String: SQLiteValue] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                row[name] = value(statement, column)
            }
            rows.append(row)
        }
        return rows
    }

    public func tableExists(_ name: String) -> Bool {
        let rows = try? query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [.text(name)])
        return !(rows?.isEmpty ?? true)
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: Private

    private func prepare(_ sql: String, _ parameters: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK else { throw lastError(status) }
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch parameter {
            case .integer(let v): sqlite3_bind_int64(statement, index, v)
            case .real(let v): sqlite3_bind_double(statement, index, v)
            case .text(let s): sqlite3_bind_text(statement, index, s, -1, Self.transient)
            case .blob(let d):
                _ = d.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(d.count), Self.transient)
                }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func value(_ statement: OpaquePointer?, _ column: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, column) else { return .null }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, column))
            guard let pointer = sqlite3_column_blob(statement, column), count > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: count))
        default: return .null
        }
    }

    private func lastError(_ status: Int32) -> SQLiteError {
        SQLiteError(code: status, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
    }
}
