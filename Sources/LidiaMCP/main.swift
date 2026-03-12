import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: AnyCodableID?
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: AnyCodableID?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Encodable {
    let code: Int
    let message: String
}

// Flexible ID that can be Int or String
enum AnyCodableID: Codable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { throw DecodingError.typeMismatch(AnyCodableID.self, .init(codingPath: [], debugDescription: "Expected Int or String")) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

// Minimal Any-wrapping Codable type
indirect enum AnyCodable: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case dict([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([AnyCodable].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodable].self) { self = .dict(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dict(let v): try container.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

// MARK: - Database Access

final class MeetingStore {
    private var db: OpaquePointer?

    init() throws {
        let storePath = Self.findStorePath()
        guard FileManager.default.fileExists(atPath: storePath) else {
            throw StoreError.notFound(storePath)
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(storePath, &handle, flags, nil) == SQLITE_OK else {
            throw StoreError.openFailed(String(cString: sqlite3_errmsg(handle!)))
        }
        db = handle
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    static func findStorePath() -> String {
        // SwiftData default store location for SPM executables
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("default.store").path
    }

    func recentMeetings(limit: Int = 20) throws -> [[String: AnyCodable]] {
        let sql = """
            SELECT ZTITLE, ZDATE, ZDURATION, ZSUMMARY, ZSTATUS, Z_PK, ZID
            FROM ZMEETING
            ORDER BY ZDATE DESC
            LIMIT ?
            """
        return try query(sql, bind: [.int(limit)]).map(meetingRow)
    }

    func meeting(byUUID uuid: String) throws -> [String: AnyCodable]? {
        // ZID stores the UUID as a string in SwiftData
        let sql = """
            SELECT ZTITLE, ZDATE, ZDURATION, ZSUMMARY, ZSTATUS, ZREFINEDTRANSCRIPT, Z_PK, ZID,
                   ZCALENDARATTENDEES, ZTEMPLATEID
            FROM ZMEETING
            WHERE ZID = ?
            """
        guard let row = try query(sql, bind: [.string(uuid)]).first else { return nil }
        var result = meetingRow(row)

        // Fetch action items
        if let pk = row["Z_PK"] {
            let actionSQL = """
                SELECT ZTITLE, ZASSIGNEE, ZDEADLINE, ZISCOMPLETED, ZID
                FROM ZACTIONITEM
                WHERE ZMEETING = ?
                """
            let items = try query(actionSQL, bind: [pk]).map { item -> [String: AnyCodable] in
                var dict: [String: AnyCodable] = [:]
                dict["title"] = item["ZTITLE"] ?? .null
                dict["assignee"] = item["ZASSIGNEE"] ?? .null
                dict["deadline"] = item["ZDEADLINE"] ?? .null
                if case .int(let v) = item["ZISCOMPLETED"] {
                    dict["isCompleted"] = .bool(v != 0)
                } else {
                    dict["isCompleted"] = .bool(false)
                }
                return dict
            }
            result["actionItems"] = .array(items.map { .dict($0) })
        }

        if let transcript = row["ZREFINEDTRANSCRIPT"] {
            result["refinedTranscript"] = transcript
        }

        return result
    }

    func searchMeetings(query searchText: String) throws -> [[String: AnyCodable]] {
        let pattern = "%\(searchText)%"
        let sql = """
            SELECT ZTITLE, ZDATE, ZDURATION, ZSUMMARY, ZSTATUS, Z_PK, ZID
            FROM ZMEETING
            WHERE ZTITLE LIKE ? OR ZSUMMARY LIKE ? OR ZREFINEDTRANSCRIPT LIKE ?
            ORDER BY ZDATE DESC
            LIMIT 50
            """
        return try query(sql, bind: [.string(pattern), .string(pattern), .string(pattern)]).map(meetingRow)
    }

    func actionItems(status: String?) throws -> [[String: AnyCodable]] {
        var sql = """
            SELECT ai.ZTITLE, ai.ZASSIGNEE, ai.ZDEADLINE, ai.ZISCOMPLETED, ai.ZID,
                   m.ZTITLE AS ZMEETINGTITLE, m.ZID AS ZMEETINGID
            FROM ZACTIONITEM ai
            LEFT JOIN ZMEETING m ON ai.ZMEETING = m.Z_PK
            """

        let bindings: [AnyCodable] = []
        if let status {
            if status == "pending" {
                sql += " WHERE ai.ZISCOMPLETED = 0"
            } else if status == "completed" {
                sql += " WHERE ai.ZISCOMPLETED = 1"
            }
        }
        sql += " ORDER BY m.ZDATE DESC"

        return try query(sql, bind: bindings).map { row in
            var dict: [String: AnyCodable] = [:]
            dict["title"] = row["ZTITLE"] ?? .null
            dict["assignee"] = row["ZASSIGNEE"] ?? .null
            dict["deadline"] = row["ZDEADLINE"] ?? .null
            if case .int(let v) = row["ZISCOMPLETED"] {
                dict["isCompleted"] = .bool(v != 0)
            } else {
                dict["isCompleted"] = .bool(false)
            }
            dict["meetingTitle"] = row["ZMEETINGTITLE"] ?? .null
            dict["meetingId"] = row["ZMEETINGID"] ?? .null
            return dict
        }
    }

    // MARK: - Helpers

    private func meetingRow(_ row: [String: AnyCodable]) -> [String: AnyCodable] {
        var dict: [String: AnyCodable] = [:]
        dict["id"] = row["ZID"] ?? .null
        dict["title"] = row["ZTITLE"] ?? .null
        dict["summary"] = row["ZSUMMARY"] ?? .null
        dict["status"] = row["ZSTATUS"] ?? .null

        // Convert Core Data timestamp (seconds since 2001-01-01) to ISO 8601
        if case .double(let ts) = row["ZDATE"] {
            let date = Date(timeIntervalSinceReferenceDate: ts)
            dict["date"] = .string(ISO8601DateFormatter().string(from: date))
        }
        if case .double(let d) = row["ZDURATION"] {
            dict["durationSeconds"] = .int(Int(d))
        }
        return dict
    }

    enum BindValue {
        case int(Int)
        case string(String)
    }

    private func query(_ sql: String, bind: [AnyCodable]) throws -> [[String: AnyCodable]] {
        guard let db else { throw StoreError.notOpen }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        for (i, val) in bind.enumerated() {
            let idx = Int32(i + 1)
            switch val {
            case .int(let v): sqlite3_bind_int64(stmt, idx, Int64(v))
            case .string(let v): sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
            default: sqlite3_bind_null(stmt, idx)
            }
        }

        var results: [[String: AnyCodable]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: AnyCodable] = [:]
            let colCount = sqlite3_column_count(stmt)
            for c in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER:
                    row[name] = .int(Int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(stmt, c))
                case SQLITE_TEXT:
                    row[name] = .string(String(cString: sqlite3_column_text(stmt, c)))
                case SQLITE_NULL:
                    row[name] = .null
                default:
                    row[name] = .null
                }
            }
            results.append(row)
        }
        return results
    }

    enum StoreError: LocalizedError {
        case notFound(String)
        case openFailed(String)
        case notOpen
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let p): return "SwiftData store not found at: \(p)"
            case .openFailed(let m): return "Failed to open database: \(m)"
            case .notOpen: return "Database not open"
            case .queryFailed(let m): return "Query failed: \(m)"
            }
        }
    }
}

