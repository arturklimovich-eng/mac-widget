import AppKit
import SwiftUI

/// Рисует панель и островок в PNG без окна — единственный способ посмотреть,
/// как всё свёрстано: окна виджета лежат выше строки меню и в скриншот не попадают.
@MainActor
func renderPreviews(to dir: URL) {
    let snap = UsageReader.snapshot()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    func write(_ view: some View, _ name: String, size: CGSize) {
        let renderer = ImageRenderer(content:
            view
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return print("не удалось отрисовать \(name)") }
        try? png.write(to: dir.appendingPathComponent(name))
        print("\(name): содержимое \(Int(image.size.width))×\(Int(image.size.height))")
    }

    write(StatsView(snap: snap), "panel.png",
          size: CGSize(width: Theme.panelWidth,
                       height: snap.alert == .none ? Theme.panelHeight : Theme.panelHeightAlert))
    write(IslandView(snap: snap), "island.png",
          size: CGSize(width: Theme.islandWidth, height: Theme.islandHeight))

    // Панель с алертом — проверить, что плашка помещается в 300 pt.
    var alerted = snap
    alerted.blockLimit = max(1, Int(Double(snap.block.total) / 0.92))
    write(StatsView(snap: alerted), "panel-alert.png",
          size: CGSize(width: Theme.panelWidth, height: Theme.panelHeightAlert))
}
