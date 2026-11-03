// Round 3: icons that say what Simplify is — the calendar's day and the diary on one sheet — in the
// v5 ledger's own parts: the 1.75 spine, the 3pt ink "today" bar under a week rule, tabular day numerals,
// the Gowun Batang big date, the drawn check box and the pencil memo mark.
// Usage: swift render2.swift <out-dir> <path-to-GowunBatang-Bold.ttf>
import AppKit
import CoreGraphics
import CoreText

struct Ink {
    let paper, ink, soft, faint, wall, raised, tint, mark: CGColor
    static let light = Ink(paper: rgb(0xFBFAF7), ink: rgb(0x1A1A1A), soft: rgb(0x575755), faint: rgb(0xCFCEC9), wall: rgb(0xF4F4F2),
                           raised: rgb(0xEAE8E2), tint: rgb(0xDCE6F8), mark: rgb(0x2A5FC4))
    static let dark = Ink(paper: rgb(0x2A2927), ink: rgb(0xECEBE6), soft: rgb(0xBAB8B1), faint: rgb(0x4A4844), wall: rgb(0x1F1E1C),
                          raised: rgb(0x33312E), tint: rgb(0x3B4458), mark: rgb(0x8AB0F7))
    var isDark: Bool { paper == Ink.dark.paper }
}
func rgb(_ v: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}

enum Concept: String, CaseIterable { case i3 = "I3", i4 = "I4", i5 = "I5" }

func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5, steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1), y = pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        let pt = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath(); return p
}

var gowun: CTFont?
func numeralFont(_ size: CGFloat, serif: Bool) -> CTFont {
    if serif, let g = gowun { return CTFontCreateCopyWithAttributes(g, size, nil, nil) }
    // SF Pro, semibold, tabular figures: the ledger's date numerals.
    let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    return base as CTFont
}

