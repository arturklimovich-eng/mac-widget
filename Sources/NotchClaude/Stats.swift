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

struct DayUsage: Identifiable, Equatable {
    let date: Date          // начало суток
    let tokens: Tokens
    var id: Date { date }
}

struct ModelUsage: Identifiable, Equatable {
    let model: String       // короткое имя: opus-5, sonnet-5, haiku-4-5
    let tokens: Tokens
    var id: String { model }
}

struct BucketUsage: Identifiable, Equatable {
    let start: Date         // получасовой бакет внутри текущего 5-часового окна
    let tokens: Tokens
    var id: Date { start }
}

enum AlertLevel: Equatable {
    case none, warning, critical    // >= 80% лимита, >= 95%
}

/// Всё, что показывает виджет. Заполняет `UsageReader.snapshot()`.
struct Snapshot: Equatable {
    var session = Tokens()          // самая свежая сессия
    var block = Tokens()            // скользящее 5-часовое окно лимитов
    var today = Tokens()
    var week = Tokens()             // последние 7 дней

    var requests = 0                // ответов модели в текущем окне
    var sessionRequests = 0
    var lastEvent: Date?
    var model = ""                  // короткое имя последней модели
    var project = ""                // имя каталога последней сессии

    var blockStart: Date?           // время первого ответа в текущем окне
    var blockLimit = 0              // ориентир лимита: максимум расхода за 5ч в истории
    var weekLimit = 0               // ориентир лимита: максимум за 7 дней в истории

    var byDay: [DayUsage] = []      // последние 7 суток, по возрастанию даты
    var byModel: [ModelUsage] = []  // за неделю, по убыванию расхода
    var blockSeries: [BucketUsage] = []   // получасовые бакеты текущего окна, по возрастанию

    /// Claude считается активным, если лог шевелился минуту назад.
    var isActive: Bool { lastEvent.map { Date().timeIntervalSince($0) < 60 } ?? false }

    /// Когда сбросится текущее 5-часовое окно.
    var blockResetsAt: Date? { blockStart.map { $0.addingTimeInterval(5 * 3600) } }

    var blockRatio: Double { blockLimit > 0 ? Double(block.total) / Double(blockLimit) : 0 }
    var weekRatio: Double { weekLimit > 0 ? Double(week.total) / Double(weekLimit) : 0 }

    var alert: AlertLevel {
        let worst = max(blockRatio, weekRatio)
        if worst >= 0.95 { return .critical }
        if worst >= 0.8 { return .warning }
        return .none
    }
}
