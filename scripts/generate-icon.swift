import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let unit = CGFloat(pixels) / 1024
        let transform = AffineTransform(scale: unit)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 208, y: 238, width: 608, height: 462), xRadius: 70, yRadius: 70).fill()
        NSColor(calibratedWhite: 0.90, alpha: 1).setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 214, y: 244, width: 596, height: 450), xRadius: 66, yRadius: 66)
        frame.lineWidth = 24
        frame.stroke()
        NSColor(calibratedWhite: 0.9, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 386, y: 633, width: 252, height: 84), xRadius: 30, yRadius: 30).fill()
        NSColor(calibratedRed: 0.58, green: 0.85, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 288, y: 325, width: 106, height: 106), xRadius: 24, yRadius: 24).fill()
        NSColor(calibratedWhite: 0.52, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 434, y: 389, width: 290, height: 22), xRadius: 11, yRadius: 11).fill()
        NSBezierPath(roundedRect: NSRect(x: 434, y: 341, width: 184, height: 22), xRadius: 11, yRadius: 11).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
