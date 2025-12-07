import SwiftUI

struct AppTheme {
    static let primaryColor = Color(hex: "2ECC71") // Emerald Green
    static let secondaryColor = Color(hex: "2C3E50") // Dark Blue/Slate
    static let accentColor = Color(hex: "F1C40F") // Sunflower Yellow
    static let backgroundColor = Color(hex: "F5F6FA") // Light Gray
    static let surfaceColor = Color.white
    static let errorColor = Color(hex: "E74C3C")
    static let textColor = Color(hex: "2C3E50")
    
    struct Metrics {
        static let cornerRadius: CGFloat = 12
        static let padding: CGFloat = 16
    }
}

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
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

