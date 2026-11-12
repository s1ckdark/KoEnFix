import AppKit
import CoreText
import Foundation

// Current-version usage film. Silent, 1920×1080, 30fps.
// Rebuild: swift scripts/render-usage.swift
//
// Beats match the shipped aggressive-mode behavior:
//   스ㅕㅌ + Space → tmux, input source ABC
//   djeltj + Space → 어디서, input source 한글
//   work stays English; Shift+Space → 재가 and the accept list
//   the next work + Space → 재가
//   deleting that insertion at once moves work to the reject list
//   after toggling back to English, work + Space stays work

let width = 1920
let height = 1080
let fps = 30

let ink = CGColor(srgbRed: 0.106, green: 0.145, blue: 0.204, alpha: 1)
let paper = CGColor(srgbRed: 0.965, green: 0.945, blue: 0.910, alpha: 1)
let bg = CGColor(srgbRed: 0.067, green: 0.082, blue: 0.110, alpha: 1)
let bar = CGColor(srgbRed: 0.045, green: 0.055, blue: 0.075, alpha: 1)
let captionColor = CGColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1)
let muted = CGColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
let keyFace = CGColor(srgbRed: 0.93, green: 0.91, blue: 0.87, alpha: 1)
let keyDown = CGColor(srgbRed: 0.80, green: 0.78, blue: 0.74, alpha: 1)
let menuPaper = CGColor(srgbRed: 0.985, green: 0.975, blue: 0.955, alpha: 1)
let rowOn = CGColor(srgbRed: 0.835, green: 0.890, blue: 0.820, alpha: 1)

enum ListShown {
    case hidden
    case accept
    case reject
}

struct Shot {
    var text: String = ""
    var english: Bool = false
    var spaceDown: Bool = false
    var shiftDown: Bool = false
    var backspaceDown: Bool = false
    var caption: String = ""
    var chapter: Int = 0
    var list: ListShown = .hidden
    var card: Bool = true
    var title: Bool = false
}

var timeline: [Shot] = []

func hold(_ count: Int, _ shot: Shot, mark: String? = nil) {
    if let mark {
        fputs(String(format: "mark %d\t%@\n", timeline.count, mark), stderr)
    }
    for _ in 0..<count {
        timeline.append(shot)
    }
}

