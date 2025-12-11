import SwiftUI

// MARK: - Temperature Rounding

/// Extension for consistent temperature rounding across app and widgets
/// Uses standard rounding (0.5 rounds up) to avoid truncation issues
extension Double {
    /// Rounds to nearest integer using standard rounding rules
    /// Example: 57.85 → 58, 57.49 → 57
    /// This ensures app and widget display the same temperature value
    var roundedInt: Int {
        Int(self.rounded())
    }
}

// MARK: - Color Extensions

// Hex initializer for consistent palette
extension Color {
    init(hex: String) {
        let hexValue = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hexValue.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

// Temperature-based gradient helper
func temperatureGradient(for fahrenheit: Double) -> LinearGradient {
    let start: Color
    let end: Color
    switch fahrenheit {
    case ..<32:
        start = Color(hex: "667eea"); end = Color(hex: "764ba2")
    case 32..<70:
        start = Color(hex: "11998e"); end = Color(hex: "38ef7d")
    case 70..<85:
        start = Color(hex: "f093fb"); end = Color(hex: "f5576c")
    default:
        start = Color(hex: "ff512f"); end = Color(hex: "dd2476")
    }
    return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
}
