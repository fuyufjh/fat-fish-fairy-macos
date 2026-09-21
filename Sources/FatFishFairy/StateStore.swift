import Foundation
import CSQLite

/// Messages are upserted, never replaced by the visible page of history.
final class StateStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("state.sqlite") }
    var legacyFile: URL { directory.appendingPathComponent("state.json") }
    private var db: OpaquePointer?
    private var ready = false
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FatFishFairy", isDirectory: true)
    }
    deinit { sqlite3_close(db) }

    private func open() throws {
        guard !ready else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if db == nil {
            guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw failure() }
            sqlite3_busy_timeout(db, 5000)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS messages (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, role TEXT NOT NULL, text TEXT NOT NULL, date REAL NOT NULL, observation INTEGER NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, text TEXT NOT NULL, date REAL NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS screen_observations (seq INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL)")
        // Import and completion marker commit together. A bad legacy file is left untouched.
        try transaction {
            if try rows("SELECT value FROM metadata WHERE key = 'initialized'").isEmpty {
                if FileManager.default.fileExists(atPath: legacyFile.path) {
                    let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: legacyFile))
                    try write(state)
                }
                try execute("INSERT INTO metadata(key,value) VALUES('initialized','1')")
            }
        }
        ready = true
    }
    func load() throws -> SavedState {
        try open()
        let prefs = try rows("SELECT value FROM metadata WHERE key = 'preferences'").first?.first
        return SavedState(preferences: try prefs.map { try JSONDecoder().decode(Preferences.self, from: Data($0.utf8)) } ?? Preferences(),
                          messages: try messagePage(), memories: try rows("SELECT id,text,date FROM memories ORDER BY date,rowid").map {
            guard let id = UUID(uuidString: $0[0]), let date = Double($0[2]) else { throw failure() }
            return FishMemory(id: id, text: $0[1], date: Date(timeIntervalSince1970: date))
        })
    }
    func messagePage(before id: UUID? = nil, limit: Int = 50) throws -> [ChatMessage] {
        try open()
        let predicate = id == nil ? "" : "WHERE seq < (SELECT seq FROM messages WHERE id = ?)"
        let values = (id.map { [$0.uuidString] } ?? []) + [String(max(1, min(limit, 500)))]
        return try rows("SELECT id,role,text,date,observation FROM messages \(predicate) ORDER BY seq DESC LIMIT ?", values).reversed().map {
            guard let id = UUID(uuidString: $0[0]), let date = Double($0[3]) else { throw failure() }
            return ChatMessage(id: id, role: $0[1], text: $0[2], date: Date(timeIntervalSince1970: date), observation: $0[4] == "1")
        }
    }
    func hasMessages(before id: UUID?) throws -> Bool {
        guard let id else { return false }
        try open()
        return try !rows("SELECT 1 FROM messages WHERE seq < (SELECT seq FROM messages WHERE id = ?) LIMIT 1", [id.uuidString]).isEmpty
    }
    func save(_ state: SavedState) throws {
        try open()
        try transaction { try write(state) }
    }
    func screenHistory() throws -> [String] {
        try open()
        return try rows("SELECT content FROM screen_observations ORDER BY seq DESC LIMIT 3").reversed().map { $0[0] }
    }
    func appendScreenContent(_ content: String) throws {
        try open()
        try transaction {
            try execute("INSERT INTO screen_observations(content) VALUES(?)", [content])
            try execute("DELETE FROM screen_observations WHERE seq NOT IN (SELECT seq FROM screen_observations ORDER BY seq DESC LIMIT 3)")
        }
    }
    private func write(_ state: SavedState) throws {
        let preferences = String(decoding: try JSONEncoder().encode(state.preferences), as: UTF8.self)
        try execute("INSERT INTO metadata(key,value) VALUES('preferences',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [preferences])
        for message in state.messages {
            try execute("INSERT INTO messages(id,role,text,date,observation) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET role=excluded.role,text=excluded.text,date=excluded.date,observation=excluded.observation",
                        [message.id.uuidString, message.role, message.text, String(message.date.timeIntervalSince1970), message.observation ? "1" : "0"])
        }
        try execute("DELETE FROM memories")
        for memory in state.memories {
            try execute("INSERT INTO memories(id,text,date) VALUES(?,?,?)", [memory.id.uuidString, memory.text, String(memory.date.timeIntervalSince1970)])
        }
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func failure() -> FishError { .message("SQLite 数据读写失败（\(sqlite3_errcode(db))）。原有数据已保留。") }
    private func statement(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if status != SQLITE_OK { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    private func execute(_ sql: String, _ values: [String] = []) throws {
        let query = try statement(sql, values); defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_DONE else { throw failure() }
    }
    private func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        let query = try statement(sql, values); defer { sqlite3_finalize(query) }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(query)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw failure() }
            result.append((0..<sqlite3_column_count(query)).map { index in
                guard let bytes = sqlite3_column_text(query, index) else { return "" }
                return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(query, index))), as: UTF8.self)
            })
        }
    }
}
