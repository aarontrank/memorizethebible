import SwiftUI

/// Design doc §9. The whole palette, and nothing beyond it: no other colors,
/// no gradients, no shadows, no decorative imagery.
enum Palette {
    static let text = Color("scriptureText", light: 0x1C1C1E, dark: 0xF2F2F2)
    static let background = Color("background", light: 0xFFFFFF, dark: 0x0F0F10)
    static let blankFill = Color("blankFill", light: 0xFFF4C2, dark: 0x3A3220)
    static let blankUnderline = Color("blankUnderline", light: 0xE8CE6A, dark: 0xC9A94A)
    static let dimmedText = Color("dimmedText", light: 0x8A8A8E, dark: 0x8A8A8E)
    static let verseNumber = Color("verseNumber", light: 0xA0A0A5, dark: 0x76767A)
    static let progressFill = Color("progressFill", light: 0x1C1C1E, dark: 0xF2F2F2)
    static let progressTrack = Color("progressTrack", light: 0xEAEAEC, dark: 0x2A2A2C)
}

extension Color {
    /// A light/dark pair resolved by the trait environment. Dark mode is a
    /// requirement, not a nicety: a pure-white app at 5 AM is hostile (§9).
    init(_ name: String, light: UInt32, dark: UInt32) {
        self.init(
            UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// §9 type. Scripture is set in a serif with generous leading; UI chrome uses
/// the system face.
enum Typography {
    /// Line height multiple applied to scripture (§9: "generous line height").
    static let scriptureLineSpacingMultiple: CGFloat = 0.6

    /// Scripture face: bundled Literata (SIL OFL), falling back to the system
    /// serif if registration fails. See `ScriptureFont`.
    static func scripture(_ style: Font.TextStyle = .body, italic: Bool = false) -> Font {
        ScriptureFont.font(style, italic: italic)
    }

    static func verseNumber(_ style: Font.TextStyle = .caption2) -> Font {
        ScriptureFont.font(style).weight(.medium)
    }

    static func chrome(_ style: Font.TextStyle = .body) -> Font {
        .system(style)
    }
}

/// §9 motion. Nothing animates except these, and nothing at all under Reduce
/// Motion (§12).
enum Motion {
    static let maskCrossFade: TimeInterval = 0.18
    static let peekFadeIn: TimeInterval = 0.12
    static let peekFadeOut: TimeInterval = 0.20
    /// §7.3: a peeked word is visible for about two seconds.
    static let peekDuration: TimeInterval = 2.0

    static func crossFade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: maskCrossFade)
    }

    static func peekIn(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeIn(duration: peekFadeIn)
    }

    static func peekOut(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: peekFadeOut)
    }
}

enum Metrics {
    /// §9: measure capped around 38–42 characters per line on iPhone.
    static let scriptureMaxWidth: CGFloat = 560
    /// §12: minimum tap target, including individual blanks.
    static let minimumTapTarget: CGFloat = 44
    static let gutter: CGFloat = 20
    /// Width of the session controls when they sit beside the text rather than
    /// under it. Wide enough for the level row and the longest button label.
    static let controlRailWidth: CGFloat = 260
}
