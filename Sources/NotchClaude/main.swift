import AppKit

if CommandLine.arguments.contains("--selftest") {
    selfTest()
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    let s = UsageReader.snapshot()
    print("окно 5ч: \(s.block.total) (\(s.requests) отв.), сегодня: \(s.today.total), сессия: \(s.session.total)")
    print("неделя: \(s.week.total), ориентиры: окно \(s.blockLimit) / неделя \(s.weekLimit)")
    print("заполнение: окно \(Int(s.blockRatio * 100))%, неделя \(Int(s.weekRatio * 100))%, алерт: \(s.alert)")
    print("модели: \(s.byModel.map { "\($0.model) \($0.tokens.total)" }.joined(separator: ", "))")
    print("модель: \(s.model), проект: \(s.project), активен: \(s.isActive)")
    exit(0)
}

// Отладочный рендер интерфейса в PNG: окна виджета лежат поверх строки меню,
// и обычным скриншотом их не снять.
if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
    renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // без иконки в Dock

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
