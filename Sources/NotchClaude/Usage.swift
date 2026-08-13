import Foundation

/// Читает локальные логи Claude Code (`~/.claude/projects/**/*.jsonl`) и собирает `Snapshot`.
enum UsageReader {
    static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    static let historyDays = 30         // глубина истории для лимитов
    static let blockSpan: TimeInterval = 5 * 3600
    static let bucketSpan: TimeInterval = 1800      // получасовые бакеты
    static let bucketCount = 10                     // 10 × 30 мин = 5 часов

    /// Один ответ модели. Держим только нужное — сырые строки в памяти не остаются.
    struct Entry {
        let date: Date
        let tokens: Tokens
        let model: String       // уже укороченное имя
        let session: String
        let project: String
        let key: String         // message.id|requestId — для дедупа
    }

    // MARK: - Снимок

    static func snapshot(root: URL = defaultRoot, now: Date = Date()) -> Snapshot {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let historyStart = cal.date(byAdding: .day, value: -(historyDays - 1), to: dayStart) ?? dayStart
        let weekStart = cal.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let blockFrom = now.addingTimeInterval(-blockSpan)

        var snap = Snapshot()
        var seen = Set<String>()
        var all: [Entry] = []
        var lastMtime = Date.distantPast
        var alive = Set<String>()

        for file in files(root: root, modifiedAfter: historyStart) {
            alive.insert(file.path)
            let (entries, mtime) = cached(file)
            lastMtime = max(lastMtime, mtime)
            for e in entries where e.date >= historyStart {
                if seen.insert(e.key).inserted { all.append(e) }   // один запрос пишется в лог несколько раз
            }
        }
        cache = cache.filter { alive.contains($0.key) }            // файлы, вышедшие из окна истории

        all.sort { $0.date < $1.date }

        var dayTotals: [Date: Tokens] = [:]     // все сутки истории — для weekLimit
        var buckets: [Date: Tokens] = [:]       // выровненные получасовки — для blockLimit
        var models: [String: Tokens] = [:]      // за неделю
        var series = [Tokens](repeating: Tokens(), count: bucketCount)

        for e in all {
            dayTotals[cal.startOfDay(for: e.date), default: Tokens()] += e.tokens
            buckets[align(e.date), default: Tokens()] += e.tokens

            if e.date >= dayStart { snap.today += e.tokens }
            if e.date >= weekStart {
                snap.week += e.tokens
                models[e.model, default: Tokens()] += e.tokens
            }
            if e.date >= blockFrom {
                snap.block += e.tokens
                snap.requests += 1
                if snap.blockStart == nil { snap.blockStart = e.date }   // all отсортирован — первый ответ в окне
                let i = min(bucketCount - 1, Int(e.date.timeIntervalSince(blockFrom) / bucketSpan))
                series[i] += e.tokens
            }
        }

        if let newest = all.last {
            snap.model = newest.model
            snap.project = newest.project
            for e in all where e.session == newest.session {
                snap.session += e.tokens
                snap.sessionRequests += 1
            }
            snap.lastEvent = max(newest.date, lastMtime)
        } else if lastMtime > .distantPast {
            snap.lastEvent = lastMtime
        }

        snap.byDay = (0..<7).map { i -> DayUsage in
            let day = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
            return DayUsage(date: day, tokens: dayTotals[day] ?? Tokens())   // пустые дни — нулями, чтобы график не рвался
        }
        snap.byModel = models
            .map { ModelUsage(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens.total == $1.tokens.total ? $0.model < $1.model : $0.tokens.total > $1.tokens.total }
        snap.blockSeries = series.enumerated().map {
            BucketUsage(start: blockFrom.addingTimeInterval(Double($0.offset) * bucketSpan), tokens: $0.element)
        }

        // Лимиты не публикуются, поэтому за ориентир берём собственный исторический максимум.
        // ponytail: скользящее окно по получасовкам — точность 30 мин, хватает для полоски прогресса.
        snap.blockLimit = max(maxWindow(buckets, span: blockSpan), snap.block.total, 1)
        snap.weekLimit = max(maxWindow(dayTotals, span: 7 * 86400), snap.week.total)
        return snap
    }

    /// Начало получасового бакета (сетка выровнена по абсолютному времени).
    private static func align(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / bucketSpan).rounded(.down) * bucketSpan)
    }

    /// Максимальная сумма по любому окну длиной `span`, скользящему по непустым точкам.
    private static func maxWindow(_ totals: [Date: Tokens], span: TimeInterval) -> Int {
        let keys = totals.keys.sorted()
        var best = 0
        for (i, start) in keys.enumerated() {
            var sum = 0
            var j = i
            while j < keys.count, keys[j].timeIntervalSince(start) < span {
                sum += totals[keys[j]]?.total ?? 0
                j += 1
            }
            best = max(best, sum)
        }
        return best
    }

    // MARK: - Кеш разобранных файлов

    private struct Cached {
        var size: Int
        var mtime: Date
        var offset: UInt64      // сколько байт уже разобрано (по границе строки)
        var entries: [Entry]
    }

    // ponytail: словарь без блокировки — `snapshot()` обязан вызываться строго по одному
    // (для этого в `Model` заведена своя последовательная очередь). Понадобится параллельный
    // вызов — обернуть в actor: иначе гонка ломает кучу и приложение падает с SIGABRT.
    nonisolated(unsafe) private static var cache: [String: Cached] = [:]

    /// Записи файла: из кеша, если он не менялся; дочитывая хвост, если файл дорос.
    private static func cached(_ file: URL) -> ([Entry], Date) {
        let path = file.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast

        if let old = cache[path], old.size == size, old.mtime == mtime { return (old.entries, mtime) }

        // Лог только дописывается; если он усох — читаем заново.
        let old = cache[path].flatMap { $0.size <= size ? $0 : nil }
        guard let chunk = read(file, from: old?.offset ?? 0) else {
            cache[path] = nil
            return ([], mtime)
        }

        var entries = old?.entries ?? []
        var consumed = 0
        if let nl = chunk.lastIndex(of: 0x0A) {                  // недописанный хвост оставляем на потом
            let complete = chunk[..<chunk.index(after: nl)]
            consumed = complete.count
            // Ищем `"usage"` сразу по всему куску и расширяем находку до границ строки: резать
            // сотни мегабайт логов на строки, чтобы отбросить 99% из них, вдвое дороже.
            let needle = Data("\"usage\"".utf8)
            var from = complete.startIndex
            while from < complete.endIndex, let hit = complete.range(of: needle, in: from..<complete.endIndex) {
                let start = complete[..<hit.lowerBound].lastIndex(of: 0x0A).map { complete.index(after: $0) }
                    ?? complete.startIndex
                let end = complete[hit.upperBound...].firstIndex(of: 0x0A) ?? complete.endIndex
                if let e = entry(from: complete[start..<end]) { entries.append(e) }
                from = end < complete.endIndex ? complete.index(after: end) : complete.endIndex
            }
        }
        cache[path] = Cached(size: size, mtime: mtime, offset: (old?.offset ?? 0) + UInt64(consumed), entries: entries)
        return (entries, mtime)
    }

    private static func read(_ file: URL, from offset: UInt64) -> Data? {
        // mmap: сотни мегабайт логов не тащим в heap. Логи только дописываются, так что
        // ponytail: усечение файла под отображением не рассматриваем.
        if offset == 0 { return try? Data(contentsOf: file, options: .mappedIfSafe) }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return nil }
        return (try? handle.readToEnd()) ?? Data()
    }

    // MARK: - Разбор строки

    static func entry(from data: Data) -> Entry? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let date = date(from: stamp)
        else { return nil }

        // `<synthetic>` — служебные записи самого Claude Code, а не ответы модели: расход нулевой,
        // но счётчик ответов и список моделей они портят.
        let model = shortModel(msg["model"] as? String ?? "")
        guard !model.isEmpty, !model.hasPrefix("<") else { return nil }

        return Entry(
            date: date,
            tokens: Tokens(input: int(usage["input_tokens"]),
                           output: int(usage["output_tokens"]),
                           cacheWrite: int(usage["cache_creation_input_tokens"]),
                           cacheRead: int(usage["cache_read_input_tokens"])),
            model: model,
            session: obj["sessionId"] as? String ?? "",
            project: (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
            key: "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? UUID().uuidString)"
        )
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4-5`, `claude-opus-5[1m]` → `opus-5`.
    static func shortModel(_ raw: String) -> String {
        var s = raw
        if s.hasSuffix("[1m]") { s.removeLast(4) }
        if s.hasPrefix("claude-") { s.removeFirst(7) }
        if let tail = s.range(of: "-[0-9]{8}$", options: .regularExpression) { s.removeSubrange(tail) }
        return s
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

    /// Разбор `2026-08-13T06:03:21.123Z` по фиксированным позициям: `ISO8601DateFormatter`
    /// на 26 тысячах записей стоит 0.5 с, руками — 0.05 с. Всё нестандартное отдаём форматтеру.
    static func date(from string: String) -> Date? {
        let u = Array(string.utf8)
        func num(_ from: Int, _ count: Int) -> Int? {
            var n = 0
            for i in from..<(from + count) {
                guard u[i] >= 48, u[i] <= 57 else { return nil }
                n = n * 10 + Int(u[i] - 48)
            }
            return n
        }
        guard u.count >= 20, u.last == UInt8(ascii: "Z"), u[4] == UInt8(ascii: "-"), u[10] == UInt8(ascii: "T"),
              let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2)
        else { return iso.date(from: string) ?? ISO8601DateFormatter().date(from: string) }

        var parts = tm()
        parts.tm_year = Int32(year - 1900)
        parts.tm_mon = Int32(month - 1)
        parts.tm_mday = Int32(day)
        parts.tm_hour = Int32(hour)
        parts.tm_min = Int32(minute)
        parts.tm_sec = Int32(second)
        let millis = (u.count >= 24 && u[19] == UInt8(ascii: ".") ? num(20, 3) : 0) ?? 0
        return Date(timeIntervalSince1970: Double(timegm(&parts)) + Double(millis) / 1000)
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

/// `NotchClaude --selftest` — проверяет разбор логов: дедуп, окна, разбивки, лимиты.
/// `precondition`, а не `assert`, чтобы работало и в release.
func selfTest() {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notch-selftest-\(getpid())")
    try! FileManager.default.createDirectory(at: dir.appendingPathComponent("proj"), withIntermediateDirectories: true)
    let log = dir.appendingPathComponent("proj/a.jsonl")

    // Полдень: тогда «минус 6 часов» — те же сутки, а «минус 25 часов» — вчерашние.
    let cal = Calendar.current
    let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    let day = cal.startOfDay(for: now)

    func line(_ stamp: Date, _ out: Int, req: String, msg: String,
              session: String = "s1", model: String = "claude-opus-5[1m]") -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(iso.string(from: stamp))","sessionId":"\(session)",\
        "cwd":"/Users/x/Desktop/vibe","message":{"id":"\(msg)","model":"\(model)","usage":\
        {"input_tokens":1,"output_tokens":\(out),"cache_creation_input_tokens":10,"cache_read_input_tokens":100}}}
        """
    }

    /// Служебная запись Claude Code: модель в угловых скобках, расход нулевой.
    func synthetic(_ stamp: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"type":"assistant","requestId":"r9","timestamp":"\(iso.string(from: stamp))","sessionId":"s2",\
        "cwd":"/Users/x/Desktop/vibe","message":{"id":"m9","model":"<synthetic>","usage":\
        {"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }
    // накладные расходы записи, кроме output: input 1 + cacheWrite 10 + cacheRead 100
    let overhead = 111

    let lines = [
        line(now.addingTimeInterval(-60), 5, req: "r1", msg: "m1"),
        line(now.addingTimeInterval(-60), 5, req: "r1", msg: "m1"),             // дубль — не считается
        line(now.addingTimeInterval(-6 * 3600), 7, req: "r2", msg: "m2", model: "claude-sonnet-5"),  // вне 5ч окна, но сегодня
        line(now.addingTimeInterval(-30), 3, req: "r3", msg: "m3", session: "s2",
             model: "claude-haiku-4-5-20251001"),                              // самая свежая сессия
        line(now.addingTimeInterval(-25 * 3600), 11, req: "r4", msg: "m4"),    // вчера: не today, но в week
        line(now.addingTimeInterval(-8 * 86400), 13, req: "r5", msg: "m5"),    // вне недели, внутри истории
        synthetic(now.addingTimeInterval(-20)),                                // служебная — не ответ модели
        "{\"type\":\"user\",\"message\":{\"content\":\"hi\"}}",                 // не assistant
    ]
    try! lines.joined(separator: "\n").appending("\n").write(to: log, atomically: true, encoding: .utf8)

    let snap = UsageReader.snapshot(root: dir, now: now)

    // Дедуп, служебная запись и граница 5-часового окна.
    precondition(snap.requests == 2, "в окне должно быть 2 ответа, а не \(snap.requests)")
    precondition(snap.block.output == 8, "output в окне: \(snap.block.output)")
    precondition(snap.block.cacheRead == 200, "cacheRead в окне: \(snap.block.cacheRead)")
    precondition(snap.block.total == 8 + 2 * overhead, "block.total: \(snap.block.total)")
    // допуск: в ISO8601 пишутся только миллисекунды
    precondition(abs(snap.blockStart!.timeIntervalSince(now) + 60) < 0.01, "blockStart: \(snap.blockStart!)")

    // Границы суток и недели.
    precondition(snap.today.output == 15, "today: \(snap.today.output)")
    precondition(snap.week.output == 26, "week: \(snap.week.output)")

    // Сессия — самая свежая (s2).
    precondition(snap.session.output == 3 && snap.sessionRequests == 1, "сессия: \(snap.session.output)")
    precondition(snap.project == "vibe", "проект: \(snap.project)")

    // Укорачивание имени модели.
    precondition(snap.model == "haiku-4-5", "модель: \(snap.model)")
    precondition(UsageReader.shortModel("claude-opus-5[1m]") == "opus-5")
    precondition(UsageReader.shortModel("claude-sonnet-5") == "sonnet-5")
    precondition(UsageReader.shortModel("claude-haiku-4-5-20251001") == "haiku-4-5")

    // byDay: 7 суток по возрастанию, пустые дни — нулями.
    precondition(snap.byDay.count == 7, "byDay: \(snap.byDay.count)")
    precondition(snap.byDay.map(\.date) == snap.byDay.map(\.date).sorted(), "byDay не по возрастанию")
    precondition(snap.byDay.last?.date == day && snap.byDay.last?.tokens.output == 15, "byDay сегодня")
    precondition(snap.byDay[5].tokens.output == 11, "byDay вчера: \(snap.byDay[5].tokens.output)")
    precondition(snap.byDay[0].tokens == Tokens(), "пустой день должен быть нулевым")
    precondition(snap.byDay.reduce(0) { $0 + $1.tokens.output } == snap.week.output, "сумма byDay ≠ week")

    // byModel: за неделю, по убыванию расхода; служебных записей в списке нет.
    precondition(snap.byModel.map(\.model) == ["opus-5", "sonnet-5", "haiku-4-5"], "byModel: \(snap.byModel.map(\.model))")
    precondition(!snap.byModel.contains { $0.model.hasPrefix("<") }, "служебная модель попала в byModel")
    precondition(snap.byModel.map(\.tokens.total).reduce(0, +) == snap.week.total, "сумма byModel ≠ week")

    // blockSeries: 10 получасовок по возрастанию, в сумме равны окну.
    precondition(snap.blockSeries.count == 10, "blockSeries: \(snap.blockSeries.count)")
    precondition(snap.blockSeries.map(\.start) == snap.blockSeries.map(\.start).sorted(), "blockSeries не по возрастанию")
    precondition(snap.blockSeries.reduce(0) { $0 + $1.tokens.total } == snap.block.total, "сумма blockSeries ≠ block")
    precondition(snap.blockSeries[9].tokens.total == snap.block.total, "оба ответа — в последнем бакете")

    // Лимиты-ориентиры не могут быть меньше текущего расхода.
    precondition(snap.blockLimit >= snap.block.total && snap.blockLimit >= 1, "blockLimit: \(snap.blockLimit)")
    precondition(snap.weekLimit >= snap.week.total, "weekLimit: \(snap.weekLimit)")

    // Кеш: файл дорос — хвост дочитывается, старое не теряется и не дублируется.
    let handle = try! FileHandle(forWritingTo: log)
    handle.seekToEndOfFile()
    handle.write(Data((line(now.addingTimeInterval(-10), 100, req: "r6", msg: "m6") + "\n").utf8))
    try! handle.close()

    let grown = UsageReader.snapshot(root: dir, now: now)
    precondition(grown.requests == 3, "после дописывания: \(grown.requests) ответов")
    precondition(grown.block.output == 108, "после дописывания: \(grown.block.output)")

    try? FileManager.default.removeItem(at: dir)
    print("selftest ok")
}
