import SwiftUI
import AppKit

enum NovaStyle {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x12645B, 0x80D6C4)
    static let onAccent = adaptive(0xFFFFFF, 0x142622)
    static let canvas = adaptive(0xF5F7F7, 0x171C1D)
    static let surface = adaptive(0xFFFFFF, 0x212728)
    static let sidebar = adaptive(0xEDF1F1, 0x1D2324)
    static let muted = adaptive(0x556366, 0xADBABB)
    static let line = adaptive(0xD7DFDF, 0x3E494A)
    static let success = adaptive(0x17734E, 0x83D8AB)
    static let warning = adaptive(0x99600B, 0xF2C07D)
    static let contentWidth: CGFloat = 820
}

struct NovaPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NovaStyle.line.opacity(0.65), lineWidth: 1))
    }
}

struct NovaSectionTitle: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(NovaStyle.muted) }
}

struct NovaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(isEnabled ? NovaStyle.onAccent : NovaStyle.muted)
            .background(isEnabled ? NovaStyle.accent : NovaStyle.line, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isFocused ? NovaStyle.accent : .clear, lineWidth: 2).padding(-3))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NovaEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(NovaStyle.accent).accessibilityHidden(true)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(NovaStyle.muted).multilineTextAlignment(.center)
        }.padding(.vertical, 38).frame(maxWidth: .infinity)
    }
}
