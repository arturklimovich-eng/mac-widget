import AppKit
import Combine
import SwiftUI

/// Геометрия чёлки. Без чёлки (внешний монитор) — полоска в центре сверху.
enum Notch {
    static func geometry() -> (screen: NSScreen, rect: CGRect) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        let height = max(screen.safeAreaInsets.top, 24)
        var width: CGFloat = 200
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
        }
        let frame = screen.frame
        return (screen, CGRect(x: frame.midX - width / 2, y: frame.maxY - height,
                               width: width, height: height))
    }
}

/// Спрятан → островок под чёлкой (наведение) → раскрытая панель (клик).
enum PanelState: Equatable {
    case hidden, island, expanded
}

@MainActor
final class Model: ObservableObject {
    @Published var snap = Snapshot()
    @Published var state = PanelState.hidden

    /// Снимки считаются строго по одному на своей очереди: кеш `UsageReader`
    /// не переживает параллельного доступа (наведение, таймер и старт лезут разом).
    private let queue = DispatchQueue(label: "dev.airshow.notchclaude.usage")
    private var refreshing = false

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        queue.async {
            let snap = UsageReader.snapshot()
            Task { @MainActor in
                self.snap = snap
                self.refreshing = false
            }
        }
    }

    /// Размер чёрного блока под чёлкой; высота панели зависит от наличия плашки алерта.
    func boxSize(for state: PanelState) -> CGSize {
        switch state {
        case .hidden:
            CGSize(width: 0, height: 0)
        case .island:
            CGSize(width: Theme.islandWidth, height: Theme.islandHeight)
        case .expanded:
            CGSize(width: Theme.panelWidth,
                   height: snap.alert == .none ? Theme.panelHeight : Theme.panelHeightAlert)
        }
    }
}

/// Содержимое островка: звёздочка, расход текущего окна, точка активности.
/// Волны при алерте рисует `Waves` — снаружи, чтобы их не срезала форма блока.
struct IslandView: View {
    let snap: Snapshot

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ClaudeMark(size: 12, color: Theme.accent(for: snap.alert))
            Text(label)
                .font(.system(size: 10, weight: snap.alert == .critical ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(snap.alert == .none ? Color.white.opacity(0.85) : Theme.accent(for: snap.alert))
            Circle()
                .fill(snap.isActive ? Theme.activeDot : Color.white.opacity(0.25))
                .frame(width: 5, height: 5)
                .opacity(snap.isActive && pulse ? 0.35 : 1)
        }
        .frame(height: Theme.islandHeight)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// Спокойно — расход, при алерте — процент того окна, которое алерт и подняло:
    /// иначе островок тревожит красным, показывая при этом мирные 10%.
    private var label: String {
        guard snap.alert != .none else { return fmt(snap.block.total) }
        let weekWorse = snap.weekRatio > snap.blockRatio
        let worst = max(snap.blockRatio, snap.weekRatio)
        guard snap.alert == .critical else { return pct(worst) }
        // Время сброса относится только к пятичасовому окну; у недели его нет.
        return "\(pct(worst)) · \(weekWorse ? "нед." : resetShort)"
    }

    /// Сколько осталось до конца текущего блока, в формате Ч:ММ.
    private var resetShort: String {
        guard let reset = snap.blockResetsAt else { return "—" }
        let left = max(0, Int(reset.timeIntervalSinceNow))
        return String(format: "%d:%02d", left / 3600, (left % 3600) / 60)
    }
}

/// Два кольца, разбегающиеся вокруг островка при алерте. Своё состояние и свой onAppear:
/// анимация обязана стартовать заново каждый раз, когда островок с алертом появляется.
private struct Waves: View {
    let alert: AlertLevel

    @State private var on = false

