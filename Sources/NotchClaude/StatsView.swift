import SwiftUI

func fmt(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

struct StatsView: View {
    let snap: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(snap.isActive ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text(snap.isActive ? "Claude работает" : "Claude простаивает")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(shortModel).font(.system(size: 10)).foregroundStyle(.secondary)
            }

            row("5-часовое окно", snap.block, note: "\(snap.requests) отв.")
            row("Сегодня", snap.today, note: nil)
            row("Сессия", snap.session, note: snap.project.isEmpty ? nil : snap.project)

            HStack {
                Text(lastEventText).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Выход") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }

    private var shortModel: String {
        snap.model.replacingOccurrences(of: "claude-", with: "")
    }

    private var lastEventText: String {
        guard let last = snap.lastEvent else { return "логов за сегодня нет" }
        let ago = Int(Date().timeIntervalSince(last))
        return ago < 60 ? "активность: \(ago) с назад" : "активность: \(ago / 60) мин назад"
    }

    private func row(_ title: String, _ t: Tokens, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let note { Text(note).font(.system(size: 10)).foregroundStyle(.tertiary) }
                Text(fmt(t.total)).font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            Text("in \(fmt(t.input)) · out \(fmt(t.output)) · cache w \(fmt(t.cacheWrite)) / r \(fmt(t.cacheRead))")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
