import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let source = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let out = CommandLine.arguments[2]
let size = 1024
let s = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 1. Pastel sky, sampled from the artwork: lavender at the top, blush toward the bottom.
let sky = CGGradient(colorsSpace: space, colors: [rgb(0xD8B6FC), rgb(0xEBD3FD), rgb(0xF8E4FB)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// 2. Soft clouds, drawn on their own layer and blurred so they have no hard edges.
func cloudLayer(_ puffs: [(CGFloat, CGFloat, CGFloat)], color: CGColor, blur: Double) -> CGImage {
    let layer = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    layer.setFillColor(color)
    for (x, y, r) in puffs { layer.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
    let input = CIImage(cgImage: layer.makeImage()!)
    let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: input.extent)
    return CIContext().createCGImage(blurred, from: input.extent)!
}
func cloud(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: CGColor) {}
let backClouds = cloudLayer([(60, 830, 170), (980, 870, 190), (1010, 600, 130), (20, 560, 120)], color: rgb(0xFBEFFF, 0.7), blur: 45)
ctx.draw(backClouds, in: CGRect(x: 0, y: 0, width: s, height: s))
// 3. The bear and its hearts, cut from the artwork (top-left origin: x 0...580, y 25...800),
//    with feathered edges so it blends into the new sky.
let cropRect = CGRect(x: 0, y: 25, width: 588, height: 775)
let bear = source.cropping(to: cropRect)!
let targetHeight = s * 0.93
let scale = targetHeight / cropRect.height
let drawW = cropRect.width * scale
let drawRect = CGRect(x: (s - drawW) / 2 + 20, y: s * 0.035, width: drawW, height: targetHeight)

// Build an alpha mask that fades the crop's edges.
let maskCtx = CGContext(data: nil, width: Int(drawRect.width), height: Int(drawRect.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
maskCtx.setFillColor(gray: 1, alpha: 1)
maskCtx.fill(CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height))
let gray = CGColorSpaceCreateDeviceGray()
let fade = CGGradient(colorsSpace: gray, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray, locations: [0, 1])!
let mw = drawRect.width, mh = drawRect.height
func edge(_ rect: CGRect, from: CGPoint, to: CGPoint) {
    maskCtx.saveGState(); maskCtx.clip(to: rect)
    maskCtx.drawLinearGradient(fade, start: from, end: to, options: [])
    maskCtx.restoreGState()
}
let feather: CGFloat = 55
edge(CGRect(x: mw - feather, y: 0, width: feather, height: mh), from: CGPoint(x: mw, y: 0), to: CGPoint(x: mw - feather, y: 0))  // right
edge(CGRect(x: 0, y: 0, width: 130, height: mh), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 130, y: 0))                          // left
edge(CGRect(x: 0, y: 0, width: mw, height: 90), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 90))                          // bottom
edge(CGRect(x: 0, y: mh - 150, width: mw, height: 150), from: CGPoint(x: 0, y: mh), to: CGPoint(x: 0, y: mh - 150))              // top
let mask = maskCtx.makeImage()!

ctx.saveGState()
ctx.clip(to: drawRect, mask: mask)
ctx.interpolationQuality = .high
ctx.draw(bear, in: drawRect)
ctx.restoreGState()

// 4. Front clouds so the bear sits in them, like the original.
let frontClouds = cloudLayer([(100, 0, 190), (400, -50, 210), (740, -30, 200), (1010, 30, 190)], color: rgb(0xFFF8FE, 1), blur: 22)
ctx.draw(frontClouds, in: CGRect(x: 0, y: 0, width: s, height: s))

// Flatten onto an opaque canvas (app icons must not be transparent).
let flat = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                     space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.setFillColor(rgb(0xEBD3FD))
flat.fill(CGRect(x: 0, y: 0, width: s, height: s))
flat.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: s, height: s))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, flat.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("ok")
