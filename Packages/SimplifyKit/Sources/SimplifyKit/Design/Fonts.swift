import CoreText
import SwiftUI

/// Gowun Batang (SIL Open Font License, see Resources/Fonts/OFL.txt), bundled for titles and numerals.
public enum SimplifyFonts {
    /// Registers the bundled faces for this process. Safe to call more than once.
    public static func register() {
        _ = registered
    }

    private static let registered: Bool = {
        for name in ["GowunBatang-Regular", "GowunBatang-Bold"] {
            // A missing face falls back to the system font silently, so catch it in debug builds.
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("\(name).ttf is missing from SimplifyKit resources")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                assertionFailure("\(name) failed to register: \(String(describing: error?.takeRetainedValue()))")
            }
        }
        return true
    }()
}

public extension Font {
    /// The display face for month titles, headings and date numbers.
    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "GowunBatang-Bold" : "GowunBatang-Regular", fixedSize: size)
    }
}
