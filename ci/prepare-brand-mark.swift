import Foundation
import CoreGraphics
import ImageIO

// This is the former TransparentBrandMark pixel conversion, unchanged. Run at
// project generation time so neither first launch nor SwiftUI layout pays for it.
// Keep the original SplashMark untouched (including the F and green dot).
let sourceURL = URL(fileURLWithPath: "BARQ/Resources/Assets.xcassets/SplashMark.imageset/SplashMark.png")
let outputURL = URL(fileURLWithPath: "BARQ/Resources/PreparedBrandMark.rgba")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read the original SplashMark resource")
}
let width = cg.width, height = cg.height
precondition(width == 1024 && height == 1024, "Update the resource contract if the original dimensions change")
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: &pixels, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot prepare the original logo pixels")
}
context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
for i in stride(from: 0, to: pixels.count, by: 4) {
    let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
    let green = g > r * 1.5 && g > b
    let coverage = min(1, max(0, green ? (g - 11) / (196 - 11) : (r - 8) / (255 - 8)))
    pixels[i] = UInt8(min(255, max(0, r - 8 * (1 - coverage))))
    pixels[i + 1] = UInt8(min(255, max(0, g - 11 * (1 - coverage))))
    pixels[i + 2] = UInt8(min(255, max(0, b - 18 * (1 - coverage))))
    pixels[i + 3] = UInt8((coverage * 255).rounded())
}
try Data(pixels).write(to: outputURL, options: .atomic)
print("Prepared original logo RGBA resource (\(width)x\(height))")