func drawIcon(_ c: CGContext, concept: Concept, size s: CGFloat, ink: Ink, framed: Bool = true) {
    let inset = framed ? s * 100 / 1024 : 0
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = framed ? squircle(body) : CGPath(rect: body, transform: nil)
    c.saveGState()
    if framed { c.setShadow(offset: CGSize(width: 0, height: -max(1, s * 6 / 1024)), blur: s * 14 / 1024, color: rgb(0, ink.isDark ? 0.45 : 0.16)) }
    c.addPath(shape); c.setFillColor(ink.paper); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(shape); c.clip()

    let u = body.width / 824
    let devicePx = 1024 / s * u
    func lw(_ w: CGFloat) -> CGFloat { max(w * u, devicePx * 0.9) }
    let detail: Int = s >= 96 ? 2 : (s >= 40 ? 1 : 0)
    c.translateBy(x: body.minX, y: body.maxY); c.scaleBy(x: 1, y: -1)
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }
    func fill(_ r: CGRect, _ col: CGColor) { c.setFillColor(col); c.fill(r) }
    func hline(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ w: CGFloat, _ col: CGColor) { fill(CGRect(x: x0 * u, y: y * u - lw(w) / 2, width: (x1 - x0) * u, height: lw(w)), col) }
    func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ w: CGFloat, _ col: CGColor) { fill(CGRect(x: x * u - lw(w) / 2, y: y0 * u, width: lw(w), height: (y1 - y0) * u), col) }
    /// Text with its baseline at (x, y) in grid units; the context is flipped, so flip back locally.
    func text(_ str: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ col: CGColor, serif: Bool, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: numeralFont(size * u, serif: serif), .foregroundColor: NSColor(cgColor: col)!, .kern: kern * u]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: attrs))
        c.saveGState(); c.translateBy(x: x * u, y: y * u); c.scaleBy(x: 1, y: -1)
        c.textPosition = .zero; CTLineDraw(line, c); c.restoreGState()
    }
    /// The drawn check box: square outline, or ink-filled with a heavy check when done.
    func checkbox(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat, done: Bool, line: CGFloat) {
        let r = R(x, y, side, side)
        if done {
            fill(r, ink.ink)
            c.setStrokeColor(ink.paper); c.setLineWidth(lw(line * 1.3)); c.setLineCap(.square); c.setLineJoin(.miter)
            c.move(to: CGPoint(x: (x + side * 0.22) * u, y: (y + side * 0.52) * u))
            c.addLine(to: CGPoint(x: (x + side * 0.42) * u, y: (y + side * 0.72) * u))
            c.addLine(to: CGPoint(x: (x + side * 0.78) * u, y: (y + side * 0.30) * u)); c.strokePath()
        } else {
            c.setStrokeColor(ink.ink); c.setLineWidth(lw(line)); c.stroke(r.insetBy(dx: lw(line) / 2, dy: lw(line) / 2))
        }
    }
    /// The memo pencil, as the app draws it: a slanted line-art pencil.
    func pencil(_ cx: CGFloat, _ cy: CGFloat, _ len: CGFloat, _ line: CGFloat, _ col: CGColor) {
        c.saveGState(); c.translateBy(x: cx * u, y: cy * u); c.rotate(by: -.pi / 4)
        let w = len * 0.26 * u, l = len * u
        c.setStrokeColor(col); c.setLineWidth(lw(line)); c.setLineJoin(.miter)
        c.move(to: CGPoint(x: -l / 2, y: -w / 2)); c.addLine(to: CGPoint(x: l / 2 - w, y: -w / 2)); c.addLine(to: CGPoint(x: l / 2, y: 0))
        c.addLine(to: CGPoint(x: l / 2 - w, y: w / 2)); c.addLine(to: CGPoint(x: -l / 2, y: w / 2)); c.closePath(); c.strokePath()
        c.move(to: CGPoint(x: -l / 2 + w * 0.9, y: -w / 2)); c.addLine(to: CGPoint(x: -l / 2 + w * 0.9, y: w / 2)); c.strokePath()
        c.restoreGState()
    }

    // The left page: a month in the ledger's own rules. Weekday rule at spine weight, week rules
    // in ink, the 3pt "today" bar under a week rule in one day's column, and (I2, I3) the weekend
    // columns on the raised face. Rules stop just short of the pencil: the pencil is the spine.
    let gx0: CGFloat = 96, gx1: CGFloat = 536, cols: CGFloat = 7
    let cw = (gx1 - gx0) / cols
    let head: CGFloat = concept == .i3 ? 236 : 196
    let weeks = detail == 0 ? 2 : 5
    let rh = (732 - head) / CGFloat(weeks)
    if detail >= 1 {
        fill(R(gx0, head, cw, 732 - head), ink.raised)
        fill(R(gx1 - cw, head, cw, 732 - head), ink.raised)
    }
    if concept == .i3 { fill(R(gx0, 112, 190, detail == 0 ? 60 : 40), ink.ink) }      // the month's title, as weight
    if concept != .i3 && detail >= 1 {
        // the weekday row: seven short marks over the weekday rule, Sunday in the holiday red (I4)
        for k in 0..<7 {
            let col = (k == 0 && concept == .i4) ? (ink.isDark ? rgb(0xFF8A7A) : rgb(0xB3332A)) : ink.ink
            fill(R(gx0 + cw * CGFloat(k) + cw * 0.28, head - (detail == 2 ? 52 : 64), cw * 0.44, detail == 2 ? 20 : 30), col)
        }
    }
    hline(gx0, gx1, head, detail == 0 ? 30 : (detail == 1 ? 20 : 14), ink.ink)       // weekday rule, spine weight
    for k in 1...weeks {
        let y = head + rh * CGFloat(k)
        hline(gx0, gx1, y, detail == 0 ? 18 : (detail == 1 ? 9 : 4.5), detail == 2 ? ink.ink : ink.soft)
    }
    // today: second week, Wednesday
    let tw = detail == 0 ? 1 : 2, tc: CGFloat = detail == 0 ? 2 : 3
    let ty = head + rh * CGFloat(tw - 1)
    fill(R(gx0 + cw * tc + (detail == 0 ? -40 : 0), ty + (detail == 0 ? 12 : 0), detail == 0 ? cw + 80 : cw, detail == 0 ? 64 : rh * 0.34), ink.ink)
    // the pencil, upright, as the spine
    let px: CGFloat = 640, w: CGFloat = detail == 0 ? 136 : 108, top: CGFloat = 92, tipY: CGFloat = 740
    let shaft = tipY - w * 1.1
    c.setFillColor(ink.ink); c.fill(R(px - w / 2, top, w, shaft - top))
    if detail >= 1 { c.setFillColor(ink.paper); c.fill(R(px - w / 2 + 16, top + 64, detail == 2 ? 9 : 14, shaft - top - 84)) }
    c.setFillColor(ink.ink)
    c.move(to: CGPoint(x: (px - w / 2) * u, y: shaft * u)); c.addLine(to: CGPoint(x: (px + w / 2) * u, y: shaft * u)); c.addLine(to: CGPoint(x: px * u, y: tipY * u)); c.closePath(); c.fillPath()
    if detail >= 1 { c.setFillColor(ink.paper); c.fill(R(px - w / 2, top + 34, w, detail == 2 ? 8 : 14)) }
    c.restoreGState()
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ c: CGContext, _ url: URL) {
    try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}
