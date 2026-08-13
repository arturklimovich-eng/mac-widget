import AppKit
import SwiftUI

/// Вкладки панели. Порядок как в прототипе, начальная — «5 часов».
private enum Tab: String, CaseIterable, Identifiable {
    case session = "Сессия"
    case block = "5 часов"
    case week = "Неделя"
    case models = "Модели"

    var id: String { rawValue }
}

/// Раскрытая панель по прототипу NotchClaude (блок `panelStyle`).
/// Фон и скругление рисует NotchPanel — здесь контент прозрачный.
///
/// Бюджет высоты, 268 pt без плашки алерта (фактические метрики SwiftUI, не CSS):
/// 12 отступ сверху + 15 шапка + 9 + 13 подпись окна + 4 + 6 шкала
/// + 10 + 24 вкладки + 9 + 142 область вкладки + 8 + 13 футер + 2 снизу = 268.
/// Прототип отдаёт под область вкладки 148 pt; строки SwiftUI на 5-6 pt выше
/// браузерных, эта разница и съедает остаток. Плашка алерта добавляет 8 + 24 → 300 pt.
struct StatsView: View {
    let snap: Snapshot

    @State private var tab: Tab = .block
    @State private var pulse = false

    /// 440 минус горизонтальные отступы 16+16 — та самая ширина 408 из прототипа.
    private let inner = Theme.panelWidth - 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if snap.alert != .none { banner.padding(.top, 8) }
            windowLabel.padding(.top, 9)
            meter(snap.blockRatio, blockFill, width: inner, height: 6).padding(.top, 4)
            tabBar.padding(.top, 10)
            // Область вкладки забирает весь остаток: жёсткие 148 pt срезали футер,
            // если метрики шрифтов оказывались чуть выше расчётных. Нижний отступ
            // минимальный — в прототипе футер стоит вплотную к нижнему краю.
            content
                .frame(width: inner, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)
            footer.padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(width: Theme.panelWidth,
               height: snap.alert == .none ? Theme.panelHeight : Theme.panelHeightAlert,
               alignment: .topLeading)
        .font(.system(size: 10))
        .foregroundStyle(Theme.text)
        .onAppear { startPulse() }
        .onChange(of: snap.isActive) { _, _ in startPulse() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            ClaudeMark(size: 14, color: Theme.accent)
            Text(snap.isActive ? "Claude работает" : "Claude простаивает")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Circle()
                .fill(snap.isActive ? Theme.activeDotPanel : Theme.text(0.3))
                .frame(width: 6, height: 6)
                .opacity(snap.isActive && pulse ? 0.35 : 1)
            Spacer(minLength: 8)
            Text(snap.model.isEmpty ? "—" : snap.model)
                .font(.mono(10))
                .foregroundStyle(Theme.text(0.45))
                .lineLimit(1)
        }
        .frame(width: inner)
    }

    /// Точка активности дышит, пока Claude работает.
    private func startPulse() {
        guard snap.isActive, !pulse else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
    }

    // MARK: - Плашка алерта

    /// Показывает то окно, что ближе к ориентиру: пятичасовое или недельное.
    private var banner: some View {
        let weekWorse = snap.weekRatio > snap.blockRatio
        let worst = max(snap.blockRatio, snap.weekRatio)
        let tint = Theme.accent(for: snap.alert)
        let what = weekWorse ? "недельный расход на исходе" : "5-часовое окно на исходе"
        return Text(verbatim: "\(what): \(pct(worst)) от твоего обычного максимума")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(width: inner, alignment: .leading)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Пятичасовое окно

    private var windowLabel: some View {
        HStack(spacing: 8) {
            // fixedSize: иначе HStack отдаёт всю ширину распорке и подпись схлопывается.
            // verbatim обязателен: в локализуемом литерале со вставкой знак «%»
            // из процента ломает форматирование и строка пропадает целиком.
            Text(verbatim: snap.blockLimit > 0
                 ? "5 ч · \(pct(snap.blockRatio)) от твоего обычного максимума"
                 : "5 ч · ориентира пока нет")
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Text(resetLabel)
                .font(.mono(10))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Theme.text(0.5))
        .frame(width: inner)
    }

    /// Заполнение шкалы окна: спокойное состояние — градиент, алерт — цвет уровня.
    /// Уровень берём по самому окну, а не по snap.alert: тот может быть поднят неделей,
    /// и тогда шкала, залитая на 10%, красилась бы в критический красный.
    private var blockFill: AnyShapeStyle {
        let own = level(snap.blockRatio)
        return own == .none
            ? AnyShapeStyle(LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                          startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(Theme.accent(for: own))
    }

    // MARK: - Вкладки

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Tab.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                    } label: {
                        VStack(spacing: 0) {
                            Text(item.rawValue)
                                .font(.system(size: 11, weight: tab == item ? .semibold : .regular))
                                .foregroundStyle(tab == item ? Theme.text : Theme.text(0.45))
                                .padding(.top, 2)
                                .padding(.bottom, 5)
                            // Прозрачная полоска у неактивных: подчёркивание не должно
                            // растягивать вкладку и расталкивать соседей. Отступ одинаковый,
                            // иначе колонки разной высоты и хайрлайн отходит от подчёркивания.
                            Rectangle()
                                .fill(tab == item ? Theme.accent : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .frame(width: inner)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .session: sessionTab
        case .block: blockTab
        case .week: weekTab
        case .models: modelsTab
        }
    }

    // MARK: - Вкладка «Сессия»

    private var sessionTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline(snap.session.total, note: "\(snap.sessionRequests) отв.")
            Text(snap.project.isEmpty ? "проект неизвестен" : snap.project)
                .foregroundStyle(Theme.text(0.5))
                .lineLimit(1)
                .padding(.top, 2)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 6) {
                part("вход", snap.session.input)
                part("выход", snap.session.output)
                part("кэш · запись", snap.session.cacheWrite)
                part("кэш · чтение", snap.session.cacheRead)
            }
        }
    }

    /// Строка разбивки сессии: подпись, доля от общего расхода, значение.
    private func part(_ title: String, _ value: Int) -> some View {
        let total = snap.session.total
        return HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.text(0.5))
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)
            meter(total > 0 ? Double(value) / Double(total) : 0,
                  Theme.text(0.4), width: 180, height: 5)
            Text(fmt(value))
                .font(.mono(10))
                .foregroundStyle(Theme.text(0.8))
                .frame(width: 62, alignment: .trailing)
        }
    }

    // MARK: - Вкладка «5 часов»

    private var blockTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline(snap.block.total, note: "\(snap.requests) отв. за окно")
            if snap.block.total == 0 {
                empty("в текущем окне расхода нет").padding(.top, 8)
            } else {
                let peak = snap.blockSeries.map(\.tokens.total).max() ?? 0
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(snap.blockSeries) { bucket in
                        bar(bucket.tokens.total, peak, width: 18, maxHeight: 82)
                    }
                }
                .frame(height: 82, alignment: .bottom)
                .padding(.top, 8)
                HStack(spacing: 0) {
                    Text(hhmm(snap.blockSeries[0].start))
                    Spacer(minLength: 0)
                    Text(hhmm(snap.blockSeries[snap.blockSeries.count - 1].start))
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.text(0.45))
                .frame(width: 225)
                .padding(.top, 3)
            }
        }
    }

    // MARK: - Вкладка «Неделя»

    private var weekTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline(snap.week.total, note: snap.weekLimit > 0
                     ? "\(pct(snap.weekRatio)) от максимума за 7 дней"
                     : "ориентира пока нет")
            if snap.week.total == 0 {
                empty("за 7 дней расхода нет").padding(.top, 8)
            } else {
                let peak = snap.byDay.map(\.tokens.total).max() ?? 0
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(snap.byDay) { day in
                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            // Столбик и подпись вместе укладываются в 70 pt области.
                            bar(day.tokens.total, peak, width: 22, maxHeight: 55)
                            Text(weekday(day.date))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.text(0.45))
                        }
                    }
                }
                .frame(height: 70, alignment: .bottom)
                .padding(.top, 8)
                meter(snap.weekRatio, Theme.activeDotPanel, width: inner, height: 5)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Вкладка «Модели»

    private var modelsTab: some View {
        let top = Array(snap.byModel.prefix(5))
        let peak = top.map(\.tokens.total).max() ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            if top.isEmpty {
                empty("за 7 дней моделей нет")
            } else {
                ForEach(top) { item in
                    HStack(spacing: 10) {
                        Text(item.model)
                            .font(.mono(10))
                            .foregroundStyle(Theme.text(0.55))
                            .lineLimit(1)
                            .frame(width: 76, alignment: .trailing)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent.opacity(0.7))
                                .frame(width: peak > 0
                                       ? 240 * Double(item.tokens.total) / Double(peak) : 0,
                                       height: 12)
                            Text(fmt(item.tokens.total))
                                .font(.mono(10))
                                .foregroundStyle(Theme.text(0.6))
                        }
                        .frame(height: 12)
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Футер

    private var footer: some View {
        HStack(spacing: 8) {
            Text(lastEventLabel)
                .font(.mono(10))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Выход") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.text(0.4))
        .frame(width: inner)
    }

    // MARK: - Мелкие блоки

    /// Пусто на вкладке — это про её период. «Логов нет» говорим, только когда логов
    /// действительно нет: иначе вкладка «Сессия» рядом показывает расход и противоречит.
    private func empty(_ text: String) -> some View {
        Text(snap.lastEvent == nil ? "логов Claude Code пока нет" : text)
            .foregroundStyle(Theme.text(0.45))
    }

    /// Крупное число вкладки и подпись рядом с ним.
    private func headline(_ n: Int, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(fmt(n)).font(.mono(24, .semibold))
            Text(note).foregroundStyle(Theme.text(0.5)).lineLimit(1)
        }
    }

    private func meter<S: ShapeStyle>(_ ratio: Double, _ fill: S,
                                     width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.track)
            RoundedRectangle(cornerRadius: 3).fill(fill)
                .frame(width: max(0, min(1, ratio)) * w)
        }
        .frame(width: w, height: h)
    }

    /// Столбик графика: максимум в наборе — насыщенный акцент, остальные приглушены.
    private func bar(_ value: Int, _ peak: Int, width: CGFloat, maxHeight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(peak > 0 && value == peak ? Theme.accent : Theme.accent.opacity(0.55))
            .frame(width: width,
                   height: peak > 0 ? maxHeight * Double(value) / Double(peak) : 0)
    }

    // MARK: - Тексты

    private var resetLabel: String {
        guard let at = snap.blockResetsAt else { return "окно пустое" }
        let left = max(0, Int(at.timeIntervalSinceNow))
        return String(format: "до сброса %d:%02d", left / 3600, (left % 3600) / 60)
    }

    private var lastEventLabel: String {
        guard let last = snap.lastEvent else { return "активности нет" }
        let ago = max(0, Int(Date().timeIntervalSince(last)))
        return ago < 60 ? "активность: \(ago) с назад" : "активность: \(ago / 60) мин назад"
    }

    /// Часы без ведущего нуля, как в прототипе: 9:00 · 13:30.
    private func hhmm(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func weekday(_ date: Date) -> String {
        let names = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        return names[(Calendar.current.component(.weekday, from: date) - 1) % 7]
    }
}
