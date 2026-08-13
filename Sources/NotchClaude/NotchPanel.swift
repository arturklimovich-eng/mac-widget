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

@MainActor
final class Model: ObservableObject {
    @Published var snap = Snapshot()
    @Published var expanded = false

    func refresh() {
        Task.detached {
            let snap = UsageReader.snapshot()
            await MainActor.run { self.snap = snap }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: Model
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)   // зона наведения поверх самой чёлки
            if model.expanded {
                StatsView(snap: model.snap).transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Отслеживает курсор даже когда приложение неактивно (`.activeAlways`),
/// чего SwiftUI `.onHover` в non-activating панели не делает.
final class HoverHostingView: NSHostingView<RootView> {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

@MainActor
final class NotchController {
    private let model = Model()
    private let panel: NSPanel
    private let notch: CGRect
    private var bag = Set<AnyCancellable>()
    private var ticker: Timer?

    /// Минимум: если контент выше, NSHostingView сам растянет окно.
    private let panelSize = CGSize(width: 340, height: 130)

    init() {
        let (_, notch) = Notch.geometry()
        self.notch = notch
        panel = NSPanel(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hover = HoverHostingView(rootView: RootView(model: model, notchHeight: notch.height))
        hover.onHover = { [weak self] hovering in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.15)) { self.model.expanded = hovering }
            if hovering { self.model.refresh() }
        }
        panel.contentView = hover
        panel.setFrame(collapsedFrame, display: false)
        panel.orderFrontRegardless()

        // --show: раскрыть сразу, без наведения (проверить, что панель вообще рисуется).
        if CommandLine.arguments.contains("--show") { model.expanded = true }

        model.$expanded
            .removeDuplicates()
            .sink { [weak self] in self?.setExpanded($0) }
            .store(in: &bag)
    }

    private var collapsedFrame: CGRect { notch }

    private var expandedFrame: CGRect {
        CGRect(x: notch.midX - panelSize.width / 2, y: notch.maxY - notch.height - panelSize.height,
               width: panelSize.width, height: notch.height + panelSize.height)
    }

    private func setExpanded(_ expanded: Bool) {
        panel.setFrame(expanded ? expandedFrame : collapsedFrame, display: true)
        ticker?.invalidate()
        guard expanded else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }
}
