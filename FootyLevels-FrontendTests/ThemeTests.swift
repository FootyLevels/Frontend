import SwiftUI
import Testing
import UIKit
@testable import FootyLevels_Frontend

/// The app follows the phone's light or dark setting, so every text colour must stay
/// readable on its background in both: 4.5:1 for text, 3:1 for outlines and data marks.
struct ThemeTests {

    private static let textPairs: [(String, Color, Color)] = [
        ("ink on page", SL.ink, SL.page),
        ("ink on card", SL.ink, SL.card),
        ("muted on page", SL.muted, SL.page),
        ("muted on card", SL.muted, SL.card),
        ("muted on raised", SL.muted, SL.raised),
        ("on-green on green", SL.onGreen, SL.green),
        ("on-green on pressed green", SL.onGreen, SL.greenActive),
        ("mode text on mode track", SL.modeText, SL.modeTrack),
        ("panel topline text", SL.panelToplineText, SL.panelTopline),
        ("selected preset text", SL.presetActiveText, SL.presetActive),
        ("icon tile text", SL.iconTileText, SL.iconTile),
        ("tick text", SL.tickText, SL.tick),
        ("error text", SL.errorText, SL.errorFill),
        ("notice text", SL.noticeText, SL.noticeFill),
        ("good on card", SL.good, SL.card),
        ("fair on card", SL.fair, SL.card),
        ("miss on card", SL.miss, SL.card),
        ("video text on video panel", SL.videoText, SL.videoPanel),
        ("video muted on video panel", SL.videoMuted, SL.videoPanel),
        ("white on wrong", .white, SL.wrong),
    ]

    private static let markPairs: [(String, Color, Color)] = [
        ("data on card", SL.data, SL.card),
        ("field outline on raised", SL.mark, SL.raised),
        ("control outline on card", SL.controlBorder, SL.card),
    ]

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func textStaysReadable(_ style: UIUserInterfaceStyle) {
        for (name, text, background) in Self.textPairs {
            let ratio = Self.contrast(text, background, style)
            #expect(ratio >= 4.5, "\(name) is \(ratio):1 in \(style == .dark ? "dark" : "light") mode")
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func marksStayVisible(_ style: UIUserInterfaceStyle) {
        for (name, mark, background) in Self.markPairs {
            let ratio = Self.contrast(mark, background, style)
            #expect(ratio >= 3, "\(name) is \(ratio):1 in \(style == .dark ? "dark" : "light") mode")
        }
    }

    /// The page really changes with the appearance rather than staying light.
    @Test func pageFollowsTheAppearance() {
        #expect(Self.luminance(SL.page, .light) > 0.7)
        #expect(Self.luminance(SL.page, .dark) < 0.05)
    }

    // MARK: - WCAG relative luminance and contrast

    private static func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let la = luminance(a, style), lb = luminance(b, style)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
