import SwiftUI

extension Color {
    init(calendarHex: String?) {
        guard let calendarHex else {
            self = .secondary
            return
        }

        let value = calendarHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            self = .secondary
            return
        }

        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}
