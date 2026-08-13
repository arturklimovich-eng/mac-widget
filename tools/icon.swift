// Рисует иконку приложения (знак Claude на тёмном квадрате) во .iconset.
// Вызывается из bundle.sh: mkicon <каталог.iconset>
import AppKit

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let r = CGFloat(px)
    let inset = r * 0.06
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: r - 2 * inset, height: r - 2 * inset),
                 xRadius: r * 0.22, yRadius: r * 0.22).fill()

    NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()
    for i in 0..<8 {
        let h = r * (i.isMultiple(of: 2) ? 0.52 : 0.36)
        let w = r * 0.075
        let spoke = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h),
                                 xRadius: w / 2, yRadius: w / 2)
        var t = AffineTransform(translationByX: r / 2, byY: r / 2)
        t.rotate(byDegrees: Double(i) * 45)
        spoke.transform(using: t)
        spoke.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(px: base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(px: base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
