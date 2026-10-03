// Draws NabBar's icon: three rising usage bars on muted slate.
//
//   swift scripts/local/draw-icon.swift <output.png> [size]
//
// Colours are the Muted Slate theme's: cyan, green and yellow, one bar each
// for Codex, Claude and Command Code.
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: draw-icon.swift <output.png> [size]")
    exit(1)
}
let size = args.count >= 3 ? CGFloat(Double(args[2]) ?? 1024) : 1024
let s = size / 1024

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon grid: an 824pt rounded square centred on the 1024pt canvas.
let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
shadow.shadowBlurRadius = 28 * s
shadow.set()
NSGradient(starting: rgb(0x2C3036), ending: rgb(0x1B1E22))!.draw(in: tilePath, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// Hairline highlight along the top edge.
rgb(0xFFFFFF).withAlphaComponent(0.03).setStroke()
tilePath.lineWidth = 2 * s
tilePath.stroke()

// Track behind each bar, then the bar filled to its level.
let barWidth: CGFloat = 132 * s
let gap: CGFloat = 70 * s
let bottom: CGFloat = 262 * s
let maxHeight: CGFloat = 500 * s
let firstX = 512 * s - (3 * barWidth + 2 * gap) / 2
let bars: [(level: CGFloat, color: NSColor)] = [
    (0.62, rgb(0x86A3A1)),  // Codex — cyan
    (0.82, rgb(0x8FA68E)),  // Claude — green
    (1.00, rgb(0xBBA97F)),  // Command Code — yellow
]
for (i, bar) in bars.enumerated() {
    let x = firstX + CGFloat(i) * (barWidth + gap)
    let track = NSBezierPath(roundedRect: NSRect(x: x, y: bottom, width: barWidth, height: maxHeight),
                             xRadius: barWidth / 2, yRadius: barWidth / 2)
    rgb(0xFFFFFF).withAlphaComponent(0.07).setFill()
    track.fill()
    let fill = NSBezierPath(roundedRect: NSRect(x: x, y: bottom, width: barWidth, height: maxHeight * bar.level),
                            xRadius: barWidth / 2, yRadius: barWidth / 2)
    bar.color.setFill()
    fill.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("could not encode PNG")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: args[1]))