func label(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: CGColor, weight: NSFont.Weight = .regular) {
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor(cgColor: color)!])
    c.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(a), c)
}
func stamp(_ sheet: CGContext, _ concept: Concept, _ px: Int, _ ink: Ink, at p: CGPoint, shown: CGFloat? = nil) {
    let ctx = makeContext(px, px)
    drawIcon(ctx, concept: concept, size: CGFloat(px), ink: ink)
    let w = shown ?? CGFloat(px)
    sheet.draw(ctx.makeImage()!, in: CGRect(x: p.x, y: p.y, width: w, height: w))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var fontErr: Unmanaged<CFError>?
let fontURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
if let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor], let d = descs.first {
    gowun = CTFontCreateWithFontDescriptor(d, 100, nil)
} else { print("Gowun Batang not loaded", fontErr as Any) }

for concept in Concept.allCases {
    for (name, ink) in [("light", Ink.light), ("dark", Ink.dark)] {
        let c = makeContext(1024, 1024); drawIcon(c, concept: concept, size: 1024, ink: ink); save(c, out.appendingPathComponent("icon-\(concept.rawValue)-\(name)-1024.png"))
        let b = makeContext(1024, 1024); drawIcon(b, concept: concept, size: 1024, ink: ink, framed: false); save(b, out.appendingPathComponent("icon-\(concept.rawValue)-\(name)-fullbleed.png"))
    }
}

let W = 2200, rowH = 720, H = 140 + rowH * 3 + 40
let sheet = makeContext(W, H)
sheet.setFillColor(Ink.light.wall); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
func top(_ y: CGFloat) -> CGFloat { CGFloat(H) - y }
label(sheet, "Simplify — 앱 아이콘 6회차 · 디자인 검사 반영", 80, top(84), size: 30, color: Ink.light.ink, weight: .semibold)
label(sheet, "큰 크기 · 128 · 64 · 32 · 16 pt (Retina 픽셀)  /  흰 벽 · 흑연", 80, top(118), size: 15, color: Ink.light.soft)
let names: [Concept: String] = [
    .i3: "I3  (5회차) 달 제목 · 주말 면 · 다섯 주",
    .i4: "I4  요일 표식 7개(일요일 공휴일 빨강) · 진한 주말 면 · 오늘 칸 막대 키움",
    .i5: "I5  I4와 같고 빨강 없이 흑백만"]
for (i, concept) in Concept.allCases.enumerated() {
    let y0 = 140 + CGFloat(i) * CGFloat(rowH)
    sheet.setFillColor(Ink.light.ink); sheet.fill(CGRect(x: 80, y: top(y0 + 2), width: CGFloat(W - 160), height: 1.75))
    label(sheet, names[concept]!, 80, top(y0 + 40), size: 18, color: Ink.light.ink, weight: .medium)
    stamp(sheet, concept, 1040, .light, at: CGPoint(x: 50, y: top(y0 + 640)), shown: 520)
    sheet.setFillColor(Ink.dark.wall); sheet.fill(CGRect(x: 560, y: top(y0 + 680), width: 520, height: 620))
    stamp(sheet, concept, 1040, .dark, at: CGPoint(x: 560, y: top(y0 + 640)), shown: 520)
    sheet.setFillColor(Ink.dark.wall); sheet.fill(CGRect(x: 1110, y: top(y0 + 680), width: CGFloat(W - 80 - 1110), height: 310))
    var x: CGFloat = 1140
    for size in [128, 64, 32, 16] {
        let px = size * 2
        stamp(sheet, concept, px, .light, at: CGPoint(x: x, y: top(y0 + 326)))
        stamp(sheet, concept, px, .dark, at: CGPoint(x: x, y: top(y0 + 650)))
        label(sheet, "\(size)pt", x, top(y0 + 352), size: 13, color: Ink.light.soft)
        x += CGFloat(px) + 48
    }
}
save(sheet, out.appendingPathComponent("icon-sheet-6.png"))
print("ok")
