import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 230, yRadius: 230)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.10, green: 0.40, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.45, green: 0.74, blue: 1, alpha: 1)
    ])
    gradient?.draw(in: shape, angle: 90)

    let ballRect = rect.insetBy(dx: 250, dy: 250)
    let ball = NSBezierPath(ovalIn: ballRect)
    NSColor.white.setFill()
    ball.fill()

    NSColor(srgbRed: 0.12, green: 0.42, blue: 0.95, alpha: 1).setStroke()
    NSColor(srgbRed: 0.12, green: 0.42, blue: 0.95, alpha: 1).setFill()
    let midX = rect.midX
    let midY = rect.midY
    let stem = NSBezierPath()
    stem.lineWidth = 54
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: midX, y: midY + 150))
    stem.line(to: NSPoint(x: midX, y: midY - 40))
    stem.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: midX - 110, y: midY + 10))
    head.line(to: NSPoint(x: midX, y: midY - 110))
    head.line(to: NSPoint(x: midX + 110, y: midY + 10))
    head.lineWidth = 54
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    NSBezierPath(roundedRect: NSRect(x: midX - 150, y: midY - 210, width: 300, height: 36), xRadius: 18, yRadius: 18).fill()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成图标\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
