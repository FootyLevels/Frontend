import SwiftUI
import UIKit

/// The Skill Lab look, taken from `3d-model-frontend/web/src/styles.css` so the
/// app and the browser viewer read as one product: deep pitch green, lime
/// accents, and pale sage panels.
enum SL {
    // Page
    static let page = Color(hex: "F8F8F2")
    static let header = Color(hex: "FAFAF5")
    static let ink = Color(hex: "233C30")
    static let muted = Color(hex: "58665B")
    static let line = Color(hex: "DFE3D9")
    static let green = Color(hex: "173F31")
    static let greenActive = Color(hex: "244C36")
    static let lime = Color(hex: "D9EF8B")
    static let accentLine = Color(hex: "719554")
    static let headlineSoft = Color(hex: "526B53")

    // Video panel
    static let videoPanel = Color(hex: "142C22")
    static let videoTopline = Color(hex: "17352A")
    static let videoStage = Color(hex: "11271E")
    static let videoText = Color(hex: "DCE8D4")
    static let videoMuted = Color(hex: "8EAA94")
    static let track = Color(hex: "50604A")
    static let knob = Color(hex: "E7F6B0")
    static let mark = Color(hex: "78936B")

    // 3D inspector
    static let panel = Color(hex: "F9FAF3")
    static let panelBorder = Color(hex: "D7DECF")
    static let panelTopline = Color(hex: "F2F5EB")
    static let panelToplineText = Color(hex: "5A6C52")
    static let stage = Color(hex: "EDF0E8")
    static let toolbar = Color(hex: "F6F8EF")
    static let presetActive = Color(hex: "E4ECD6")
    static let presetActiveBorder = Color(hex: "D1DFBE")
    static let presetActiveText = Color(hex: "355338")
    static let presetText = Color(hex: "586C4E")
    static let readyDot = Color(hex: "558552")
    static let idleDot = Color(hex: "B4BF98")

    // Cards
    static let insight = Color(hex: "F5F6EF")
    static let iconTile = Color(hex: "E9EFDE")
    static let iconTileText = Color(hex: "4E663C")
    static let card = Color(hex: "F4F5ED")
    static let cardBorder = Color(hex: "DCE3D3")
    static let cardSelected = Color(hex: "486539")
    static let frameImage = Color(hex: "C9D3BD")
    static let tick = Color(hex: "DCEFAF")
    static let tickText = Color(hex: "31572D")
    static let pipeline = Color(hex: "EDF2E3")
    static let pipelineBorder = Color(hex: "DCE5CB")
    static let pipelineIcon = Color(hex: "E0EBCE")
    static let modeTrack = Color(hex: "E9EFDF")
    static let modeBorder = Color(hex: "D5DFC8")
    static let modeText = Color(hex: "526546")
    static let errorFill = Color(hex: "F8E9E3")
    static let errorText = Color(hex: "923E28")
    static let noticeFill = Color(hex: "F5E9D8")
    static let noticeText = Color(hex: "79551F")

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

    // 3D scene, as UIColor for RealityKit materials
    static let bodyTint = UIColor(red: 0xA1 / 255, green: 0xBD / 255, blue: 0x9B / 255, alpha: 1)
    // The two bodies in the overlay. Blue and orange stay apart with red-green
    // color blindness, where green and orange would not.
    static let overlayFirst = UIColor(red: 0x3E / 255, green: 0x7C / 255, blue: 0xB1 / 255, alpha: 1)
    static let overlaySecond = UIColor(red: 0xE0 / 255, green: 0x7B / 255, blue: 0x39 / 255, alpha: 1)

    // Type — Manrope for display, DM Sans for text in the web app. The system
    // face with tightened tracking gets close without bundling fonts.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Shared pieces

/// The skewed three-bar logo followed by "footy**levels**".
struct BrandMark: View {
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.4) {
            HStack(alignment: .center, spacing: size * 0.14) {
                bar(height: 0.8)
                bar(height: 1)
                bar(height: 0.57)
            }
            .frame(height: size)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.36, d: 1, tx: size * 0.18, ty: 0))

            (Text("footy").font(SL.display(size, .heavy))
                + Text("levels").font(SL.display(size, .medium)))
                .tracking(-size * 0.05)
                .foregroundStyle(SL.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FootyLevels")
    }

    private func bar(height: CGFloat) -> some View {
        Rectangle()
            .fill(SL.green)
            .frame(width: size * 0.2, height: size * height)
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
                .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
            Spacer()
            trailing
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .foregroundStyle(dark ? Color(hex: "D5DFCF") : SL.panelToplineText)
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
            Text(text).font(.system(size: 10))
        }
        .foregroundStyle(SL.muted)
    }
}

struct SLPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 44)
            .background(isEnabled ? (configuration.isPressed ? SL.greenActive : SL.green) : SL.line,
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isEnabled ? Color.white : SL.muted)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SLSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? SL.iconTile : SL.panel,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SL.panelBorder))
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
    /// The workspace uses a light canvas, including its navigation chrome.
    func slScreen() -> some View {
        self.foregroundStyle(SL.ink)
            .toolbarBackground(SL.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    /// Rounded panel with the hairline border used across the workspace.
    func slPanel(fill: Color = SL.panel, border: Color = SL.panelBorder, radius: CGFloat = 10) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border))
    }
}