    var body: some View {
        ForEach(0..<2, id: \.self) { i in
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(Theme.accent(for: alert).opacity(alert == .critical ? 0.5 : 0.45),
                              lineWidth: 1.5)
                .scaleEffect(on ? 1.45 : 1)
                .opacity(on ? 0 : 0.7)
                .animation(.easeOut(duration: 1.2).delay(Double(i) * 0.3).repeatForever(autoreverses: false),
                           value: on)
        }
        .allowsHitTesting(false)
        .onAppear { on = true }
    }
}

/// Чёрный блок, приклеенный снизу к чёлке: морфится между островком и панелью,
/// содержимое перекрёстно затухает, всё лишнее обрезается по краям блока.
struct RootView: View {
    @ObservedObject var model: Model
    let notch: CGRect

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)      // зона наведения поверх самой чёлки
            box
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: UnevenRoundedRectangle {
        let radius = model.state == .expanded ? Theme.panelRadius : Theme.islandRadius
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
    }

    /// Чёрный блок морфится размером и скруглением, содержимое перекрёстно затухает.
    /// Размер задаётся тут, а не размером окна: окно при показе сразу становится
    /// максимальным, иначе анимация SwiftUI и анимация окна расходятся и всё дёргается.
    private var box: some View {
        let size = model.boxSize(for: model.state)
        return ZStack(alignment: .top) {
            IslandView(snap: model.snap)
                .opacity(model.state == .island ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: model.state)
            StatsView(snap: model.snap)
                .opacity(model.state == .expanded ? 1 : 0)
                .animation(model.state == .expanded
                           ? .easeIn(duration: 0.25).delay(0.16)
                           : .easeOut(duration: 0.1),
                           value: model.state)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.55), radius: 20, y: 18)   // как в прототипе: 0 18px 40px
        // Кольца — снаружи клипа и после тени: внутри их срезала бы форма блока,
        // а до тени они получили бы собственную. Отступ -4, как inset:-4 в прототипе.
        .background {
            if model.state == .island, model.snap.alert != .none {
                Waves(alert: model.snap.alert).padding(-4)
            }
        }
    }
}

/// Отслеживает курсор и клик даже когда приложение неактивно (`.activeAlways`):
/// SwiftUI `.onHover` в неактивной non-activating панели не срабатывает.
final class HoverHostingView: NSHostingView<RootView> {
    var onHover: ((Bool) -> Void)?
    var onMove: ((NSPoint) -> Void)?
    var onClick: (() -> Void)?
    /// Зона-переключатель в экранных координатах; клики вне неё уходят в SwiftUI (вкладки, «Выход»).
    var toggleRect: (() -> CGRect)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    /// Окно шире видимого блока (в запасе рисуется тень), поэтому наведение
    /// считаем по положению курсора, а не по границам окна.
    override func mouseMoved(with event: NSEvent) {
        onMove?(window?.convertPoint(toScreen: event.locationInWindow) ?? .zero)
    }

