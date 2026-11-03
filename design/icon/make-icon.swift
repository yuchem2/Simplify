// Builds Apps/macOS/AppIcon.icon (Icon Composer document) from the I4 "ink ledger" drawing.
// The geometry is render5.swift's drawIcon(concept: .i4, framed: false) at full size (detail 2),
// split into the layers Icon Composer stacks: the paper is the document's fill, the weekend faces
// sit on it, the ink (rules, today bar, pencil, with the pencil's paper cuts as holes) above them,
// and the Sunday holiday mark on top. Each layer is drawn once in light and once in graphite.
// The script rewrites the whole AppIcon.icon folder: change the icon here, not in Icon Composer.
//
// Usage: swift design/icon/make-icon.swift <repo-root> [--check <render5-out-dir>]
//   --check composites the layers (without the centering shift) over the paper and compares them
//   with render5's icon-I4-{light,dark}-fullbleed.png, so the shipped icon stays the drawing on the sheet.
import AppKit
import CoreGraphics

struct Ink {
    let paper, ink, raised, red: CGColor
    static let light = Ink(paper: rgb(0xFBFAF7), ink: rgb(0x1A1A1A), raised: rgb(0xEAE8E2), red: rgb(0xB3332A))
    static let dark = Ink(paper: rgb(0x2A2927), ink: rgb(0xECEBE6), raised: rgb(0x33312E), red: rgb(0xFF8A7A))
}
func rgb(_ v: Int) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

enum Layer: String, CaseIterable { case faces, ink, red }

/// The sheet's drawing spans x 96…694 of the 824 grid (margins 96 and 130), so it leans left.
/// The shipped icon moves it right by half the difference; the shapes themselves are unchanged.
let centering: CGFloat = 17

/// render5's I4 at detail 2, full bleed, drawing only `layer`. Paper-coloured cuts in the pencil
/// are cleared out of the ink layer so the document's fill shows through them.
func drawLayer(_ c: CGContext, _ layer: Layer, size s: CGFloat, ink: Ink, shift: CGFloat = centering) {
    let u = s / 824
    let devicePx = 1024 / s * u
    func lw(_ w: CGFloat) -> CGFloat { max(w * u, devicePx * 0.9) }
    c.saveGState()
    c.translateBy(x: shift * u, y: s); c.scaleBy(x: 1, y: -1)
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }
    func fill(_ r: CGRect, _ col: CGColor) { c.setFillColor(col); c.fill(r) }
    func cut(_ r: CGRect) { c.saveGState(); c.setBlendMode(.clear); c.fill(r); c.restoreGState() }
    func hline(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ w: CGFloat, _ col: CGColor) { fill(CGRect(x: x0 * u, y: y * u - lw(w) / 2, width: (x1 - x0) * u, height: lw(w)), col) }

    let gx0: CGFloat = 96, gx1: CGFloat = 536, cols: CGFloat = 7
    let cw = (gx1 - gx0) / cols
    let head: CGFloat = 196, weeks = 5
    let rh = (732 - head) / CGFloat(weeks)
    switch layer {
    case .faces:
        // Sunday and Saturday columns on the raised face
        fill(R(gx0, head, cw, 732 - head), ink.raised)
        fill(R(gx1 - cw, head, cw, 732 - head), ink.raised)
    case .red:
        // Sunday's weekday mark, in the holiday red
        fill(R(gx0 + cw * 0.28, head - 52, cw * 0.44, 20), ink.red)
    case .ink:
        for k in 1..<7 { fill(R(gx0 + cw * CGFloat(k) + cw * 0.28, head - 52, cw * 0.44, 20), ink.ink) }
        hline(gx0, gx1, head, 14, ink.ink)                                     // weekday rule, spine weight
        for k in 1...weeks { hline(gx0, gx1, head + rh * CGFloat(k), 4.5, ink.ink) }
        fill(R(gx0 + cw * 3, head + rh, cw, rh * 0.34), ink.ink)                // today: second week, Wednesday
        // the pencil, upright, as the spine
        let px: CGFloat = 640, w: CGFloat = 108, top: CGFloat = 92, tipY: CGFloat = 740
        let shaft = tipY - w * 1.1
        fill(R(px - w / 2, top, w, shaft - top), ink.ink)
        c.setFillColor(ink.ink)
        c.move(to: CGPoint(x: (px - w / 2) * u, y: shaft * u)); c.addLine(to: CGPoint(x: (px + w / 2) * u, y: shaft * u))
        c.addLine(to: CGPoint(x: px * u, y: tipY * u)); c.closePath(); c.fillPath()
        cut(R(px - w / 2 + 16, top + 64, 9, shaft - top - 84))                  // the highlight
        cut(R(px - w / 2, top + 34, w, 8))                                      // the ferrule band
    }
    c.restoreGState()
}

