import AppKit
import SwiftUI

enum SleepTheme {
    static let amber = Color(hex: 0xF2B544)
    static let ink = Color(light: Color(hex: 0x1C1508), dark: Color(hex: 0x1C1508))

    static let popoverBackground = Color(light: Color(hex: 0xF5F4EF), dark: Color(hex: 0x1C1D22))
    static let card = Color(light: Color.white, dark: Color(hex: 0x24252B))
    static let iconWell = Color(light: Color(hex: 0xE8E6DF), dark: Color(hex: 0x2E3036))
    static let border = Color(light: Color(hex: 0xD8D6CE), dark: Color(hex: 0x34363D))
    static let powerBorder = Color(light: Color(hex: 0xC8C5BB), dark: Color(hex: 0x3E4048))
    static let muted = Color(light: Color(hex: 0x6B6A68), dark: Color(hex: 0xA3A6B0))
    static let text = Color(light: Color(hex: 0x1F1E1D), dark: Color(hex: 0xF2F2F4))
    static let footer = Color(light: Color(hex: 0x4A4946), dark: Color(hex: 0xD6D7DC))
    static let divider = Color(light: Color(hex: 0xE4E2DA), dark: Color(hex: 0x303238))
    static let section = Color(light: Color(hex: 0x6B6A68), dark: Color(hex: 0x8A8D97))
    static let switchOff = Color(light: Color(hex: 0xD4D2CA), dark: Color(hex: 0x3A3C44))
    static let segmentOn = Color(light: Color(hex: 0xE0DED6), dark: Color(hex: 0x3E4048))
    static let menuBarMuted = Color(hex: 0xA3A6B0)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            let color = match == .darkAqua ? dark : light
            return NSColor(color)
        })
    }
}
