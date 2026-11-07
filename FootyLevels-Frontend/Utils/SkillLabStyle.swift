import SwiftUI
import UIKit

/// The FootyLevels look. Every colour has a light and a dark value and follows the
/// phone's appearance: light mode is olive green on light grey with off-white cards;
/// dark mode is black with white controls and lime on the data. Video and 3D video
/// surfaces stay dark in both modes.
enum SL {
    // Page
    static let page = Color(light: "EBEBEB", dark: "000000")
    static let header = Color(light: "EBEBEB", dark: "000000")
    static let ink = Color(light: "0B0B0B", dark: "FFFFFF")
    static let muted = Color(light: "5E5E5E", dark: "B4B4B4")
    static let line = Color(light: "DCDCDC", dark: "222222")
    /// The main action colour: olive in light mode, white in dark mode. Text on it is `onGreen`.
    static let green = Color(light: "58752A", dark: "FFFFFF")
    static let greenActive = Color(light: "4A6323", dark: "E0E0E0")
    static let onGreen = Color(light: "FFFFFF", dark: "000000")
    /// System controls (toggles, progress, links): olive in light mode, lime in dark mode.
    static let tint = Color(light: "58752A", dark: "C6F24E")
    /// Data on the page (the 3D body, timelines, progress, key numbers). Graphics only in
    /// light mode, where it is under 4.5:1 against cards.
    static let data = Color(light: "6B8E2E", dark: "C6F24E")
    /// Lime for data on the dark video surfaces, in both modes.
    static let lime = Color(hex: "C6F24E")
    static let accentLine = data
    static let headlineSoft = muted
    /// A text link in the brand colour: dark olive in light mode, lime in dark mode.
    static let link = Color(light: "3F5A1A", dark: "C6F24E")
    /// A raised surface: buttons, fields and chips on top of a card.
    static let raised = Color(light: "FFFFFF", dark: "1C1C1C")

    // Video panel: dark in both modes
    static let videoPanel = Color(light: "141414", dark: "0A0A0A")
    static let videoTopline = Color(light: "1A1A1A", dark: "111111")
    static let videoStage = Color(light: "0E0E0E", dark: "050505")
    static let videoText = Color(hex: "F2F2F2")
    static let videoMuted = Color(hex: "A3A3A3")
    static let videoBorder = Color(hex: "2A2A2A")
    static let track = Color(hex: "4A4A4A")
    static let knob = Color(hex: "FFFFFF")
    /// Field outlines and frame marks: at least 3:1 against the surface they sit on.
    static let mark = Color(light: "858585", dark: "6E6E6E")
    static let controlBorder = Color(light: "8A8A8A", dark: "6E6E6E")

    // 3D inspector
    static let panel = Color(light: "F7F7F7", dark: "111111")
    static let panelBorder = Color(light: "E0E0E0", dark: "262626")
    static let panelTopline = Color(light: "F0F0F0", dark: "161616")
    static let panelToplineText = Color(light: "575757", dark: "B4B4B4")
    static let stage = Color(light: "F2F2F2", dark: "0A0A0A")
    static let toolbar = Color(light: "F7F7F7", dark: "111111")
    static let presetActive = Color(light: "E3EBD3", dark: "222A10")
    static let presetActiveBorder = Color(light: "C9D7AE", dark: "3A4A1A")
    static let presetActiveText = Color(light: "3F5A1A", dark: "C6F24E")
    static let presetText = Color(light: "575757", dark: "B4B4B4")
    static let readyDot = data
    static let idleDot = Color(light: "B0B0B0", dark: "4A4A4A")

    // Cards
    static let insight = Color(light: "F2F2F2", dark: "111111")
    static let iconTile = Color(light: "E3EBD3", dark: "1C1C1C")
    static let iconTileText = Color(light: "3F5A1A", dark: "C6F24E")
    static let card = Color(light: "F7F7F7", dark: "111111")
    static let cardBorder = Color(light: "E2E2E2", dark: "222222")
    static let cardSelected = green
    static let frameImage = Color(light: "D6D6D6", dark: "2A2A2A")
    static let tick = Color(light: "E3EBD3", dark: "222A10")
    static let tickText = Color(light: "3F5A1A", dark: "C6F24E")
    static let pipeline = Color(light: "F2F2F2", dark: "111111")
    static let pipelineBorder = Color(light: "E2E2E2", dark: "222222")
    static let pipelineIcon = Color(light: "E3EBD3", dark: "1C1C1C")
    static let modeTrack = Color(light: "E2E2E2", dark: "1C1C1C")
    static let modeBorder = Color(light: "D6D6D6", dark: "262626")
    static let modeText = Color(light: "474747", dark: "B4B4B4")
    static let errorFill = Color(light: "FBE9E7", dark: "2C1616")
    static let errorText = Color(light: "9E2B1E", dark: "FF8A7A")
    static let noticeFill = Color(light: "FBF1DD", dark: "2A2212")
    static let noticeText = Color(light: "7A4F12", dark: "F0C46A")

