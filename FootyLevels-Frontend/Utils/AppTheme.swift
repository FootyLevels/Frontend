import SwiftUI

// MARK: - App Theme
/// Centralized theming system for FootyLevels
/// Change colors, fonts, spacing, and styles in one place

struct AppTheme {

    // MARK: - Color Palette

    struct Colors {
        // Primary Brand Colors
        static let primary = SL.green        // Forest green - main action color
        static let primaryDark = SL.greenActive    // Pressed green
        static let primaryLight = SL.iconTile   // Light green for backgrounds

        // Secondary Colors
        static let secondary = SL.ink      // Main text
        static let secondaryLight = SL.muted // Supporting text

        // Accent Colors
        static let accent = SL.lime         // Lime highlights
        static let accentDark = SL.noticeText     // Amber warnings

        // Semantic Colors
        static let success = SL.green        // Green
        static let warning = SL.noticeText        // Amber
        static let error = SL.errorText          // Red
        static let info = Color(hex: "2C6381")           // Blue

        // Difficulty Colors
        static let beginner = SL.green       // Green
        static let intermediate = SL.noticeText   // Amber
        static let advanced = SL.errorText       // Red

        // Background Colors
        static let background = SL.page     // Warm cream background
        static let surface = SL.panel                  // Card/surface background
        static let surfaceElevated = Color(hex: "FFFFFF") // Elevated surfaces

        // Text Colors
        static let textPrimary = SL.ink    // Main text
        static let textSecondary = SL.muted  // Secondary text
        static let textTertiary = SL.muted   // Disabled/placeholder
        static let textOnPrimary = Color.white           // Text on primary color
        static let textOnDark = Color.white              // Text on dark backgrounds

        // Border & Divider
        static let border = SL.panelBorder
        static let divider = SL.line

        // Shadow
        static let shadow = Color.black.opacity(0.05)
        static let shadowMedium = Color.black.opacity(0.1)
    }

    // MARK: - Gradients

