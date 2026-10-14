import CoreGraphics
import DeckhandKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the app icon from the same geometry the app draws its mark with, so the thing on the
/// home screen and the thing at the top of the rail can never drift apart. Run `just icon`.
///
/// The grid is deliberately visible: unlit cells at 0.24 of a step, lit at 0.34, which is what
/// makes the anchor read as a glyph on a dot matrix rather than as pixel art of an anchor.
///
/// `--mac` draws the Mac app's icon from the same mark. iOS masks an icon itself; macOS does not,
/// so there the rounded square and the margin around it are drawn in: Apple's grid, an 824-point
/// body on a 1024 canvas, transparent outside it.
/// ponytail: circular corners, not Apple's continuous ones; draw the squircle if the difference shows.
let mac = CommandLine.arguments.contains("--mac")
let side = 1024
let body = mac ? 824.0 : CGFloat(side)
// The grid, as a share of the icon. An app icon is masked to a squircle, so the
// shape wants more of the canvas than the same mark does on a tile inside the app.
let grid = body * 0.74
let origin = (CGFloat(side) - grid) / 2

// Copied from Palette so the executable does not need SwiftUI's Color at all.
let ground = CGColor(red: 0.188, green: 0.188, blue: 0.153, alpha: 1)
let tint = CGColor(red: 0.243, green: 0.686, blue: 0.706, alpha: 1)
let hot = CGColor(red: 0.470, green: 0.780, blue: 0.794, alpha: 1)  // tint mixed 0.3 towards white
let unlit = CGColor(red: 0.945, green: 0.941, blue: 0.918, alpha: 0.28)

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    // Opaque, not premultiplied: App Store Connect refuses an app icon that carries an alpha
    // channel at all (ITMS-90717), even one whose every pixel is already opaque. The ground
    // fill below covers the canvas, so nothing is lost -- the unlit dots still blend against
    // it, because source alpha governs the blend whether or not the destination keeps one.
    // The Mac's icon is the exception: its corners are transparent, and it never goes to App
    // Store Connect as an iOS icon does.
    bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
) else { fatalError("could not make a bitmap to draw into") }

context.setFillColor(ground)
if mac {
    let inset = (CGFloat(side) - body) / 2
    let square = CGRect(x: inset, y: inset, width: body, height: body)
    context.addPath(CGPath(roundedRect: square, cornerWidth: body * 0.225, cornerHeight: body * 0.225,
                           transform: nil))
    context.fillPath()
} else {
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
}

let space = CGColorSpaceCreateDeviceRGB()
let core = CGGradient(
    colorsSpace: space,
    colors: [hot, tint, tint] as CFArray,
    locations: [0, 0.55, 1]
)!

for index in 0..<36 {
    let lit = DotGlyph.anchor.contains(index)
    var rect = DotMatrix.rect(for: index, size: grid, lit: lit)
    // CoreGraphics counts up from the bottom; the patterns are written top-down.
    rect.origin = CGPoint(x: origin + rect.origin.x, y: CGFloat(side) - origin - rect.maxY)
    guard lit else {
        context.setFillColor(unlit)
        context.fillEllipse(in: rect)
        continue
    }
    context.saveGState()
    context.addEllipse(in: rect)
    context.clip()
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    context.drawRadialGradient(core, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: rect.width / 2, options: [])
    context.restoreGState()
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { $0 != "--mac" } ?? "icon.png")
guard let image = context.makeImage(),
      let sink = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not encode \(out.path)") }
CGImageDestinationAddImage(sink, image, nil)
guard CGImageDestinationFinalize(sink) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path)")
