// Optional original icon generator. The PNG is committed; no build-time dependency.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: alpha)
}
context.setFillColor(color(0.055, 0.075, 0.11))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(color(1, 0.39, 0.08))
context.fill(CGRect(x: 700, y: 0, width: 324, height: 1024))
for x in [150, 320, 490] {
    context.setFillColor(color(1, 1, 1, 0.08))
    context.fill(CGRect(x: x, y: 0, width: 7, height: 1024))
}
context.setStrokeColor(color(1, 1, 1))
context.setLineWidth(58)
context.strokeEllipse(in: CGRect(x: 188, y: 235, width: 566, height: 566))
context.setLineWidth(54)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 472, y: 697))
context.addLine(to: CGPoint(x: 472, y: 518))
context.addLine(to: CGPoint(x: 598, y: 430))
context.strokePath()
context.setFillColor(color(1, 1, 1))
context.addPath(CGPath(roundedRect: CGRect(x: 387, y: 843, width: 170, height: 43),
                       cornerWidth: 17, cornerHeight: 17, transform: nil))
context.fillPath()
for row in 0..<3 {
    for column in 0..<2 where (row + column) % 2 == 0 {
        context.fill(CGRect(x: 775 + column * 68, y: 390 + row * 68, width: 68, height: 68))
    }
}
let url = URL(fileURLWithPath: "SprintTimer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Could not write original app icon")
