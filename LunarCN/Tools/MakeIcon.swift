import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Expected an iconset output directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(srgbRed: 0.05, green: 0.12, blue: 0.32, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.48, blue: 0.88, alpha: 1))!.draw(in: background, angle: 45)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(NSColor.white.cgColor)
    context.fillEllipse(in: CGRect(x: 220, y: 210, width: 600, height: 600))
    context.setBlendMode(.clear)
    context.fillEllipse(in: CGRect(x: 390, y: 390, width: 520, height: 520))
    context.setBlendMode(.normal)
    context.endTransparencyLayer()
    context.setFillColor(NSColor(srgbRed: 0.76, green: 0.91, blue: 1, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: 745, y: 690, width: 40, height: 40))
    context.fillEllipse(in: CGRect(x: 660, y: 820, width: 22, height: 22))
    context.fillEllipse(in: CGRect(x: 840, y: 560, width: 20, height: 20))
    NSGraphicsContext.restoreGraphicsState()
    let data = image.representation(using: .png, properties: [:])!
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
    let verified = NSBitmapImageRep(data: data)!
    precondition(verified.pixelsWide == pixels && verified.pixelsHigh == pixels)
}
print("Application icon generated and dimensions verified")