func buildTimeline() {
    hold(48, Shot(
        caption: "적극 모드에서 이렇게 씁니다",
        card: false,
        title: true
    ), mark: "title")

    // 1. Korean-mode command → English
    hold(16, Shot(english: false, caption: "한글 모드에서 명령어를 치면", chapter: 1), mark: "cmd")
    hold(10, Shot(text: "스", caption: "한글 모드에서 명령어를 치면", chapter: 1))
    hold(10, Shot(text: "스ㅕ", caption: "한글 모드에서 명령어를 치면", chapter: 1))
    hold(26, Shot(text: "스ㅕㅌ", caption: "한글 모드에서 명령어를 치면", chapter: 1))
    hold(12, Shot(text: "스ㅕㅌ", spaceDown: true, caption: "Space", chapter: 1))
    hold(6, Shot(text: "스ㅕ", spaceDown: true, caption: "Space", chapter: 1))
    hold(6, Shot(text: "스", spaceDown: true, caption: "Space", chapter: 1))
    hold(6, Shot(caption: "Space", chapter: 1))
    hold(6, Shot(text: "t", english: true, caption: "Space", chapter: 1))
    hold(6, Shot(text: "tm", english: true, caption: "Space", chapter: 1))
    hold(6, Shot(text: "tmu", english: true, caption: "Space", chapter: 1))
    hold(36, Shot(text: "tmux", english: true, caption: "영문으로 고치고, 입력기도 바뀝니다", chapter: 1), mark: "tmux")

    // 2. English-mode Hangul → Korean
    hold(14, Shot(english: true, caption: "영문 모드에서 한글을 쳐도", chapter: 2), mark: "hangul")
    for word in ["d", "dj", "dje", "djel", "djelt"] {
        hold(8, Shot(text: word, english: true, caption: "영문 모드에서 한글을 쳐도", chapter: 2))
    }
    hold(24, Shot(text: "djeltj", english: true, caption: "영문 모드에서 한글을 쳐도", chapter: 2))
    hold(12, Shot(text: "djeltj", english: true, spaceDown: true, caption: "Space", chapter: 2))
    hold(6, Shot(english: true, caption: "Space", chapter: 2))
    hold(8, Shot(text: "어", caption: "Space", chapter: 2))
    hold(8, Shot(text: "어디", caption: "Space", chapter: 2))
    hold(40, Shot(text: "어디서", caption: "한글로 고치고, 입력기도 바뀝니다", chapter: 2), mark: "어디서")

    // 3. Real English stays; Shift+Space teaches the accept list.
    hold(14, Shot(english: true, caption: "영어 단어는 그대로 둡니다", chapter: 3), mark: "learn")
    hold(8, Shot(text: "w", english: true, caption: "영어 단어는 그대로 둡니다", chapter: 3))
    hold(8, Shot(text: "wo", english: true, caption: "영어 단어는 그대로 둡니다", chapter: 3))
    hold(8, Shot(text: "wor", english: true, caption: "영어 단어는 그대로 둡니다", chapter: 3))
    hold(18, Shot(text: "work", english: true, caption: "영어 단어는 그대로 둡니다", chapter: 3))
    hold(12, Shot(text: "work", english: true, spaceDown: true, caption: "Space를 눌러도 그대로입니다", chapter: 3))
    hold(16, Shot(text: "work", english: true, caption: "Space를 눌러도 그대로입니다", chapter: 3))
    hold(14, Shot(
        text: "work",
        english: true,
        spaceDown: true,
        shiftDown: true,
        caption: "Shift + Space로 바꾸면",
        chapter: 3
    ))
    hold(6, Shot(english: true, caption: "Shift + Space로 바꾸면", chapter: 3))
    hold(8, Shot(text: "재", caption: "Shift + Space로 바꾸면", chapter: 3))
    hold(40, Shot(
        text: "재가",
        caption: "그 영문이 목록에 남습니다",
        chapter: 3,
        list: .accept
    ), mark: "accept")

    hold(20, Shot(
        caption: "다시 영문으로 치면",
        chapter: 4,
        list: .accept,
        card: false
    ), mark: "again")

    // 4. Learned accept converts on Space; deleting the insertion rejects it.
    hold(12, Shot(english: true, caption: "이제는 Space만으로", chapter: 4, list: .accept))
    hold(8, Shot(text: "w", english: true, caption: "이제는 Space만으로", chapter: 4, list: .accept))
    hold(8, Shot(text: "wo", english: true, caption: "이제는 Space만으로", chapter: 4, list: .accept))
    hold(8, Shot(text: "wor", english: true, caption: "이제는 Space만으로", chapter: 4, list: .accept))
    hold(14, Shot(text: "work", english: true, caption: "이제는 Space만으로", chapter: 4, list: .accept))
    hold(12, Shot(text: "work", english: true, spaceDown: true, caption: "Space", chapter: 4, list: .accept))
    hold(6, Shot(english: true, caption: "Space", chapter: 4, list: .accept))
    hold(8, Shot(text: "재", caption: "Space", chapter: 4, list: .accept))
    hold(28, Shot(text: "재가 ", caption: "한글로 바뀝니다", chapter: 4, list: .accept), mark: "learned-space")
    hold(12, Shot(text: "재가 ", caption: "방금 글을 바로 모두 지우면", chapter: 4, list: .accept))
    hold(10, Shot(text: "재가", backspaceDown: true, caption: "방금 글을 바로 모두 지우면", chapter: 4, list: .accept))
    hold(10, Shot(text: "재", backspaceDown: true, caption: "방금 글을 바로 모두 지우면", chapter: 4, list: .accept))
    hold(10, Shot(backspaceDown: true, caption: "방금 글을 바로 모두 지우면", chapter: 4, list: .reject), mark: "reject")
    hold(12, Shot(caption: "입력기를 영문으로 돌린 뒤", chapter: 4, list: .reject))
    hold(12, Shot(
        english: false,
        spaceDown: true,
        shiftDown: true,
        caption: "입력기를 영문으로 돌린 뒤",
        chapter: 4,
        list: .reject
    ))
    hold(10, Shot(english: true, caption: "한 번 더 쳐 봅니다", chapter: 4, list: .reject))
    hold(8, Shot(text: "w", english: true, caption: "한 번 더 쳐 봅니다", chapter: 4, list: .reject))
    hold(8, Shot(text: "wo", english: true, caption: "한 번 더 쳐 봅니다", chapter: 4, list: .reject))
    hold(8, Shot(text: "wor", english: true, caption: "한 번 더 쳐 봅니다", chapter: 4, list: .reject))
    hold(14, Shot(text: "work", english: true, caption: "한 번 더 쳐 봅니다", chapter: 4, list: .reject))
    hold(12, Shot(text: "work", english: true, spaceDown: true, caption: "Space", chapter: 4, list: .reject))
    hold(48, Shot(
        text: "work",
        english: true,
        caption: "다음부터는 그대로 둡니다",
        chapter: 4,
        list: .reject
    ), mark: "stays")
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

func typographicWidth(_ text: String, font: NSFont) -> CGFloat {
    let run = line(text, font: font, color: ink)
    return CGFloat(CTLineGetTypographicBounds(run, nil, nil, nil))
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

func drawChapters(_ ctx: CGContext, current: Int) {
    let names = ["명령어", "한글", "기억", "목록"]
    let labelFont = font(named: "AppleSDGothicNeo-Medium", size: 22, weight: .medium)
    let numFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold)
    for (index, name) in names.enumerated() {
        let on = current == index + 1
        let color = on ? paper : muted
        let y = CGFloat(760 - index * 48)
        let row = CGRect(x: 64, y: y, width: 220, height: 36)
        draw("\(index + 1)", font: numFont, color: color, in: ctx, rect: CGRect(x: row.minX, y: row.minY, width: 28, height: row.height), align: 0)
        draw(name, font: labelFont, color: color, in: ctx, rect: CGRect(x: row.minX + 36, y: row.minY, width: 180, height: row.height), align: 0)
    }
}

func drawKey(_ ctx: CGContext, _ rect: CGRect, title: String, down: Bool) {
    let moved = rect.offsetBy(dx: 0, dy: down ? -6 : 0)
    fillRound(ctx, moved, radius: 14, color: down ? keyDown : keyFace)
    draw(
        title,
        font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        color: ink,
        in: ctx,
        rect: moved,
        align: 0.5
    )
}

func drawKeys(_ ctx: CGContext, shot: Shot) {
    let shiftW: CGFloat = 148
    let spaceW: CGFloat = 220
    let backW: CGFloat = 188
    let gap: CGFloat = 14
    let keyH: CGFloat = 64
    let total = shiftW + spaceW + backW + gap * 2
    var x = (CGFloat(width) - total) / 2
    let y: CGFloat = 268
    drawKey(ctx, CGRect(x: x, y: y, width: shiftW, height: keyH), title: "Shift", down: shot.shiftDown)
    x += shiftW + gap
    drawKey(ctx, CGRect(x: x, y: y, width: spaceW, height: keyH), title: "Space", down: shot.spaceDown)
    x += spaceW + gap
    drawKey(ctx, CGRect(x: x, y: y, width: backW, height: keyH), title: "Backspace", down: shot.backspaceDown)
}

func drawMenu(_ ctx: CGContext, list: ListShown) {
    let menuW: CGFloat = 320
    let menuH: CGFloat = 236
    let menu = CGRect(x: CGFloat(width) - 28 - menuW, y: CGFloat(height) - 52 - 10 - menuH, width: menuW, height: menuH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: CGColor(gray: 0, alpha: 0.45))
    fillRound(ctx, menu, radius: 14, color: menuPaper)
    ctx.restoreGState()

    let titleFont = font(named: "AppleSDGothicNeo-Bold", size: 15, weight: .bold)
    let headFont = font(named: "AppleSDGothicNeo-Medium", size: 14, weight: .medium)
    let itemFont = font(named: "Menlo", size: 16, weight: .regular)
    let hangulItem = font(named: "AppleSDGothicNeo-Regular", size: 16, weight: .regular)

    var top = menu.maxY - 8
    func row(_ h: CGFloat) -> CGRect {
        top -= h
        return CGRect(x: menu.minX + 8, y: top, width: menu.width - 16, height: h)
    }

    draw("KoEnFix", font: titleFont, color: ink, in: ctx, rect: row(34).insetBy(dx: 10, dy: 0), align: 0)
    top -= 6
    ctx.setStrokeColor(CGColor(srgbRed: 0.82, green: 0.80, blue: 0.76, alpha: 1))
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: menu.minX + 14, y: top))
    ctx.addLine(to: CGPoint(x: menu.maxX - 14, y: top))
    ctx.strokePath()
    top -= 6

    draw("Space로 바꿀 영문", font: headFont, color: muted, in: ctx, rect: row(28).insetBy(dx: 10, dy: 0), align: 0)
    let acceptRow = row(34)
    if list == .accept {
        fillRound(ctx, acceptRow, radius: 8, color: rowOn)
    }
    let acceptText = list == .accept ? "work" : "(없음)"
    let acceptFont = list == .accept ? itemFont : hangulItem
    draw(acceptText, font: acceptFont, color: ink, in: ctx, rect: acceptRow.insetBy(dx: 10, dy: 0), align: 0)

    draw("그대로 둘 영문", font: headFont, color: muted, in: ctx, rect: row(28).insetBy(dx: 10, dy: 0), align: 0)
    let rejectRow = row(34)
    if list == .reject {
        fillRound(ctx, rejectRow, radius: 8, color: rowOn)
    }
    let rejectText = list == .reject ? "work" : "(없음)"
    let rejectFont = list == .reject ? itemFont : hangulItem
    draw(rejectText, font: rejectFont, color: ink, in: ctx, rect: rejectRow.insetBy(dx: 10, dy: 0), align: 0)

    top -= 6
    ctx.move(to: CGPoint(x: menu.minX + 14, y: top))
    ctx.addLine(to: CGPoint(x: menu.maxX - 14, y: top))
    ctx.strokePath()
    top -= 4
    draw("학습 목록 비우기", font: headFont, color: ink, in: ctx, rect: row(32).insetBy(dx: 10, dy: 0), align: 0)
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

