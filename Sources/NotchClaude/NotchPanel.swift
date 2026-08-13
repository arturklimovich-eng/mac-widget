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
/// При алерте вокруг расходятся волны, в спокойном состоянии — одна волна на появление.
struct IslandView: View {
    let snap: Snapshot

    @State private var wave = false
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
        .background(alignment: .center) { waves }
        .onAppear {
            wave = true
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var label: String {
        switch snap.alert {
        case .none: fmt(snap.block.total)
        case .warning: "\(Int(snap.blockRatio * 100))%"
        case .critical: "\(Int(snap.blockRatio * 100))% · \(resetShort)"
        }
    }

    /// Сколько осталось до сброса окна, в формате Ч:ММ.
    private var resetShort: String {
        guard let reset = snap.blockResetsAt else { return "—" }
        let left = max(0, Int(reset.timeIntervalSinceNow))
        return String(format: "%d:%02d", left / 3600, (left % 3600) / 60)
    }

    /// Два кольца по форме островка, разбегающиеся друг за другом.
    private var waves: some View {
        ForEach(0..<2, id: \.self) { i in
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(Theme.accent(for: snap.alert).opacity(snap.alert == .critical ? 0.5 : 0.45),
                              lineWidth: 1.5)
                .padding(-4)
                .scaleEffect(wave ? 1.45 : 1)
                .opacity(wave ? 0 : 0.7)
                .animation(ripple(delay: Double(i) * 0.3), value: wave)
        }
    }

    private func ripple(delay: Double) -> Animation {
        let base = Animation.easeOut(duration: 1.2).delay(delay)
        return snap.alert == .none ? base : base.repeatForever(autoreverses: false)
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
                .padding(.horizontal, model.state == .hidden ? 0 : NotchController.shadowMargin)
                .padding(.bottom, model.state == .hidden ? 0 : NotchController.shadowMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: UnevenRoundedRectangle {
        let radius = model.state == .expanded ? Theme.panelRadius : Theme.islandRadius
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
    }

    private var box: some View {
        ZStack(alignment: .top) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.55), radius: 20, y: 9)
    }
}

/// Отслеживает курсор и клик даже когда приложение неактивно (`.activeAlways`):
/// SwiftUI `.onHover` в неактивной non-activating панели не срабатывает.
final class HoverHostingView: NSHostingView<RootView> {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    /// Зона-переключатель в экранных координатах; клики вне неё уходят в SwiftUI (вкладки, «Выход»).
    var toggleRect: (() -> CGRect)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

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

    private let model = Model()
    private let panel: NotchWindow
    private let notch: CGRect
    private var bag = Set<AnyCancellable>()
    private var ticker: Timer?

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
        hover.onHover = { [weak self] hovering in
            guard let self, model.state != .expanded else { return }
            set(hovering ? .island : restingState)
        }
        hover.onClick = { [weak self] in
            guard let self else { return }
            set(model.state == .expanded ? .island : .expanded)
        }
        // Пока панель раскрыта, переключает только клик по самой чёлке.
        hover.toggleRect = { [weak self] in
            guard let self else { return .zero }
            return model.state == .expanded ? notch : panel.frame
        }
        panel.contentView = hover
        panel.setFrame(frame(for: .hidden), display: false)
        panel.orderFrontRegardless()

        if CommandLine.arguments.contains("--show") { set(.expanded) }

        model.$state
            .removeDuplicates()
            .sink { [weak self] in self?.apply($0) }
            .store(in: &bag)

        // Алерт должен быть заметен, когда панель скрыта: островок вылезает сам.
        model.$snap
            .map(\.alert)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                if model.state == .hidden { set(restingState) } else { apply(model.state) }
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

    /// Окно = чёрный блок плюс запас на тень; спрятанное окно строго по чёлке,
    /// иначе оно перехватывало бы клики по строке меню.
    private func frame(for state: PanelState) -> CGRect {
        guard state != .hidden else { return notch }
        let box = model.boxSize(for: state)
        let width = box.width + 2 * Self.shadowMargin
        let height = notch.height + box.height + Self.shadowMargin
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    private func apply(_ state: PanelState) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = state == .expanded ? 0.3 : 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.4, 1)
            panel.animator().setFrame(frame(for: state), display: true)
        }

        // Видно — обновляем часто, спрятано — раз в минуту, чтобы поймать подход к лимиту.
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: state == .hidden ? 60 : 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }
}
