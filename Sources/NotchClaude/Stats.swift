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

/// Уровень для одного показателя. В `Snapshot.alert` смешаны окно и неделя, а шкале
/// окна нужен её собственный уровень, иначе недельный алерт красит её в красный.
func level(_ ratio: Double) -> AlertLevel {
    if ratio >= 0.95 { return .critical }
    if ratio >= 0.8 { return .warning }
    return .none
}

/// Всё, что показывает виджет. Заполняет `UsageReader.snapshot()`.
struct Snapshot: Equatable {
    var session = Tokens()          // самая свежая сессия
    var block = Tokens()            // текущий 5-часовой блок лимитов
    var today = Tokens()
    var week = Tokens()             // последние 7 дней

    var requests = 0                // ответов модели в текущем блоке
    var sessionRequests = 0
    var lastEvent: Date?
    var model = ""                  // короткое имя последней модели
    var project = ""                // имя каталога последней сессии

    var blockStart: Date?           // начало текущего блока, nil — блок не идёт
    var blockLimit = 0              // ориентир: самый расходный блок в истории, 0 — ориентира нет
    var weekLimit = 0               // ориентир: максимум за 7 дней раньше текущей недели

    var byDay: [DayUsage] = []      // последние 7 суток, по возрастанию даты
    var byModel: [ModelUsage] = []  // за неделю, по убыванию расхода
    var blockSeries: [BucketUsage] = []   // получасовые бакеты текущего блока, по возрастанию

    /// Claude считается активным, если лог шевелился минуту назад.
    var isActive: Bool { lastEvent.map { Date().timeIntervalSince($0) < 60 } ?? false }

    /// Когда закончится текущий блок: ровно 5 часов от его начала.
    var blockResetsAt: Date? { blockStart.map { $0.addingTimeInterval(5 * 3600) } }

    var blockRatio: Double { blockLimit > 0 ? Double(block.total) / Double(blockLimit) : 0 }
    var weekRatio: Double { weekLimit > 0 ? Double(week.total) / Double(weekLimit) : 0 }

    var alert: AlertLevel { level(max(blockRatio, weekRatio)) }
}
