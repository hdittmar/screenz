// Reproducible vector-drawn icon; no downloaded artwork or dependencies.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: pixels * 4, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            CGColor(colorSpace: colorSpace, components: [r, g, b, 1])!
        }
        func rounded(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
            context.setFillColor(fill)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        let ink = color(0.10, 0.21, 0.17)
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.18))
        rounded(CGRect(x: 70, y: 70, width: 884, height: 884), radius: 196, fill: color(0.95, 0.96, 0.91))
        context.setShadow(offset: .zero, blur: 0, color: nil)
        rounded(CGRect(x: 131, y: 338, width: 223, height: 180), radius: 22, fill: ink)
        rounded(CGRect(x: 147, y: 354, width: 191, height: 148), radius: 9, fill: color(0.86, 0.77, 0.64))
        rounded(CGRect(x: 371, y: 338, width: 331, height: 305), radius: 25, fill: ink)
        rounded(CGRect(x: 387, y: 354, width: 299, height: 273), radius: 12, fill: color(0.71, 0.82, 0.61))
        rounded(CGRect(x: 719, y: 338, width: 174, height: 392), radius: 23, fill: ink)
        rounded(CGRect(x: 735, y: 354, width: 142, height: 360), radius: 10, fill: color(0.66, 0.78, 0.82))
        rounded(CGRect(x: 519, y: 282, width: 35, height: 64), radius: 4, fill: ink)
        rounded(CGRect(x: 465, y: 273, width: 143, height: 15), radius: 7, fill: ink)
        let suffix = scale == 2 ? "@2x" : ""
        let url = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(output) else { fatalError("Could not write icon") }
    }
}
