import AppKit
import SwiftUI

struct AppearancePreviewView: View {
    let settings: AppSettings

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            previewCard
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("settings.appearance.preview.accessibility"))
    }

    @ViewBuilder
    private var previewCard: some View {
        switch AppearancePreviewSample.resolvedLayout(
            overlayLayout: settings.overlayLayout,
            cardSize: settings.cardSize
        ) {
        case .list:
            WindowListRow(
                window: sampleWindow,
                isSelected: false,
                index: 1,
                settings: settings
            )
            .frame(maxWidth: 420)
        case .grid, .horizontal:
            WindowGridCard(
                window: sampleWindow,
                thumbnail: settings.shouldCaptureThumbnails ? AppearancePreviewSample.thumbnailImage() : nil,
                isSelected: false,
                index: 1,
                settings: settings,
                cardWidth: AppearancePreviewSample.cardWidth(for: settings.cardSize)
            )
        }
    }

    private var sampleWindow: WindowRecord {
        AppearancePreviewSample.window(
            applicationName: String(localized: "app.name"),
            applicationIconData: ApplicationIconRasterizer.pngData(
                from: NSApplication.shared.applicationIconImage
            ),
            title: String(localized: "settings.appearance.preview.windowTitle")
        )
    }
}
