import AppKit
import CoreText
import Foundation

// Draws the KoEnFix app icon: warm paper / ink split, 한 and A.
// macOS applies the squircle mask, so the artwork is a full-bleed square.
// Rebuild with: swift scripts/render-app-icon.swift

let paper = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.902, alpha: 1)
let ink = NSColor(srgbRed: 0.106, green: 0.145, blue: 0.204, alpha: 1)

func hangulFont(size: CGFloat) -> NSFont {
    for name in ["AppleSDGothicNeo-Heavy", "AppleSDGothicNeo-ExtraBold", "AppleSDGothicNeo-Bold"] {
        if let font = NSFont(name: name, size: size) { return font }
    }
    return NSFont.systemFont(ofSize: size, weight: .heavy)
}

func latinFont(size: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: .black)
}

func glyphLine(_ text: String, font: NSFont, color: NSColor) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

func drawLine(_ line: CTLine, in ctx: CGContext, centeredIn rect: CGRect, targetHeight: CGFloat) {
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let scale = targetHeight / bounds.height
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
    ctx.textMatrix = .identity
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func makeContext(_ size: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func drawIcon(size: Int) -> CGImage {
    let ctx = makeContext(size)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let s = CGFloat(size)

    ctx.setFillColor(ink.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setFillColor(paper.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: s * 0.5, height: s))

    let hangul = glyphLine("한", font: hangulFont(size: 200), color: ink)
    let latin = glyphLine("A", font: latinFont(size: 200), color: paper)
    let glyphH = s * 0.46
    // Centers sit slightly outside the midpoint so the stem of 한 and the leg of A
    // keep a gap at the color split.
    drawLine(
        hangul,
        in: ctx,
        centeredIn: CGRect(x: s * 0.04, y: s * 0.18, width: s * 0.40, height: s * 0.64),
        targetHeight: glyphH
    )
    drawLine(
        latin,
        in: ctx,
        centeredIn: CGRect(x: s * 0.56, y: s * 0.18, width: s * 0.40, height: s * 0.64),
        targetHeight: glyphH * 1.04
    )
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("png encode failed: \(url.path)\n", stderr)
        exit(1)
    }
    do {
        try data.write(to: url)
    } catch {
        fputs("write failed: \(url.path) \(error)\n", stderr)
        exit(1)
    }
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = makeContext(size)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage() else {
        fputs("scale failed\n", stderr)
        exit(1)
    }
    return out
}

let projectDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let resources = projectDir.appendingPathComponent("Resources", isDirectory: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
let masterURL = resources.appendingPathComponent("AppIcon-1024.png")
writePNG(master, to: masterURL)

let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
if FileManager.default.fileExists(atPath: iconset.path) {
    try FileManager.default.removeItem(at: iconset)
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let slots: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (size, name) in slots {
    let image = size == 1024 ? master : scaled(master, to: size)
    writePNG(image, to: iconset.appendingPathComponent(name))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    fputs("iconutil failed: \(task.terminationStatus)\n", stderr)
    exit(task.terminationStatus)
}

try FileManager.default.removeItem(at: iconset)

fputs("latin=\(latinFont(size: 12).fontName) hangul=\(hangulFont(size: 12).fontName)\n", stderr)
fputs("wrote \(masterURL.path)\n", stderr)
fputs("wrote \(icns.path)\n", stderr)
