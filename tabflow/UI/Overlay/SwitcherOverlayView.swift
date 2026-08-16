import SwiftUI

struct SwitcherOverlayView: View {
    @Bindable var model: OverlayViewModel

    private var settings: AppSettings? { model.settings }
    private var showsSearchField: Bool { settings?.showsSearchField == true }
    private var windows: [WindowRecord] { model.session.filteredWindows }
    private var sections: [WindowSection] {
        let entries = windows.enumerated().map { WindowEntry(index: $0.offset, window: $0.element) }
        guard settings?.groupsApplications == true else {
            return [WindowSection(id: "all", title: nil, entries: entries)]
        }

        var order: [String] = []
        var entriesByApplication: [String: [WindowEntry]] = [:]
        var names: [String: String] = [:]
        for entry in entries {
            let key = entry.window.bundleIdentifier ?? "pid:\(entry.window.pid)"
            if entriesByApplication[key] == nil {
                order.append(key)
                names[key] = entry.window.applicationName
            }
            entriesByApplication[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let groupEntries = entriesByApplication[key] else { return nil }
            return WindowSection(id: key, title: names[key], entries: groupEntries)
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.spacing) {
            if showsSearchField {
                searchField
            } else if !model.session.query.isEmpty {
                searchHeader
            }

            if model.showsNoWindowsActions {
                noWindowsState
            } else if model.showsActivationFailureActions {
                activationFailureState
            } else if let message = model.message {
                ContentUnavailableView(
                    message,
                    systemImage: "rectangle.on.rectangle.slash"
                )
                .frame(minWidth: 420, minHeight: 220)
            } else if windows.isEmpty {
                ContentUnavailableView(
                    model.session.query.isEmpty
                        ? String(localized: "overlay.noWindows")
                        : String(localized: "overlay.noSearchResults"),
                    systemImage: "rectangle.on.rectangle.slash"
                )
                .frame(minWidth: 420, minHeight: 220)
            } else {
                windowGrid
            }

            if settings?.showsKeyboardHint != false {
                Text(showsSearchField ? "overlay.keyboardHint.searchField" : "overlay.keyboardHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(Text(
                        showsSearchField
                            ? "overlay.keyboardHint.searchField.accessibility"
                            : "overlay.keyboardHint.accessibility"
                    ))
            }
            if settings?.diagnosticsEnabled == true {
                Text(WindowScanTrace.sessionSummary(model.session))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(
            width: model.panelSize.width,
            height: model.panelSize.height,
            alignment: .top
        )
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous))
        .preferredColorScheme(preferredColorScheme)
        .onExitCommand {
            model.onCancel?()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: DesignTokens.compactSpacing) {
            Image(systemName: "magnifyingglass")
            Text(model.session.query)
                .lineLimit(1)
            Spacer()
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .searchFieldWell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            String(
                format: String(localized: "overlay.search.accessibility.format"),
                locale: .current,
                model.session.query
            )
        ))
    }

    private var searchField: some View {
        HStack(spacing: DesignTokens.compactSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "overlay.search.placeholder",
                text: Binding(
                    get: { model.session.query },
                    set: { model.onQueryChange?($0) }
                )
            )
            .textFieldStyle(.plain)
            .accessibilityLabel(Text("overlay.search.placeholder"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .searchFieldWell()
        .frame(maxWidth: .infinity)
    }

    private var noWindowsState: some View {
        VStack(spacing: DesignTokens.spacing) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text("overlay.noWindows")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            VStack(spacing: DesignTokens.compactSpacing) {
                Button("overlay.openWindowScope") {
                    model.onOpenWindowScope?()
                }
                Button("overlay.rescan") {
                    model.onRescan?()
                }
                Button("action.cancel", role: .cancel) {
                    model.onCancel?()
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activationFailureState: some View {
        VStack(spacing: DesignTokens.spacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text("error.activationFailed")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let message = model.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: DesignTokens.compactSpacing) {
                Button("action.retry") {
                    model.onRetryActivation?()
                }
                Button("overlay.activationFailed.remove") {
                    model.onRemoveFailedWindow?()
                }
                Button("overlay.activationFailed.permissions") {
                    model.onOpenPermissions?()
                }
                Button("action.cancel", role: .cancel) {
                    model.onCancel?()
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var windowGrid: some View {
        switch model.resolvedLayout {
        case .grid:
            grid
        case .horizontal:
            horizontal
        case .list:
            list
        }
    }

    private var grid: some View {
        let cardWidth = min(DesignTokens.cardWidth(for: settings?.cardSize ?? .medium), 240)
        let columnCount = min(max(windows.count, 1), 4)
        let gridContentWidth = CGFloat(columnCount) * cardWidth
            + CGFloat(max(columnCount - 1, 0)) * DesignTokens.spacing
        let columns = Array(
            repeating: GridItem(.fixed(cardWidth), spacing: DesignTokens.spacing),
            count: columnCount
        )

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: DesignTokens.spacing) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: DesignTokens.spacing) {
                            ForEach(section.entries) { entry in
                                Button {
                                    model.onSelect?(entry.window.id)
                                } label: {
                                    WindowGridCard(
                                        window: entry.window,
                                        thumbnail: model.thumbnails[entry.window.id],
                                        isSelected: entry.index == model.session.selectedIndex,
                                        index: entry.index + 1,
                                        settings: settings,
                                        cardWidth: cardWidth
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(entry.window.id)
                            }
                        }
                    }
                }
                .frame(width: gridContentWidth, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: model.session.selectedWindow?.id) { _, selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
        .frame(
            minWidth: gridContentWidth,
            maxWidth: gridContentWidth,
            maxHeight: 640
        )
    }

    private var horizontal: some View {
        let cardWidth = min(DesignTokens.cardWidth(for: settings?.cardSize ?? .medium), 240)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: DesignTokens.spacing) {
                    ForEach(sections.flatMap(\.entries)) { entry in
                        Button {
                            model.onSelect?(entry.window.id)
                        } label: {
                            WindowGridCard(
                                window: entry.window,
                                thumbnail: model.thumbnails[entry.window.id],
                                isSelected: entry.index == model.session.selectedIndex,
                                index: entry.index + 1,
                                settings: settings,
                                cardWidth: cardWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .id(entry.window.id)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            .onChange(of: model.session.selectedWindow?.id) { _, selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 640)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: DesignTokens.compactSpacing) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(section.entries) { entry in
                            Button {
                                model.onSelect?(entry.window.id)
                            } label: {
                                WindowListRow(
                                    window: entry.window,
                                    isSelected: entry.index == model.session.selectedIndex,
                                    index: entry.index + 1,
                                    settings: settings
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.window.id)
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: model.session.selectedWindow?.id) { _, selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: 520)
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct WindowEntry: Identifiable {
    let index: Int
    let window: WindowRecord

    var id: WindowRecord.ID { window.id }
}

private struct WindowSection: Identifiable {
    let id: String
    let title: String?
    let entries: [WindowEntry]
}

struct WindowGridCard: View {
    let window: WindowRecord
    let thumbnail: CGImage?
    let isSelected: Bool
    let index: Int
    let settings: AppSettings?
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.compactSpacing) {
            preview

            HStack(alignment: .top, spacing: DesignTokens.compactSpacing) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    if settings?.showsWindowTitle != false {
                        Text(window.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    if settings?.showsApplicationName != false {
                        Text(window.applicationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("\(index)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if settings?.showsWindowStatus != false {
                WindowStatusRow(window: window)
            }
        }
        .padding(DesignTokens.compactSpacing)
        .frame(width: cardWidth)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.selectionColor : .clear, lineWidth: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var preview: some View {
        let height = DesignTokens.thumbnailHeight(for: settings?.cardSize ?? .medium)
        Group {
            if settings?.showsThumbnails != false, let thumbnail {
                CenteredThumbnailView(image: thumbnail)
                    .padding(6)
            } else {
                appIcon
                    .frame(width: 56, height: 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(Color.primary.opacity(0.06))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var appIcon: some View {
        if let data = window.applicationIconData, let icon = NSImage(data: data) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: Text {
        let status = window.statusLabels.joined(separator: "、")
        return Text(
            String(
                format: String(localized: "window.accessibilityLabel.format"),
                locale: .current,
                index,
                window.displayTitle,
                window.applicationName,
                status
            )
        )
    }
}

struct WindowListRow: View {
    let window: WindowRecord
    let isSelected: Bool
    let index: Int
    let settings: AppSettings?

    var body: some View {
        HStack(spacing: DesignTokens.compactSpacing) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            listIcon
            VStack(alignment: .leading, spacing: 2) {
                if settings?.showsWindowTitle != false {
                    Text(window.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                }
                if settings?.showsApplicationName != false {
                    Text(window.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if settings?.showsWindowStatus != false {
                    WindowStatusRow(window: window)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: settings?.showsWindowStatus != false ? 64 : 44,
            alignment: .leading
        )
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.selectionColor : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            String(
                format: String(localized: "window.listAccessibilityLabel.format"),
                locale: .current,
                index,
                window.displayTitle,
                window.applicationName
            )
        ))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var listIcon: some View {
        if let data = window.applicationIconData, let icon = NSImage(data: data) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
    }
}

private struct WindowStatusRow: View {
    let window: WindowRecord

    var body: some View {
        HStack(spacing: 6) {
            ForEach(window.statusLabels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            if OverlayDisplayNamePolicy.showsDisplayName(screenCount: NSScreen.screens.count),
               let displayName = window.displayName {
                Text(displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private final class CenteringThumbnailHost: NSView {
    let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = false
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct CenteredThumbnailView: NSViewRepresentable {
    let image: CGImage

    func makeNSView(context: Context) -> CenteringThumbnailHost {
        let view = CenteringThumbnailHost()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CenteringThumbnailHost, context: Context) {
        view.imageView.image = NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
        )
    }
}