    // Outcomes and confidence, as text or marks on cards
    static let good = Color(light: "4A6A1F", dark: "C6F24E")
    static let fair = Color(light: "8A6418", dark: "F0C46A")
    static let miss = Color(light: "9E4A22", dark: "FF9A6A")
    /// A wrong answer's fill; white text on it in both modes (5.9:1).
    static let wrong = Color(hex: "B23B3B")
    /// Behind the person symbol when an account has no photo; the symbol is white (8:1).
    static let avatarFill = Color(hex: "3F5A1A")

    // Status dots on key frames
    static func frameDot(_ status: String) -> Color {
        switch status {
        case "ready": return Color(hex: "56894C")
        case "failed": return Color(hex: "BC6D49")
        case "running", "queued": return Color(hex: "C4A843")
        default: return Color(hex: "AEBD97")
        }
    }

    static func frameStatusText(_ status: String) -> String {
        switch status {
        case "ready": return "3D ready"
        case "failed": return "Retry needed"
        case "running": return "Reconstructing"
        case "queued": return "Queued"
        default: return "Key frame"
        }
    }

    // 3D scene, as UIColor for RealityKit materials. RealityKit reads the colour when
    // a material is made, so a scene built in one appearance keeps it until rebuilt.
    static let bodyTint = UIColor(light: "6B8E2E", dark: "C6F24E")
    // The two bodies in the overlay. Blue and orange stay apart with red-green
    // color blindness, where green and orange would not.
    static let overlayFirst = UIColor(red: 0x3E / 255, green: 0x7C / 255, blue: 0xB1 / 255, alpha: 1)
    static let overlaySecond = UIColor(red: 0xE0 / 255, green: 0x7B / 255, blue: 0x39 / 255, alpha: 1)

    // Type — the system face. A text style rather than a point size, so headings follow
    // the person's text size. Large titles are regular weight, as in the brand screens;
    // smaller headings are semibold, never heavier.
    static func display(_ style: Font.TextStyle) -> Font {
        switch style {
        case .largeTitle, .title: .system(style)
        default: .system(style, weight: .semibold)
        }
    }
}

extension Color {
    /// A colour that follows the system appearance, from two hex values.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    /// A colour that follows the system appearance, from two hex values.
    convenience init(light: String, dark: String) {
        let light = UIColor(Color(hex: light))
        let dark = UIColor(Color(hex: dark))
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - Shared pieces

/// The skewed three-bar logo followed by "footy**levels**". The last bar carries the
/// data colour: olive in light mode, lime in dark mode.
struct BrandMark: View {
    var size: CGFloat = 24
    /// Draws the mark in white for use over photographs.
    var onImage = false
    /// Turning this on springs the bars up one after another, then fades the
    /// wordmark in. The sign-in splash and the sign-in screen start it off.
    var drawn = true
    /// Keeps the bars rising and falling like a level meter, as on the sign-in screen.
    var levels = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: size * 0.4) {
            TimelineView(.animation(paused: !levels || reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .center, spacing: size * 0.14) {
                    bar(0, height: 0.8, color: onImage ? .white : SL.ink, time: time)
                    bar(1, height: 1, color: onImage ? .white : SL.ink, time: time)
                    bar(2, height: 0.57, color: onImage ? SL.lime : SL.data, time: time)
                        .shadow(color: SL.lime.opacity(levels && onImage && !reduceMotion ? 0.8 : 0), radius: size * 0.25)
                }
            }
            .frame(height: size)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.36, d: 1, tx: size * 0.18, ty: 0))

