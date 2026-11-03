// Optional asset generator. The generated PNG is committed; Xcode needs no script.
import AppKit
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                          bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 3, bitsPerPixel: 24)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let dark = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.11, alpha: 1)
dark.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let orange = NSColor(calibratedRed: 1, green: 0.39, blue: 0.08, alpha: 1)
orange.setFill()
NSBezierPath(rect: NSRect(x: 700, y: 0, width: 324, height: 1024)).fill()
for x in [150, 320, 490] {
 NSColor.white.withAlphaComponent(0.08).setFill()
 NSBezierPath(rect: NSRect(x: x, y: 0, width: 7, height: 1024)).fill()
}
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 188, y: 235, width: 566, height: 566))
ring.lineWidth = 58
ring.stroke()
let hands = NSBezierPath()
hands.move(to: NSPoint(x: 472, y: 697))
hands.line(to: NSPoint(x: 472, y: 518))
hands.line(to: NSPoint(x: 598, y: 430))
hands.lineWidth = 54
hands.lineCapStyle = .round
hands.lineJoinStyle = .round
hands.stroke()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 387, y: 843, width: 170, height: 43), xRadius: 17, yRadius: 17).fill()
for row in 0..<3 {
 for col in 0..<2 where (row + col) % 2 == 0 {
  NSColor.white.setFill()
  NSBezierPath(rect: NSRect(x: 775 + col * 68, y: 390 + row * 68, width: 68, height: 68)).fill()
 }
}
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "SprintTimer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