// MARK: - MCP Server

final class MCPServer {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    var store: MeetingStore?

    init() {
        encoder.outputFormatting = [.sortedKeys]
    }

    func run() {
        // Try to open the store (may fail if LidIA hasn't been run yet)
        do {
            store = try MeetingStore()
        } catch {
            // Store will be nil; tools will return errors
            log("Warning: Could not open meeting store: \(error.localizedDescription)")
        }

        // Read JSON-RPC messages from stdin, one per line
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: data)
                let response = handleRequest(request)
                let responseData = try encoder.encode(response)
                if let json = String(data: responseData, encoding: .utf8) {
                    print(json)
                    fflush(stdout)
                }
            } catch {
                let errResponse = JSONRPCResponse(
                    id: nil,
                    result: nil,
                    error: JSONRPCError(code: -32700, message: "Parse error: \(error.localizedDescription)")
                )
                if let data = try? encoder.encode(errResponse),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                    fflush(stdout)
                }
            }
        }
    }

    func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return initializeResponse(id: request.id)
        case "initialized":
            // Notification, no response needed but we return one anyway for protocol
            return JSONRPCResponse(id: request.id, result: .dict([:]), error: nil)
        case "resources/list":
            return listResources(id: request.id)
        case "resources/read":
            return readResource(id: request.id, params: request.params)
        case "tools/list":
            return listTools(id: request.id)
        case "tools/call":
            return callTool(id: request.id, params: request.params)
        case "ping":
            return JSONRPCResponse(id: request.id, result: .dict([:]), error: nil)
        default:
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    // MARK: - Initialize

    func initializeResponse(id: AnyCodableID?) -> JSONRPCResponse {
        let result: [String: AnyCodable] = [
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .dict([
                "resources": .dict([:]),
                "tools": .dict([:])
            ]),
            "serverInfo": .dict([
                "name": .string("lidia-mcp"),
                "version": .string("1.0.0")
            ])
        ]
        return JSONRPCResponse(id: id, result: .dict(result), error: nil)
    }

    // MARK: - Resources

    func listResources(id: AnyCodableID?) -> JSONRPCResponse {
        let resources: [AnyCodable] = [
            .dict([
                "uri": .string("meetings://recent"),
                "name": .string("Recent Meetings"),
                "description": .string("Last 20 meetings with titles, dates, and summaries"),
                "mimeType": .string("application/json")
            ])
        ]
        return JSONRPCResponse(id: id, result: .dict(["resources": .array(resources)]), error: nil)
    }

    func readResource(id: AnyCodableID?, params: [String: AnyCodable]?) -> JSONRPCResponse {
        guard let uri = params?["uri"]?.stringValue else {
            return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32602, message: "Missing uri parameter"))
        }

        guard let store else {
            return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32000, message: "Meeting store not available. Has LidIA been run at least once?"))
        }

        do {
            if uri == "meetings://recent" {
                let meetings = try store.recentMeetings()
                let json = try encoder.encode(AnyCodable.array(meetings.map { .dict($0) }))
                let contents: [AnyCodable] = [
                    .dict([
                        "uri": .string(uri),
                        "mimeType": .string("application/json"),
                        "text": .string(String(data: json, encoding: .utf8) ?? "[]")
                    ])
                ]
                return JSONRPCResponse(id: id, result: .dict(["contents": .array(contents)]), error: nil)
            } else if uri.hasPrefix("meetings://") {
                let meetingID = String(uri.dropFirst("meetings://".count))
                guard let meeting = try store.meeting(byUUID: meetingID) else {
                    return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32000, message: "Meeting not found"))
                }
                let json = try encoder.encode(AnyCodable.dict(meeting))
                let contents: [AnyCodable] = [
                    .dict([
                        "uri": .string(uri),
                        "mimeType": .string("application/json"),
                        "text": .string(String(data: json, encoding: .utf8) ?? "{}")
                    ])
                ]
                return JSONRPCResponse(id: id, result: .dict(["contents": .array(contents)]), error: nil)
            } else {
                return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32602, message: "Unknown resource URI: \(uri)"))
            }
        } catch {
            return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    // MARK: - Tools

    func listTools(id: AnyCodableID?) -> JSONRPCResponse {
        let tools: [AnyCodable] = [
            .dict([
                "name": .string("search_meetings"),
                "description": .string("Search meetings by title, summary, or transcript content"),
                "inputSchema": .dict([
                    "type": .string("object"),
                    "properties": .dict([
                        "query": .dict([
                            "type": .string("string"),
                            "description": .string("Search text to find in meeting titles, summaries, or transcripts")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ]),
            .dict([
                "name": .string("get_action_items"),
                "description": .string("Get action items from meetings, optionally filtered by status"),
                "inputSchema": .dict([
                    "type": .string("object"),
                    "properties": .dict([
                        "status": .dict([
                            "type": .string("string"),
                            "description": .string("Filter by status: 'pending', 'completed', or omit for all"),
                            "enum": .array([.string("pending"), .string("completed")])
                        ])
                    ])
                ])
            ]),
            .dict([
                "name": .string("get_meeting"),
                "description": .string("Get full details of a specific meeting by its ID, including transcript and action items"),
                "inputSchema": .dict([
                    "type": .string("object"),
                    "properties": .dict([
                        "meeting_id": .dict([
                            "type": .string("string"),
                            "description": .string("The UUID of the meeting")
                        ])
                    ]),
                    "required": .array([.string("meeting_id")])
                ])
            ])
        ]
        return JSONRPCResponse(id: id, result: .dict(["tools": .array(tools)]), error: nil)
    }

    func callTool(id: AnyCodableID?, params: [String: AnyCodable]?) -> JSONRPCResponse {
        guard let toolName = params?["name"]?.stringValue else {
            return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32602, message: "Missing tool name"))
        }

        guard let store else {
            return toolError(id: id, message: "Meeting store not available. Has LidIA been run at least once?")
        }

        let arguments: [String: AnyCodable]
        if case .dict(let args) = params?["arguments"] {
            arguments = args
        } else {
            arguments = [:]
        }

        do {
            switch toolName {
            case "search_meetings":
                guard let query = arguments["query"]?.stringValue else {
                    return toolError(id: id, message: "Missing required parameter: query")
                }
                let results = try store.searchMeetings(query: query)
                return toolResult(id: id, content: results.map { .dict($0) })

            case "get_action_items":
                let status = arguments["status"]?.stringValue
                let results = try store.actionItems(status: status)
                return toolResult(id: id, content: results.map { .dict($0) })

            case "get_meeting":
                guard let meetingID = arguments["meeting_id"]?.stringValue else {
                    return toolError(id: id, message: "Missing required parameter: meeting_id")
                }
                guard let meeting = try store.meeting(byUUID: meetingID) else {
                    return toolError(id: id, message: "Meeting not found with ID: \(meetingID)")
                }
                return toolResult(id: id, content: [.dict(meeting)])

            default:
                return JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: -32602, message: "Unknown tool: \(toolName)"))
            }
        } catch {
            return toolError(id: id, message: error.localizedDescription)
        }
    }

    private func toolResult(id: AnyCodableID?, content: [AnyCodable]) -> JSONRPCResponse {
        let json: Data
        do {
            json = try encoder.encode(AnyCodable.array(content))
        } catch {
            return toolError(id: id, message: "Failed to encode result")
        }
        let text = String(data: json, encoding: .utf8) ?? "[]"
        let result: [String: AnyCodable] = [
            "content": .array([
                .dict([
                    "type": .string("text"),
                    "text": .string(text)
                ])
            ])
        ]
        return JSONRPCResponse(id: id, result: .dict(result), error: nil)
    }

    private func toolError(id: AnyCodableID?, message: String) -> JSONRPCResponse {
        let result: [String: AnyCodable] = [
            "content": .array([
                .dict([
                    "type": .string("text"),
                    "text": .string("Error: \(message)")
                ])
            ]),
            "isError": .bool(true)
        ]
        return JSONRPCResponse(id: id, result: .dict(result), error: nil)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[lidia-mcp] \(message)\n".utf8))
    }
}

// MARK: - Entry Point

let server = MCPServer()
server.run()
