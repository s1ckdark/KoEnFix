import AppKit
import CoreText
import Foundation

// 5-second usage demo: Korean-mode "tmux" (스ㅕㅌ) is corrected on Space.
// Rebuild: swift scripts/render-demo.swift

let width = 1920
let height = 1080
let fps = 30
let frameCount = fps * 5

let ink = CGColor(srgbRed: 0.106, green: 0.145, blue: 0.204, alpha: 1)
let paper = CGColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1)
let bg = CGColor(srgbRed: 0.067, green: 0.082, blue: 0.110, alpha: 1)
let bar = CGColor(srgbRed: 0.045, green: 0.055, blue: 0.075, alpha: 1)
let captionColor = CGColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1)
let keyFace = CGColor(srgbRed: 0.93, green: 0.91, blue: 0.87, alpha: 1)
let keyDown = CGColor(srgbRed: 0.80, green: 0.78, blue: 0.74, alpha: 1)

struct Scene {
    let text: String
    let english: Bool
    let spaceDown: Bool
    let caption: String
}

func scene(at frame: Int) -> Scene {
    let waiting = "한글 모드에서 명령어를 치면"
    let pressing = "Space"
    let done = "영문으로 고치고, 입력기도 바꿔 줍니다"
    switch frame {
    case ..<12:
        return Scene(text: "", english: false, spaceDown: false, caption: waiting)
    case ..<24:
        return Scene(text: "스", english: false, spaceDown: false, caption: waiting)
    case ..<36:
        return Scene(text: "스ㅕ", english: false, spaceDown: false, caption: waiting)
    case ..<66:
        return Scene(text: "스ㅕㅌ", english: false, spaceDown: false, caption: waiting)
    case ..<74:
        return Scene(text: "스ㅕㅌ", english: false, spaceDown: true, caption: pressing)
    case ..<80:
        return Scene(text: "스ㅕ", english: false, spaceDown: true, caption: pressing)
    case ..<86:
        return Scene(text: "스", english: false, spaceDown: true, caption: pressing)
    case ..<92:
        return Scene(text: "", english: false, spaceDown: false, caption: pressing)
    case ..<98:
        return Scene(text: "t", english: true, spaceDown: false, caption: pressing)
    case ..<104:
        return Scene(text: "tm", english: true, spaceDown: false, caption: pressing)
    case ..<110:
        return Scene(text: "tmu", english: true, spaceDown: false, caption: pressing)
    default:
        return Scene(text: "tmux", english: true, spaceDown: false, caption: done)
    }
}

func font(named name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func line(_ text: String, font: NSFont, color: CGColor) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? NSColor.white
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

@discardableResult
func draw(_ text: String, font: NSFont, color: CGColor, in ctx: CGContext, rect: CGRect, align: CGFloat) -> CGFloat {
    let run = line(text, font: font, color: color)
    let bounds = CTLineGetBoundsWithOptions(run, .useGlyphPathBounds)
    let x = rect.minX + (rect.width - bounds.width) * align - bounds.origin.x
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: x, y: rect.midY - bounds.midY)
    CTLineDraw(run, ctx)
    ctx.restoreGState()
    return bounds.width
}

func fillRound(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

func drawAppIcon(_ ctx: CGContext, in rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.width * 0.2237, transform: nil))
    ctx.clip()
    ctx.setFillColor(ink)
    ctx.fill(rect)
    ctx.setFillColor(paper)
    ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height))
    let hangul = font(named: "AppleSDGothicNeo-Heavy", size: rect.height * 0.62, weight: .heavy)
    let latin = NSFont.systemFont(ofSize: rect.height * 0.66, weight: .black)
    let left = CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
    let right = CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
    draw("한", font: hangul, color: ink, in: ctx, rect: left, align: 0.5)
    draw("A", font: latin, color: paper, in: ctx, rect: right, align: 0.5)
    ctx.restoreGState()
}

