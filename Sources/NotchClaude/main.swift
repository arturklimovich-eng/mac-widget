import AppKit

if CommandLine.arguments.contains("--selftest") {
    selfTest()
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    let s = UsageReader.snapshot()
    print("окно 5ч: \(s.block.total) (\(s.requests) отв.), сегодня: \(s.today.total), сессия: \(s.session.total)")
    print("модель: \(s.model), проект: \(s.project), активен: \(s.isActive)")
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
