#!/usr/bin/env swift
// Generates KnowingYou/Resources/Assets.xcassets/AppIcon.appiconset from code,
// using the same geometry as `KYMark` (KnowingYou/UI/DesignSystem/Brand.swift):
// five waveform bars + a forked tail on the brand-gradient squircle.
//
//   swift scripts/make-app-icon.swift
//
// Follows the macOS icon grid: an 824pt squircle centered on a 1024pt canvas,
// with a soft drop shadow, so it sits correctly next to other Dock icons.

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "KnowingYou/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Superellipse ("continuous corner") squircle, like Apple's icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// The mark's glyph (bars + tail) fitted into `box`. Shared proportions with
/// `KYMark`: bar width 10%, gap 7.5%, tail 16% × 34% of the glyph box.
func drawGlyph(in ctx: CGContext, box: CGRect, ink: CGColor) {
    let w = box.width, h = box.height
    let barWidth = w * 0.1, gap = w * 0.075, tailWidth = w * 0.16
    let heights: [CGFloat] = [0.18, 0.58, 0.94, 0.64, 0.32]
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count) * gap + tailWidth
    var x = box.midX - total / 2
    ctx.setFillColor(ink)
    for fraction in heights {
        let barHeight = h * fraction
        let bar = CGRect(x: x, y: box.midY - barHeight / 2, width: barWidth, height: barHeight)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }
    let tailHeight = h * 0.34
    let tail = CGRect(x: x, y: box.midY - tailHeight / 2, width: tailWidth, height: tailHeight)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: tail.minX, y: tail.midY))
    path.addLine(to: CGPoint(x: tail.maxX, y: tail.maxY))
    path.addQuadCurve(to: CGPoint(x: tail.maxX, y: tail.minY), control: CGPoint(x: tail.maxX - tail.width * 0.35, y: tail.midY))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
}

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: tile)

    // Drop shadow (macOS icon grid: soft, slightly below).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1B8FA8))
    ctx.fillPath()
    ctx.restoreGState()

    // Brand gradient, top-left → bottom-right.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x3DDBD9), color(0x1B8FA8), color(0x213A6B)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Soft top highlight for depth.
    let highlight = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.midY), options: [])

    // Glyph: 66% of the tile, like KYMark.
    let glyphSide = tile.width * 0.66
    let glyphBox = CGRect(x: tile.midX - glyphSide / 2, y: tile.midY - glyphSide / 2, width: glyphSide, height: glyphSide)
    drawGlyph(in: ctx, box: glyphBox, ink: color(0x062B2B))
    ctx.restoreGState()

    // Hairline inner edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()

    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try renderIcon(pixels: points * scale).write(to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
let catalogContents = outDir.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalogContents.path) {
    try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalogContents, atomically: true, encoding: .utf8)
}
print("wrote \(sizes.count) icons to \(outDir.path)")
