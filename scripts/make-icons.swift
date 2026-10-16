import AppKit

let destination = CommandLine.arguments[1]
let sourcePath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "assets/AppIcon.png"
let fm = FileManager.default
try fm.createDirectory(atPath: destination + "/AppIcon.iconset", withIntermediateDirectories: true)
guard let source = NSImage(contentsOfFile: sourcePath) else {
    fatalError("Cannot read selected icon: \(sourcePath)")
}

func export(_ size: Int, path: String) throws {
    // Explicit pixel dimensions avoid Retina-dependent output sizes.
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill(using: .copy)
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon PNG")
    }
    try png.write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    try export(size, path: destination + "/AppIcon.iconset/icon_\(size)x\(size).png")
    try export(size * 2, path: destination + "/AppIcon.iconset/icon_\(size)x\(size)@2x.png")
}
try export(128, path: destination + "/icon128.png")
