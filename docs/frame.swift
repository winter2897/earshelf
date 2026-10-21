// Wraps raw simulator screenshots (1206x2622, iPhone 17 Pro) in an iPhone bezel for the README.
// Usage: swift docs/frame.swift <in.png> <out.png>
import AppKit

let args = CommandLine.arguments
let screen = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let sw = CGFloat(screen.width), sh = CGFloat(screen.height)

let bezel: CGFloat = 40, rim: CGFloat = 14, buttons: CGFloat = 12
let pad = bezel + rim + buttons
let W = sw + pad * 2, H = sh + (bezel + rim) * 2 + 20
let scale: CGFloat = 0.5  // output at half size to keep the repo light

let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: 10)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(h >> 16 & 0xFF) / 255, green: CGFloat(h >> 8 & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

let body = CGRect(x: buttons, y: 0, width: W - buttons * 2, height: H - 20)
let screenRadius: CGFloat = 186

// Side buttons (left: action, volume up/down; right: power), drawn behind the body.
ctx.setFillColor(rgb(0x3A3A3F))
for (y, h) in [(500.0, 110.0), (700.0, 200.0), (960.0, 200.0)] {
    ctx.addPath(rounded(CGRect(x: 0, y: H - 20 - y - h, width: buttons + 8, height: h), 6)); ctx.fillPath()
}
ctx.addPath(rounded(CGRect(x: W - buttons - 8, y: H - 20 - 760 - 300, width: buttons + 8, height: 300), 6)); ctx.fillPath()

// Titanium rim with a soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: rgb(0x000000, 0.28))
ctx.addPath(rounded(body, screenRadius + bezel + rim))
ctx.setFillColor(rgb(0x2C2C30)); ctx.fillPath()
ctx.restoreGState()
let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x6E6E75), rgb(0x2C2C30), rgb(0x55555C)] as CFArray, locations: [0, 0.5, 1])!
ctx.saveGState()
ctx.addPath(rounded(body, screenRadius + bezel + rim)); ctx.clip()
ctx.drawLinearGradient(rimGrad, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
ctx.restoreGState()

// Black glass bezel.
ctx.addPath(rounded(body.insetBy(dx: rim, dy: rim), screenRadius + bezel))
ctx.setFillColor(rgb(0x050505)); ctx.fillPath()

// Screen.
let screenRect = CGRect(x: pad, y: bezel + rim, width: sw, height: sh)
ctx.saveGState()
ctx.addPath(rounded(screenRect, screenRadius)); ctx.clip()
ctx.draw(screen, in: screenRect)
// Dynamic Island (raw simctl screenshots don't include it).
ctx.addPath(rounded(CGRect(x: screenRect.midX - 188, y: screenRect.maxY - 42 - 110, width: 376, height: 110), 55))
ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
ctx.restoreGState()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("framed", args[2])