func makeContext() -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func render(frame: Int) -> CGImage {
    let ctx = makeContext()
    let scene = scene(at: frame)
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let barH: CGFloat = 52
    ctx.setFillColor(bar)
    ctx.fill(CGRect(x: 0, y: CGFloat(height) - barH, width: CGFloat(width), height: barH))
    let icon = CGRect(x: CGFloat(width) - 64, y: CGFloat(height) - barH + 13, width: 26, height: 26)
    drawAppIcon(ctx, in: icon)

    let card = CGRect(x: 390, y: 430, width: 1140, height: 280)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 36, color: CGColor(gray: 0, alpha: 0.38))
    fillRound(ctx, card, radius: 32, color: paper)
    ctx.restoreGState()

    let pill = CGRect(x: card.minX + 48, y: card.midY - 52, width: 104, height: 104)
    let pillFill = scene.english ? ink : paper
    let pillInk = scene.english ? paper : ink
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(scene.english ? ink : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.drawPath(using: .fillStroke)
    _ = pillFill
    let pillFont = scene.english
        ? NSFont.systemFont(ofSize: 54, weight: .black)
        : font(named: "AppleSDGothicNeo-Heavy", size: 46, weight: .heavy)
    draw(scene.english ? "A" : "한", font: pillFont, color: pillInk, in: ctx, rect: pill.insetBy(dx: 8, dy: 8), align: 0.5)

    let typedFont = scene.english
        ? font(named: "Menlo-Bold", size: 84, weight: .bold)
        : font(named: "AppleSDGothicNeo-Bold", size: 84, weight: .bold)
    let textRect = CGRect(x: pill.maxX + 36, y: card.minY + 40, width: card.maxX - pill.maxX - 80, height: card.height - 80)
    let textWidth = scene.text.isEmpty
        ? 0
        : draw(scene.text, font: typedFont, color: ink, in: ctx, rect: textRect, align: 0)
    let blink = (frame / 15) % 2 == 0
    if blink {
        let caret = CGRect(x: textRect.minX + textWidth + 22, y: card.midY - 40, width: 3, height: 80)
        ctx.setFillColor(ink)
        ctx.fill(caret)
    }

    let keyW: CGFloat = 220
    let keyH: CGFloat = 64
    let keyY: CGFloat = scene.spaceDown ? 292 : 298
    let key = CGRect(x: (CGFloat(width) - keyW) / 2, y: keyY, width: keyW, height: keyH)
    fillRound(ctx, key, radius: 14, color: scene.spaceDown ? keyDown : keyFace)
    draw(
        "Space",
        font: NSFont.systemFont(ofSize: 26, weight: .semibold),
        color: ink,
        in: ctx,
        rect: key,
        align: 0.5
    )

    let captionRect = CGRect(x: 200, y: 150, width: CGFloat(width) - 400, height: 56)
    draw(
        scene.caption,
        font: font(named: "AppleSDGothicNeo-Medium", size: 34, weight: .medium),
        color: captionColor,
        in: ctx,
        rect: captionRect,
        align: 0.5
    )

    guard let image = ctx.makeImage() else {
        fputs("frame \(frame) failed\n", stderr)
        exit(1)
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("png failed\n", stderr)
        exit(1)
    }
    try! data.write(to: url)
}

let framesDir = URL(fileURLWithPath: "/tmp/koen-demo-frames", isDirectory: true)
if FileManager.default.fileExists(atPath: framesDir.path) {
    try FileManager.default.removeItem(at: framesDir)
}
try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

for frame in 0..<frameCount {
    let image = render(frame: frame)
    let name = String(format: "frame_%04d.png", frame + 1)
    writePNG(image, to: framesDir.appendingPathComponent(name))
    if frame % 30 == 0 {
        fputs("frame \(frame)\n", stderr)
    }
}

let projectDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let movie = projectDir.appendingPathComponent("Resources/koenfix-demo.mp4")
try FileManager.default.createDirectory(at: movie.deletingLastPathComponent(), withIntermediateDirectories: true)

let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
ffmpeg.arguments = [
    "-y",
    "-framerate", "\(fps)",
    "-i", framesDir.appendingPathComponent("frame_%04d.png").path,
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-crf", "18",
    "-movflags", "+faststart",
    movie.path
]
try ffmpeg.run()
ffmpeg.waitUntilExit()
if ffmpeg.terminationStatus != 0 {
    fputs("ffmpeg failed\n", stderr)
    exit(ffmpeg.terminationStatus)
}
try FileManager.default.removeItem(at: framesDir)
fputs("wrote \(movie.path)\n", stderr)
