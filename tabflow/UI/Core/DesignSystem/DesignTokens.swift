import AppKit
import SwiftUI

enum DesignTokens {
    static let panelCornerRadius: CGFloat = 24
    static let cardCornerRadius: CGFloat = 14
    static let searchFieldCornerRadius: CGFloat = 10
    static let spacing: CGFloat = 16
    static let compactSpacing: CGFloat = 8
    static let selectionColor = Color.accentColor
    static let searchFieldBackground = Color(nsColor: .textBackgroundColor)
    static let searchFieldStroke = Color.primary.opacity(0.22)

    static func cardBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.24 : 0.16)
        }
        return Color.primary.opacity(isHovered ? 0.12 : 0.06)
    }

    static func cardWidth(for size: CardSize) -> CGFloat {
        switch size {
        case .small: 176
        case .medium: 232
        case .large: 288
        }
    }

    static func thumbnailHeight(for size: CardSize) -> CGFloat {
        switch size {
        case .small: 96
        case .medium: 132
        case .large: 168
        }
    }

    static func thumbnailDisplaySize(for image: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(
            bounds.width / max(image.width, 1),
            bounds.height / max(image.height, 1)
        )
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}

extension View {
    func searchFieldWell() -> some View {
        background(DesignTokens.searchFieldBackground, in: RoundedRectangle(
            cornerRadius: DesignTokens.searchFieldCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.searchFieldCornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.searchFieldStroke, lineWidth: 1)
        }
    }
}
