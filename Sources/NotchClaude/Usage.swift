import Foundation

/// Расход токенов за какой-то период.
struct Tokens: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (a: Tokens, b: Tokens) -> Tokens {
        Tokens(input: a.input + b.input, output: a.output + b.output,
               cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    static func += (a: inout Tokens, b: Tokens) { a = a + b }
}

/// Всё, что показывает виджет.
struct Snapshot {
    var today = Tokens()
    var block = Tokens()            // скользящее 5-часовое окно (окно лимитов Claude)
    var session = Tokens()          // самая свежая сессия
    var requests = 0                // ответов модели в окне
    var lastEvent: Date?
    var model = ""
    var project = ""

    /// Claude считается активным, если запись в логах шевелилась минуту назад.
    var isActive: Bool { lastEvent.map { Date().timeIntervalSince($0) < 60 } ?? false }
}

/// Читает локальные логи Claude Code (`~/.claude/projects/**/*.jsonl`).
enum UsageReader {
    static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    static func snapshot(root: URL = defaultRoot, now: Date = Date()) -> Snapshot {
        let dayStart = Calendar.current.startOfDay(for: now)
        let blockStart = now.addingTimeInterval(-5 * 3600)
        let cutoff = min(dayStart, blockStart)

        var snap = Snapshot()
        var seen = Set<String>()
        var bySession: [String: Tokens] = [:]
        var newest = Date.distantPast
        var newestSession = ""

        for file in files(root: root, modifiedAfter: cutoff) {
            if let mtime = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mtime > (snap.lastEvent ?? .distantPast) {
                snap.lastEvent = mtime
            }
            // ponytail: файл перечитывается целиком на каждое обновление; если станет
            // медленно — запоминать offset и читать хвост.
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"usage\""), let e = entry(from: Data(line.utf8)) else { continue }
                guard seen.insert(e.key).inserted else { continue }   // один и тот же запрос пишется несколько раз
                if e.date >= dayStart { snap.today += e.tokens }
                if e.date >= blockStart {
                    snap.block += e.tokens
                    snap.requests += 1
                }
                bySession[e.session, default: Tokens()] += e.tokens
                if e.date > newest {
                    newest = e.date
                    newestSession = e.session
                    snap.model = e.model
                    snap.project = e.project
                }
            }
        }

        snap.session = bySession[newestSession] ?? Tokens()
        if newest > (snap.lastEvent ?? .distantPast) { snap.lastEvent = newest }
        return snap
    }

    struct Entry {
        let date: Date
        let tokens: Tokens
        let model: String
        let session: String
        let project: String
        let key: String
    }

    static func entry(from data: Data) -> Entry? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let date = date(from: stamp)
        else { return nil }

        return Entry(
            date: date,
            tokens: Tokens(input: int(usage["input_tokens"]),
                           output: int(usage["output_tokens"]),
                           cacheWrite: int(usage["cache_creation_input_tokens"]),
                           cacheRead: int(usage["cache_read_input_tokens"])),
            model: msg["model"] as? String ?? "",
            session: obj["sessionId"] as? String ?? "",
            project: (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
            key: "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? UUID().uuidString)"
        )
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? Int((value as? Double) ?? 0)
    }

    // ponytail: форматтер переиспользуется, читается только из одной фоновой задачи.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(from string: String) -> Date? {
        iso.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func files(root: URL, modifiedAfter: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            return (mtime ?? .distantPast) >= modifiedAfter
        }
    }
}

/// `NotchClaude --selftest` — проверяет парсинг: дедуп, окна, суммы.
func selfTest() {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notch-selftest-\(getpid())")
    try! FileManager.default.createDirectory(at: dir.appendingPathComponent("proj"), withIntermediateDirectories: true)

    let now = Date()
    func line(_ stamp: Date, _ out: Int, req: String, msg: String, session: String = "s1") -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(iso.string(from: stamp))","sessionId":"\(session)",\
        "cwd":"/Users/x/Desktop/vibe","message":{"id":"\(msg)","model":"claude-opus-5","usage":\
        {"input_tokens":1,"output_tokens":\(out),"cache_creation_input_tokens":10,"cache_read_input_tokens":100}}}
        """
    }

    let lines = [
        line(now.addingTimeInterval(-60), 5, req: "r1", msg: "m1"),
        line(now.addingTimeInterval(-60), 5, req: "r1", msg: "m1"),           // дубль — не считается
        line(now.addingTimeInterval(-6 * 3600), 7, req: "r2", msg: "m2"),     // вне 5ч окна
        line(now.addingTimeInterval(-30), 3, req: "r3", msg: "m3", session: "s2"),   // самая свежая сессия
        "{\"type\":\"user\",\"message\":{\"content\":\"hi\"}}",               // не assistant
    ]
    try! lines.joined(separator: "\n").write(to: dir.appendingPathComponent("proj/a.jsonl"), atomically: true, encoding: .utf8)

    let snap = UsageReader.snapshot(root: dir, now: now)
    precondition(snap.requests == 2, "в окне должно быть 2 запроса, а не \(snap.requests)")
    precondition(snap.block.output == 8, "output в окне: \(snap.block.output)")
    precondition(snap.block.cacheRead == 200, "cacheRead в окне: \(snap.block.cacheRead)")
    precondition(snap.session.output == 3, "последняя сессия s2: \(snap.session.output)")
    precondition(snap.project == "vibe", "проект: \(snap.project)")
    precondition(snap.model == "claude-opus-5")
    precondition(snap.block.total == 8 + 2 + 20 + 200, "total: \(snap.block.total)")

    // Записи старше суток и 5ч окна не попадают в файл-фильтр, но в today попадают, если сегодня.
    let sameDay = Calendar.current.isDate(now.addingTimeInterval(-6 * 3600), inSameDayAs: now)
    precondition(snap.today.output == (sameDay ? 15 : 8), "today: \(snap.today.output)")

    try? FileManager.default.removeItem(at: dir)
    print("selftest ok")
}
