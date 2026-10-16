import SwiftUI

extension ArtworkStyle {
    var background: Color {
        switch self {
        case .rain: Color(hex: 0x2A4170)
        case .waves: Color(hex: 0x1D5560)
        case .forest: Color(hex: 0x2B5236)
        case .fire: Color(hex: 0x7A3E22)
        case .noise: Color(hex: 0x6B2F55)
        case .breath: Color(hex: 0x463A7A)
        case .storm: Color(hex: 0x33354A)
        case .unknown: Color(hex: 0x2C2C2E)
        }
    }

    var accent: Color {
        switch self {
        case .rain: Color(hex: 0xA9C4F5)
        case .waves: Color(hex: 0x8EE0E8)
        case .forest: Color(hex: 0x9EE0B1)
        case .fire: Color(hex: 0xFFC79A)
        case .noise: Color(hex: 0xFFB3DE)
        case .breath: Color(hex: 0xCDBEFF)
        case .storm: Color(hex: 0xC9CBE6)
        case .unknown: Color(hex: 0x8E8E93)
        }
    }

    /// 播放页底色：封面色调压暗。
    var playerBackground: Color {
        switch self {
        case .rain: Color(hex: 0x17243D)
        case .waves: Color(hex: 0x102F35)
        case .forest: Color(hex: 0x172C1D)
        case .fire: Color(hex: 0x3A1E11)
        case .noise: Color(hex: 0x36182B)
        case .breath: Color(hex: 0x231D3E)
        case .storm: Color(hex: 0x1B1C27)
        case .unknown: Color(hex: 0x1C1C1E)
        }
    }

    var symbol: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .waves: "water.waves"
        case .forest: "tree.fill"
        case .fire: "flame.fill"
        case .noise: "waveform"
        case .breath: "wind"
        case .storm: "cloud.bolt.rain.fill"
        case .unknown: "music.note"
        }
    }
}

struct ArtworkView: View {
    let style: ArtworkStyle
    var cornerRadius: CGFloat = 20
    var symbolScale: CGFloat = 0.38

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(style.background)
            .overlay {
                GeometryReader { geo in
                    Image(systemName: style.symbol)
                        .font(.system(size: min(geo.size.width, geo.size.height) * symbolScale, weight: .medium))
                        .foregroundStyle(style.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
    }

    static func renderImage(_ style: ArtworkStyle) -> UIImage? {
        let renderer = ImageRenderer(content: ArtworkView(style: style, cornerRadius: 0).frame(width: 600, height: 600))
        renderer.scale = 1
        return renderer.uiImage
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