            // The wordmark is a logo, so it keeps its drawn size instead of scaling with text.
            Text("\(Text("Footy").font(.system(size: size, weight: .heavy)))\(Text("Levels").font(.system(size: size, weight: .medium)))")
                .tracking(-size * 0.05)
                .foregroundStyle(onImage ? .white : SL.ink)
                .opacity(drawn ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.26), value: drawn)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FootyLevels")
    }

    private func bar(_ index: Int, height: CGFloat, color: Color, time: TimeInterval) -> some View {
        let level = levels && !reduceMotion ? Self.levelScale(bar: index, at: time) : 1
        return Rectangle()
            .fill(color)
            .frame(width: size * 0.2, height: size * height)
            .scaleEffect(x: 1, y: (drawn ? 1 : 0) * level, anchor: .bottom)
            .animation(reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.35).delay(Double(index) * 0.09), value: drawn)
    }

    /// Each bar's height as a share of its resting height, at a moment in time. The three move
    /// at different speeds, like a level meter: the first dips to half, the second rests at
    /// 70% and rises to full, and the lime one rises to 145%.
    static func levelScale(bar: Int, at seconds: TimeInterval) -> CGFloat {
        let wave = { (period: Double) in (1 - cos(2 * .pi * seconds / period)) / 2 }
        switch bar {
        case 0: return 1 - 0.5 * wave(1.7)
        case 1: return 0.7 + 0.3 * wave(2.3)
        default: return 1 + 0.45 * wave(1.3)
        }
    }
}

/// Small spaced capitals, optionally led by the green rule.
struct Eyebrow: View {
    let text: String
    var rule = false
    var color: Color = SL.ink

    var body: some View {
        HStack(spacing: 8) {
            if rule {
                Rectangle().fill(SL.accentLine).frame(width: 21, height: 2)
            }
            Text(text)
                .font(.system(.caption2, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(color)
        }
    }
}

/// The header strip on each workspace panel: an icon label and a status.
struct PanelTopline<Trailing: View>: View {
    let icon: String
    let title: String
    var dark = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(.caption2, weight: .semibold))
                .tracking(1.3)
            Spacer()
            trailing
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .foregroundStyle(dark ? SL.videoText : SL.panelToplineText)
        .background(dark ? SL.videoTopline : SL.panelTopline)
    }
}

/// A status dot with its caption.
struct StatusDot: View {
    let text: String
    var ready = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ready ? SL.readyDot : SL.idleDot).frame(width: 6, height: 6)
            Text(text).font(.system(.caption2))
        }
        .foregroundStyle(SL.muted)
    }
}

/// The main action: a filled pill, olive with white text in light mode and white with
/// black text in dark mode.
struct SLPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 44)
            .background(isEnabled ? (configuration.isPressed ? SL.greenActive : SL.green) : SL.modeTrack,
                        in: Capsule())
            .foregroundStyle(isEnabled ? SL.onGreen : SL.muted)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A secondary action: a raised pill with a hairline border.
struct SLSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? SL.modeTrack : SL.raised, in: Capsule())
            .overlay(Capsule().stroke(SL.cardBorder))
            .foregroundStyle(isEnabled ? SL.ink : SL.muted)
    }
}

extension ButtonStyle where Self == SLPrimaryButtonStyle {
    static var slPrimary: SLPrimaryButtonStyle { SLPrimaryButtonStyle() }
    static var slPrimaryWide: SLPrimaryButtonStyle { SLPrimaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == SLSecondaryButtonStyle {
    static var slSecondary: SLSecondaryButtonStyle { SLSecondaryButtonStyle() }
}

extension View {
    /// The page canvas, including its navigation chrome, in either appearance.
    func slScreen() -> some View {
        self.foregroundStyle(SL.ink)
            .toolbarBackground(SL.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Rounded panel with the hairline border used across the app.
    func slPanel(fill: Color = SL.panel, border: Color = SL.panelBorder, radius: CGFloat = 16) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border))
    }

    /// A form field: a raised well with a border that stays visible against the page
    /// (at least 3:1 in both appearances).
    func slField() -> some View {
        padding(14)
            .frame(minHeight: 44)
            .background(SL.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SL.mark))
    }

    /// A fixed-size box, such as a number badge or icon tile, that grows with
    /// the person's text size so the text inside it never clips.
    func scaledFrame(width: CGFloat, height: CGFloat? = nil, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFrame(width: width, height: height ?? width, style: style))
    }

    /// Keeps a small control's look but gives it Apple's 44-point minimum tap area.
    func minimumTapArea() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
    }

    /// Frosted glass over a photograph or video: a light translucent fill with a hairline.
    func slGlass(radius: CGFloat = 22) -> some View {
        background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: radius))
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.35)))
            .environment(\.colorScheme, .dark)
    }
}

private struct ScaledFrame: ViewModifier {
    @ScaledMetric private var width: CGFloat
    @ScaledMetric private var height: CGFloat

    init(width: CGFloat, height: CGFloat, style: Font.TextStyle) {
        _width = ScaledMetric(wrappedValue: width, relativeTo: style)
        _height = ScaledMetric(wrappedValue: height, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height)
    }
}
