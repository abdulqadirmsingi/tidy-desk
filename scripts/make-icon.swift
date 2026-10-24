// Generates an original app icon (rounded square with a 2x2 tile motif) as an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

func render(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let body = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let clip = NSBezierPath(roundedRect: body, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.58, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.35, green: 0.30, blue: 0.90, alpha: 1)])?.draw(in: clip, angle: -60)
    let pad = s * 0.20, gap = s * 0.045
    let tile = (body.width - 2 * (pad - s * 0.06) - gap) / 2
    let x0 = body.minX + (pad - s * 0.06), y0 = body.minY + (pad - s * 0.06)
    let rects = [
        NSRect(x: x0, y: y0, width: tile, height: tile * 2 + gap),
        NSRect(x: x0 + tile + gap, y: y0 + tile + gap, width: tile, height: tile),
        NSRect(x: x0 + tile + gap, y: y0, width: tile, height: tile),
    ]
    for (index, rect) in rects.enumerated() {
        NSColor.white.withAlphaComponent(index == 0 ? 0.95 : 0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: s * 0.045, yRadius: s * 0.045).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count > 1 else { fatalError("usage: make-icon.swift <output.iconset>") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = render(size: base * scale) { try data.write(to: out.appendingPathComponent(name)) }
    }
}