    struct Gradients {
        static let primary = LinearGradient(
            colors: [Colors.primary, Colors.primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let legend = LinearGradient(
            colors: [SL.lime, SL.noticeText],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let currentStar = LinearGradient(
            colors: [Colors.primary, Colors.primary.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let beginner = LinearGradient(
            colors: [Colors.beginner, Colors.beginner.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let intermediate = LinearGradient(
            colors: [Colors.intermediate, Colors.intermediate.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let advanced = LinearGradient(
            colors: [Colors.advanced, Colors.advanced.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Typography

    struct Typography {
        // Large Titles
        static let largeTitle = Font.largeTitle.weight(.heavy)
        static let title = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.bold)
        static let title3 = Font.title3.weight(.semibold)

        // Body
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline

        // Small
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }

    // MARK: - Spacing & Metrics

    struct Metrics {
        // Padding
        static let paddingXS: CGFloat = 4
        static let paddingS: CGFloat = 8
        static let paddingM: CGFloat = 12
        static let padding: CGFloat = 16
        static let paddingL: CGFloat = 20
        static let paddingXL: CGFloat = 24
        static let paddingXXL: CGFloat = 32

        // Corner Radius
        static let cornerRadiusS: CGFloat = 8
        static let cornerRadius: CGFloat = 12
        static let cornerRadiusL: CGFloat = 16
        static let cornerRadiusXL: CGFloat = 20
        static let cornerRadiusPill: CGFloat = 100

        // Icon Sizes
        static let iconS: CGFloat = 16
        static let iconM: CGFloat = 24
        static let iconL: CGFloat = 32
        static let iconXL: CGFloat = 48

        // Avatar Sizes
        static let avatarS: CGFloat = 40
        static let avatarM: CGFloat = 60
        static let avatarL: CGFloat = 80
        static let avatarXL: CGFloat = 120

        // Card
        static let cardMinHeight: CGFloat = 80
        static let cardShadowRadius: CGFloat = 4
        static let cardShadowY: CGFloat = 2

        // Button
        static let buttonHeight: CGFloat = 50
        static let buttonHeightS: CGFloat = 40
    }

    // MARK: - Shadows

    struct Shadows {
        static let small = Shadow(color: Colors.shadow, radius: 2, x: 0, y: 1)
        static let medium = Shadow(color: Colors.shadow, radius: 4, x: 0, y: 2)
        static let large = Shadow(color: Colors.shadowMedium, radius: 8, x: 0, y: 4)
        static let elevated = Shadow(color: Colors.shadowMedium, radius: 15, x: 0, y: 8)
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Legacy Compatibility (for existing code)
    // These map to the new structure for backward compatibility

    static let primaryColor = Colors.primary
    static let secondaryColor = Colors.secondary
    static let accentColor = Colors.accent
    static let backgroundColor = Colors.background
    static let surfaceColor = Colors.surface
    static let errorColor = Colors.error
    static let textColor = Colors.textPrimary
}

// MARK: - View Modifiers

extension View {
    /// Apply card styling
    func cardStyle(padding: CGFloat = AppTheme.Metrics.padding) -> some View {
        self
            .padding(padding)
            .background(AppTheme.Colors.surface)
            .clipShape(.rect(cornerRadius: AppTheme.Metrics.cornerRadius))
            .shadow(
                color: AppTheme.Shadows.medium.color,
                radius: AppTheme.Shadows.medium.radius,
                x: AppTheme.Shadows.medium.x,
                y: AppTheme.Shadows.medium.y
            )
    }

    /// Apply primary button styling
    func primaryButtonStyle() -> some View {
        self
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Metrics.buttonHeight)
            .background(AppTheme.Colors.primary)
            .clipShape(.rect(cornerRadius: AppTheme.Metrics.cornerRadius))
    }

    /// Apply secondary button styling
    func secondaryButtonStyle() -> some View {
        self
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Metrics.buttonHeight)
            .background(AppTheme.Colors.surface)
            .clipShape(.rect(cornerRadius: AppTheme.Metrics.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
    }

    /// Apply pill badge styling
    func pillBadgeStyle(color: Color) -> some View {
        self
            .font(AppTheme.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, AppTheme.Metrics.paddingM)
            .padding(.vertical, AppTheme.Metrics.paddingXS)
            .background(color.opacity(0.1))
            .clipShape(.rect(cornerRadius: AppTheme.Metrics.cornerRadiusPill))
    }
}

// MARK: - Difficulty Helpers

extension AppTheme {
    /// Get color for difficulty level
    static func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner": return Colors.beginner
        case "intermediate": return Colors.intermediate
        case "advanced": return Colors.advanced
        default: return Colors.secondary
        }
    }

    /// Get hex string for difficulty level
    static func difficultyColorHex(_ difficulty: String) -> String {
        switch difficulty.lowercased() {
        case "beginner": return "173F31"
        case "intermediate": return "79551F"
        case "advanced": return "923E28"
        default: return "233C30"
        }
    }

    /// Get icon for difficulty level
    static func difficultyIcon(_ difficulty: String) -> String {
        switch difficulty.lowercased() {
        case "beginner": return "1.circle.fill"
        case "intermediate": return "2.circle.fill"
        case "advanced": return "3.circle.fill"
        default: return "circle.fill"
        }
    }

    /// Get gradient for difficulty level
    static func difficultyGradient(_ difficulty: String) -> LinearGradient {
        switch difficulty.lowercased() {
        case "beginner": return Gradients.beginner
        case "intermediate": return Gradients.intermediate
        case "advanced": return Gradients.advanced
        default: return Gradients.primary
        }
    }
}

// MARK: - Score Helpers

extension AppTheme {
    /// Get color based on score (0-10 scale)
    static func scoreColor(_ score: Double) -> Color {
        if score >= 8.5 { return Colors.success }
        if score >= 7.0 { return Colors.intermediate }
        if score >= 5.0 { return Colors.warning }
        return Colors.error
    }

    /// Get rating text based on score
    static func scoreRating(_ score: Double) -> String {
        if score >= 8.5 { return "Excellent" }
        if score >= 7.0 { return "Good" }
        if score >= 5.0 { return "Needs Work" }
        return "Keep Practicing"
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 20) {
            // Primary Colors
            Group {
                Text("Primary Colors")
                    .font(AppTheme.Typography.headline)
                HStack {
                    colorSwatch("Primary", AppTheme.Colors.primary)
                    colorSwatch("Primary Dark", AppTheme.Colors.primaryDark)
                    colorSwatch("Primary Light", AppTheme.Colors.primaryLight)
                }
            }

            // Difficulty Colors
            Group {
                Text("Difficulty Colors")
                    .font(AppTheme.Typography.headline)
                HStack {
                    colorSwatch("Beginner", AppTheme.Colors.beginner)
                    colorSwatch("Intermediate", AppTheme.Colors.intermediate)
                    colorSwatch("Advanced", AppTheme.Colors.advanced)
                }
            }

            // Semantic Colors
            Group {
                Text("Semantic Colors")
                    .font(AppTheme.Typography.headline)
                HStack {
                    colorSwatch("Success", AppTheme.Colors.success)
                    colorSwatch("Warning", AppTheme.Colors.warning)
                    colorSwatch("Error", AppTheme.Colors.error)
                    colorSwatch("Info", AppTheme.Colors.info)
                }
            }

            // Buttons
            Group {
                Text("Button Styles")
                    .font(AppTheme.Typography.headline)

                Text("Primary Button")
                    .primaryButtonStyle()

                Text("Secondary Button")
                    .secondaryButtonStyle()
            }

            // Cards
            Group {
                Text("Card Style")
                    .font(AppTheme.Typography.headline)

                Text("This is a card")
                    .cardStyle()
            }
        }
        .padding()
    }
    .background(AppTheme.Colors.background)
}

@ViewBuilder
func colorSwatch(_ name: String, _ color: Color) -> some View {
    VStack {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 60)
        Text(name)
            .font(.caption2)
    }
}
