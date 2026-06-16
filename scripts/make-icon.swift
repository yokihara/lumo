// Generates AppIcon.icns: a sun on an indigo squircle, drawn with CoreGraphics
// so it runs headless (no AppKit lockFocus). Run: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func drawIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Big Sur style: squircle fills ~80% of the canvas, corners ~23% of its side.
    let inset = size * 0.10
    let squircle = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = squircle.width * 0.23
    let path = CGPath(roundedRect: squircle, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.addPath(path)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.16, green: 0.18, blue: 0.38, alpha: 1),
            CGColor(red: 0.08, green: 0.09, blue: 0.20, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    // Sun: 8 rounded rays around a warm core.
    let center = CGPoint(x: size / 2, y: size / 2)
    let coreRadius = size * 0.15
    let rayInner = size * 0.235
    let rayOuter = size * 0.315
    let rayWidth = size * 0.055

    context.setFillColor(CGColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1))
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        let ray = CGRect(x: rayInner, y: -rayWidth / 2, width: rayOuter - rayInner, height: rayWidth)
        context.addPath(CGPath(roundedRect: ray, cornerWidth: rayWidth / 2, cornerHeight: rayWidth / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    let sun = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1),
            CGColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.addArc(center: center, radius: coreRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.clip()
    context.drawLinearGradient(
        sun,
        start: CGPoint(x: center.x, y: center.y + coreRadius),
        end: CGPoint(x: center.x, y: center.y - coreRadius),
        options: []
    )

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    writePNG(drawIcon(pixels: entry.pixels), to: iconset.appendingPathComponent("\(entry.name).png"))
}
print("iconset written, run: iconutil -c icns AppIcon.iconset")
