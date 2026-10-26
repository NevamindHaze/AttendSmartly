import SwiftUI
import UIKit

// MARK: - Colour helpers

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Android stores colours as 0xAARRGGBB integers.
    convenience init(argb: Int) {
        self.init(hex: UInt32(truncatingIfNeeded: argb) & 0xFFFFFF)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: 1
        )
    }
}

// MARK: - Pastel palette (light pastels by day, deep jewel tones by night)

enum Pastel {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// Screen background behind the tiles.
    static let background = dynamic(0xF2EFF8, 0x110F16)
    /// Plain cards, pills and buttons sitting on top of a tile.
    static let surface = dynamic(0xFFFFFF, 0x221F2B)
    /// Text on tiles: deep plum by day, soft white by night.
    static let ink = dynamic(0x22192F, 0xF5F1FB)

    static let pink = dynamic(0xF9CFDD, 0x4C2536)
    static let mint = dynamic(0xC5EBD7, 0x1D4133)
    static let butter = dynamic(0xFBE6A2, 0x47391A)
    static let lavender = dynamic(0xDDD3F8, 0x312A54)
    static let peach = dynamic(0xFFD6BD, 0x4D2E1F)
    static let sky = dynamic(0xCAE4F8, 0x1C3449)

    /// A soft tile colour made from a subject's own colour.
    static func subject(_ argb: Int) -> Color {
        let base = UIColor(argb: argb)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? base.mixed(with: UIColor(hex: 0x15121C), amount: 0.66)
                : base.mixed(with: .white, amount: 0.74)
        })
    }

    /// The subject's colour at full strength, for dots and bars.
    static func subjectStrong(_ argb: Int) -> Color {
        Color(uiColor: UIColor(argb: argb))
    }

    /// Tile colour that matches the attendance health.
    static func status(_ summary: AttendanceSummary) -> Color {
        if summary.conducted == 0 { return lavender }
        let margin = summary.percentage - summary.target
        if margin < 0 { return pink }
        if margin <= 5 { return butter }
        return mint
    }
}

// MARK: - Shared tile pieces

extension View {
    /// A coloured, rounded tile.
    func tile(_ color: Color, radius: CGFloat = 28) -> some View {
        self.background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// White (or dark) capsule used for small labels on top of a tile.
struct TilePill: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Pastel.ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Pastel.surface.opacity(0.75), in: Capsule())
    }
}
