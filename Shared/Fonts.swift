// Inter for Latin text, in the app and the widget: rounder and easier to read at small sizes
// than the system font. Persian letters aren't in Inter, so they fall back to the system's
// Persian font on their own. Keycaps for typed commands stay in the system monospaced font.
import CoreText
import SwiftUI

enum Fonts {
    // The bundled font files, registered once per process (the app and the widget each).
    static let registered: Void = {
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
}

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = Fonts.registered
        let name = switch weight {
        case .bold, .heavy, .black: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
        return .custom(name, size: size)
    }
}