func render(frame index: Int) -> CGImage {
    let ctx = makeContext()
    let shot = timeline[index]
    ctx.setFillColor(bg)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let barH: CGFloat = 52
    ctx.setFillColor(bar)
    ctx.fill(CGRect(x: 0, y: CGFloat(height) - barH, width: CGFloat(width), height: barH))
    draw(
        "KoEnFix",
        font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        color: captionColor,
        in: ctx,
        rect: CGRect(x: 22, y: CGFloat(height) - barH, width: 160, height: barH),
        align: 0
    )
    drawAppIcon(ctx, in: CGRect(x: CGFloat(width) - 64, y: CGFloat(height) - barH + 13, width: 26, height: 26))

    if shot.chapter > 0 {
        drawChapters(ctx, current: shot.chapter)
    }
    if shot.list != .hidden {
        drawMenu(ctx, list: shot.list)
    }

    if shot.title {
        let icon = CGRect(x: CGFloat(width) / 2 - 72, y: 560, width: 144, height: 144)
        drawAppIcon(ctx, in: icon)
        draw(
            "KoEnFix",
            font: NSFont.systemFont(ofSize: 64, weight: .bold),
            color: paper,
            in: ctx,
            rect: CGRect(x: 200, y: 450, width: CGFloat(width) - 400, height: 80),
            align: 0.5
        )
    } else if shot.card {
        let card = CGRect(x: 390, y: 430, width: 1140, height: 280)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 36, color: CGColor(gray: 0, alpha: 0.38))
        fillRound(ctx, card, radius: 32, color: paper)
        ctx.restoreGState()

        let pill = CGRect(x: card.minX + 48, y: card.midY - 52, width: 104, height: 104)
        let pillInk = shot.english ? paper : ink
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(3)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 26, cornerHeight: 26, transform: nil))
        ctx.setFillColor(shot.english ? ink : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.drawPath(using: .fillStroke)
        let pillFont = shot.english
            ? NSFont.systemFont(ofSize: 54, weight: .black)
            : font(named: "AppleSDGothicNeo-Heavy", size: 46, weight: .heavy)
        draw(shot.english ? "A" : "한", font: pillFont, color: pillInk, in: ctx, rect: pill.insetBy(dx: 8, dy: 8), align: 0.5)

        let typedFont = shot.english
            ? font(named: "Menlo-Bold", size: 84, weight: .bold)
            : font(named: "AppleSDGothicNeo-Bold", size: 84, weight: .bold)
        let textRect = CGRect(x: pill.maxX + 36, y: card.minY + 40, width: card.maxX - pill.maxX - 80, height: card.height - 80)
        let glyphWidth = shot.text.isEmpty
            ? 0
            : draw(shot.text, font: typedFont, color: ink, in: ctx, rect: textRect, align: 0)
        let caretWidth = shot.text.hasSuffix(" ") ? typographicWidth(shot.text, font: typedFont) : glyphWidth
        if (index / 15) % 2 == 0 {
            let caret = CGRect(x: textRect.minX + caretWidth + 22, y: card.midY - 40, width: 3, height: 80)
            ctx.setFillColor(ink)
            ctx.fill(caret)
        }
        drawKeys(ctx, shot: shot)
    } else {
        draw(
            shot.caption,
            font: font(named: "AppleSDGothicNeo-Medium", size: 48, weight: .medium),
            color: paper,
            in: ctx,
            rect: CGRect(x: 240, y: 480, width: CGFloat(width) - 480, height: 80),
            align: 0.5
        )
    }

    if shot.card || shot.title {
        draw(
            shot.caption,
            font: font(named: "AppleSDGothicNeo-Medium", size: 34, weight: .medium),
            color: captionColor,
            in: ctx,
            rect: CGRect(x: 280, y: 150, width: CGFloat(width) - 560, height: 56),
            align: 0.5
        )
    }

    guard let image = ctx.makeImage() else {
        fputs("frame \(index) failed\n", stderr)
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

buildTimeline()
fputs("frames \(timeline.count)\n", stderr)

let framesDir = URL(fileURLWithPath: "/tmp/koen-usage-frames", isDirectory: true)
if FileManager.default.fileExists(atPath: framesDir.path) {
    try FileManager.default.removeItem(at: framesDir)
}
try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

for frame in 0..<timeline.count {
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
let movie = projectDir.appendingPathComponent("Resources/koenfix-usage.mp4")
try FileManager.default.createDirectory(at: movie.deletingLastPathComponent(), withIntermediateDirectories: true)

let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
ffmpeg.arguments = [
    "-y",
    "-framerate", "\(fps)",
    "-i", framesDir.appendingPathComponent("frame_%04d.png").path,
    "-an",
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
