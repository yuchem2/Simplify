import Foundation

extension Palette {
    /// Where each colour sits on the hue wheel, tuned so Google's named calendar colours land
    /// where a person would expect (Tangerine → orange, Sage and Basil → green, Grape → purple).
    private var hueCenter: Double? {
        switch self {
        case .red: 5
        case .orange: 22
        case .yellow: 48
        case .green: 135
        case .teal: 180
        case .blue: 215
        case .purple: 255
        case .pink: 330
        case .grey: nil
        }
    }

    /// The palette colour closest in hue to a provider's calendar colour (`#4986e7`, or CalDAV's `#4986e7ff`).
    /// Near-grey colours become `.grey`; unreadable input falls back to `.blue`.
    public static func nearest(toHex hex: String?) -> Palette {
        guard let hex, let rgb = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(6), radix: 16) else { return .blue }
        let r = Double((rgb >> 16) & 0xff) / 255, g = Double((rgb >> 8) & 0xff) / 255, b = Double(rgb & 0xff) / 255
        let maxV = max(r, g, b), delta = maxV - min(r, g, b)
        if maxV == 0 || delta / maxV < 0.18 { return .grey }
        var hue: Double
        switch maxV {
        case r: hue = (g - b) / delta
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        return allCases.compactMap { color in color.hueCenter.map { (color, $0) } }
            .min { distance(hue, $0.1) < distance(hue, $1.1) }!.0
    }

    private static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 360 - d)
    }
}
