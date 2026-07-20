import SwiftUI

/// 从十六进制字符串（如 "#3b82f6"）创建颜色，用于后端返回的标签 / 状态颜色。
extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }

        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        let red, green, blue: Double
        switch value.count {
        case 6:
            red = Double((rgb >> 16) & 0xff) / 255
            green = Double((rgb >> 8) & 0xff) / 255
            blue = Double(rgb & 0xff) / 255
        default:
            red = 0.5; green = 0.5; blue = 0.5
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
