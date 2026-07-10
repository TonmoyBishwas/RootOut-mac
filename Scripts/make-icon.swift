// Renders the RootOut app icon: a dark glass tile with the removal glyph.
// Usage: swift Scripts/make-icon.swift <output-1024.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let canvas: CGFloat = 1024

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Tile: Apple-style rounded square with margin for the system shadow.
let tile = NSRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 100, dy: 100)
let radius: CGFloat = tile.width * 0.225
let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

NSGradient(colors: [
    NSColor(calibratedWhite: 0.20, alpha: 1),
    NSColor(calibratedWhite: 0.05, alpha: 1),
])!.draw(in: path, angle: -70)

// Glass edge highlight.
NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
path.lineWidth = 8
path.stroke()

// Glyph: the app's one action — lifting something out, into the trash.
let config = NSImage.SymbolConfiguration(pointSize: 380, weight: .regular)
if let symbol = NSImage(systemSymbolName: "arrow.up.trash", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let glyphSize = NSSize(width: tinted.size.width * 1.35, height: tinted.size.height * 1.35)
    let origin = NSPoint(x: (canvas - glyphSize.width) / 2, y: (canvas - glyphSize.height) / 2)
    tinted.draw(in: NSRect(origin: origin, size: glyphSize),
                from: .zero, operation: .sourceOver, fraction: 0.96)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