func makeContext(_ w: Int) -> CGContext {
    CGContext(data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }
func layerImage(_ layer: Layer, _ ink: Ink, _ px: Int = 1024, shift: CGFloat = centering) -> CGImage {
    let c = makeContext(px); drawLayer(c, layer, size: CGFloat(px), ink: ink, shift: shift); return c.makeImage()!
}
func srgb(_ col: CGColor) -> String {
    let p = col.components!.prefix(3).map { String(format: "%.5f", $0) }.joined(separator: ",")
    return "srgb:\(p),1.00000"
}

guard CommandLine.arguments.count >= 2, !CommandLine.arguments[1].hasPrefix("--") else {
    print("usage: swift design/icon/make-icon.swift <repo-root> [--check <render5-out-dir>]"); exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let args = Array(CommandLine.arguments.dropFirst(2))

if let i = args.firstIndex(of: "--check"), i + 1 < args.count {
    // Composite and compare against render5's full-bleed I4; report the worst channel difference.
    let ref = URL(fileURLWithPath: args[i + 1])
    var worst = 0
    for (name, ink) in [("light", Ink.light), ("dark", Ink.dark)] {
        let c = makeContext(1024)
        c.setFillColor(ink.paper); c.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        for layer in [Layer.faces, .ink, .red] { c.draw(layerImage(layer, ink, shift: 0), in: CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
        let mine = NSBitmapImageRep(cgImage: c.makeImage()!)
        let theirs = NSBitmapImageRep(data: try! Data(contentsOf: ref.appendingPathComponent("icon-I4-\(name)-fullbleed.png")))!
        var diff = 0, over = 0
        for y in 0..<1024 { for x in 0..<1024 {
            let a = mine.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, b = theirs.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let d = Int(max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)) * 255)
            diff = max(diff, d); if d > 2 { over += 1 }
        } }
        print("\(name): max channel diff \(diff), pixels over 2: \(over)")
        worst = max(worst, diff)
    }
    exit(worst > 2 ? 1 : 0)
}

let doc = root.appendingPathComponent("Apps/macOS/AppIcon.icon")
let assets = doc.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: doc)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for layer in Layer.allCases {
    for (name, ink) in [("light", Ink.light), ("dark", Ink.dark)] {
        try! png(layerImage(layer, ink)).write(to: assets.appendingPathComponent("\(layer.rawValue)-\(name).png"))
    }
}

func images(_ layer: Layer) -> [[String: Any]] {
    [["value": "\(layer.rawValue)-light.png"], ["appearance": "dark", "value": "\(layer.rawValue)-dark.png"]]
}
// Groups and layers run front to back. The ink and the red mark take the glass; the weekend
// faces stay flat paper tone under them.
let json: [String: Any] = [
    "fill-specializations": [
        ["value": ["solid": srgb(Ink.light.paper)]],
        ["appearance": "dark", "value": ["solid": srgb(Ink.dark.paper)]],
    ],
    "groups": [
        [
            "name": "Ink",
            "layers": [
                ["name": "red", "image-name-specializations": images(.red), "glass": true],
                ["name": "ink", "image-name-specializations": images(.ink), "glass": true],
            ],
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": false, "value": 0.5],
            "specular": true,
        ],
        [
            "name": "Faces",
            "layers": [[
                "name": "faces", "image-name-specializations": images(.faces), "glass": false,
                // in clear and tinted the faces turn into bright slabs that outweigh the ink; drop them there
                "hidden-specializations": [["value": false], ["appearance": "tinted", "value": true]],
            ]],
            "shadow": ["kind": "none", "opacity": 0.5],
            "translucency": ["enabled": false, "value": 0.5],
            "specular": false,
        ],
    ],
    "supported-platforms": ["squares": ["macOS"]],
]
let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try! data.write(to: doc.appendingPathComponent("icon.json"))
print("wrote \(doc.path)")
