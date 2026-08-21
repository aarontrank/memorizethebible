import CoreText
import SwiftUI
import UIKit

/// Literata, the bundled scripture face (§9).
///
/// Registered at runtime with Core Text rather than declared in `UIAppFonts`,
/// so the generated Info.plist stays untouched. Both files are variable fonts
/// under the SIL Open Font License; `Literata-OFL.txt` ships alongside them and
/// is quoted on the About screen (§8.4).
///
/// If registration ever fails, everything falls back to the system serif — the
/// app must never fail to render scripture over a font problem.
enum ScriptureFont {
    static let familyName = "Literata"

    private(set) static var isAvailable = false

    /// Called once at launch, before the first view is built.
    static func register() {
        guard !isAvailable else { return }
        let names = ["Literata", "Literata-Italic"]
        var registered = 0
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                error?.release()
            }
        }
        // The roman face alone is enough to switch over; italic degrades to a
        // synthesised slant.
        isAvailable = registered > 0 && UIFont(name: familyName, size: 12) != nil
    }

    /// A Dynamic Type-scaled SwiftUI font for the given text style.
    static func font(_ style: Font.TextStyle, italic: Bool = false) -> Font {
        guard isAvailable else {
            let base = Font.system(style, design: .serif)
            return italic ? base.italic() : base
        }
        let name = italic && UIFont(name: "Literata-Italic", size: 12) != nil
            ? "Literata-Italic"
            : familyName
        return .custom(name, size: pointSize(for: style), relativeTo: style)
    }

    /// The matching `UIFont`, used by the flow layout for its measurements.
    /// Scaled through `UIFontMetrics` so it tracks Dynamic Type exactly as the
    /// SwiftUI font above does.
    static func uiFont(_ style: Font.TextStyle) -> UIFont {
        let system = UIFont.preferredFont(forTextStyle: style.uiTextStyle)
        guard isAvailable, let literata = UIFont(name: familyName, size: pointSize(for: style)) else {
            guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
            return UIFont(descriptor: descriptor, size: system.pointSize)
        }
        return UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: literata)
    }

    /// Unscaled point sizes; `UIFontMetrics` and `relativeTo:` apply Dynamic Type.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}