    override func mouseDown(with event: NSEvent) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        if toggleRect?().contains(point) ?? true {
            onClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// Безрамочная панель по умолчанию не может стать key, из-за чего SwiftUI не отдаёт
/// нажатия кнопкам. `becomesKeyOnlyIfNeeded` при этом не отбирает фокус у чужого окна.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class NotchController {
    /// Запас вокруг чёрного блока, в котором рисуется тень.
    static let shadowMargin: CGFloat = 28
    /// Снизу запаса нужно больше: тень смещена на 18 и размыта на 20. Отдельной константой,
    /// потому что горизонтальный запас идёт в ширину окна, а лишняя ширина съедает клики.
    static let bottomShadowMargin: CGFloat = 40

    private let model = Model()
    private let panel: NotchWindow
    private let notch: CGRect
    private var bag = Set<AnyCancellable>()
    private var ticker: Timer?
    private var shrink: DispatchWorkItem?

    init() {
        let (_, notch) = Notch.geometry()
        self.notch = notch
        panel = NotchWindow(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let hover = HoverHostingView(rootView: RootView(model: model, notch: notch))
        // Раскрытую панель курсор не закрывает — только повторный клик.
        // Вход в чёлку ловим по mouseEntered (спрятанное окно ровно по ней),
        // дальше положение курсора уточняет mouseMoved.
        hover.onHover = { [weak self] hovering in
            guard let self, model.state != .expanded else { return }
            set(hovering ? .island : restingState)
        }
        hover.onMove = { [weak self] point in
            guard let self, model.state != .expanded else { return }
            set(visibleRect.contains(point) ? .island : restingState)
        }
        hover.onClick = { [weak self] in
            guard let self else { return }
            set(model.state == .expanded ? .island : .expanded)
        }
        // Пока панель раскрыта, переключает только клик по самой чёлке.
        hover.toggleRect = { [weak self] in
            guard let self else { return .zero }
            return model.state == .expanded ? handleRect : visibleRect
        }
        panel.contentView = hover
        panel.setFrame(frame(for: .hidden), display: false)
        panel.orderFrontRegardless()

        if CommandLine.arguments.contains("--show") { set(.expanded) }

        model.$state
            .removeDuplicates()
            .sink { [weak self] in self?.apply($0) }
            .store(in: &bag)

        // Алерт должен быть заметен, когда панель скрыта: островок вылезает сам, а когда
        // алерт погас — уходит, иначе висит вечно (курсор давно ушёл, событий больше нет).
        // Уровень берём из события: @Published шлёт в willSet, model.snap внутри sink ещё старый.
        model.$snap
            .map(\.alert)
            .removeDuplicates()
            .sink { [weak self] alert in
                guard let self, model.state != .expanded else { return }   // раскрытую панель не трогаем
                if alert != .none {
                    set(.island)
                } else if !visibleRect.contains(NSEvent.mouseLocation) {
                    set(.hidden)
                }
            }
            .store(in: &bag)

        model.refresh()
    }

    /// Куда возвращаться, когда курсор ушёл: обычно спрятаться, при алерте — остаться островком.
    private var restingState: PanelState {
        model.snap.alert == .none ? .hidden : .island
    }

    private func set(_ state: PanelState) {
        guard model.state != state else { return }
        withAnimation(.timingCurve(0.3, 0.9, 0.4, 1, duration: 0.28)) { model.state = state }
        if state != .hidden { model.refresh() }
    }

    /// Полоса-ручка раскрытой панели: верхняя строка с шапкой, ровно там же, где был
    /// островок. Клик по самой чёлке не годится — она прозрачная, SwiftUI не считает
    /// её попаданием, и событие уходит мимо окна.
    private var handleRect: CGRect {
        let size = model.boxSize(for: .expanded)
        return CGRect(x: notch.midX - size.width / 2, y: notch.minY - Theme.islandHeight,
                      width: size.width, height: Theme.islandHeight)
    }

    /// Видимая часть виджета в экранных координатах: чёлка плюс чёрный блок под ней.
    private var visibleRect: CGRect {
        let size = model.boxSize(for: model.state)
        guard size.height > 0 else { return notch }
        return notch.union(CGRect(x: notch.midX - size.width / 2, y: notch.minY - size.height,
                                  width: size.width, height: size.height))
    }

    /// Спрятанное окно строго по чёлке, иначе оно перехватывало бы клики по строке
    /// меню; видимое — сразу максимальное, размер блока внутри анимирует SwiftUI.
    private func frame(for state: PanelState) -> CGRect {
        guard state != .hidden else { return notch }
        let width = Theme.panelWidth + 2 * Self.shadowMargin
        let height = notch.height + Theme.panelHeightAlert + Self.bottomShadowMargin
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    private func apply(_ state: PanelState) {
        shrink?.cancel()
        if state == .hidden {
            // Окно ужимается только после того, как блок схлопнулся, иначе анимацию обрежет.
            let work = DispatchWorkItem { [weak self] in
                guard let self, model.state == .hidden else { return }
                panel.setFrame(frame(for: .hidden), display: true)
            }
            shrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
        } else {
            panel.setFrame(frame(for: state), display: true)
        }

        // Видно — обновляем часто, спрятано — раз в минуту, чтобы поймать подход к лимиту.
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: state == .hidden ? 60 : 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }
}
