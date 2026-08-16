import AppKit
import OSLog
import SwiftUI

@MainActor
final class OverlayController: OverlayPresenting {
    var onSelect: ((WindowRecord.ID) -> Void)? {
        didSet { model.onSelect = onSelect }
    }
    var onRescan: (() -> Void)? {
        didSet { model.onRescan = onRescan }
    }
    var onOpenWindowScope: (() -> Void)? {
        didSet { model.onOpenWindowScope = onOpenWindowScope }
    }
    var onCancel: (() -> Void)? {
        didSet { model.onCancel = onCancel }
    }
    var onRetryActivation: (() -> Void)? {
        didSet { model.onRetryActivation = onRetryActivation }
    }
    var onRemoveFailedWindow: (() -> Void)? {
        didSet { model.onRemoveFailedWindow = onRemoveFailedWindow }
    }
    var onOpenPermissions: (() -> Void)? {
        didSet { model.onOpenPermissions = onOpenPermissions }
    }
    var onQueryChange: ((String) -> Void)? {
        didSet { model.onQueryChange = onQueryChange }
    }
    private let screenshotMode: ScreenshotModeConfiguration?
    private let model = OverlayViewModel()
    private lazy var panel: SwitcherPanel = makePanel()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tabflow", category: "overlay")
    private var thumbnailEpoch: UInt64 = 0
    private var imagesByCGWindowID: [CGWindowID: CGImage] = [:]

    init(screenshotMode: ScreenshotModeConfiguration? = nil) {
        self.screenshotMode = screenshotMode
    }

    func show(session: SwitchSession, settings: AppSettings) {
        panel.allowsKeyStatus = false
        let targetScreen = screenshotMode != nil
            ? NSScreen.main
            : screenForPresentation(
                settings: settings,
                selectedWindow: session.windows.first(where: \.isCurrent)
            )
        model.prepareForPresentation(
            session: session,
            settings: settings,
            fixedPanelSize: screenshotMode?.panelSize,
            screenWidth: targetScreen?.visibleFrame.width ?? 1_440
        )
        applyCachedThumbnails(from: session)
        applyPanelSize()
        if screenshotMode != nil {
            centerOnMainDisplay()
        } else if let targetScreen {
            positionPanel(on: targetScreen)
        }
        presentPanel(settings: settings)
        if WindowDiagnosticLogging.isEnabled {
            logger.info("Overlay show \(WindowScanTrace.sessionSummary(session), privacy: .public)")
        }
    }

    func update(session: SwitchSession, settings: AppSettings) {
        model.update(session: session, settings: settings)
        applyCachedThumbnails(from: session)
        if WindowDiagnosticLogging.isEnabled {
            logger.info("Overlay update \(WindowScanTrace.sessionSummary(session), privacy: .public)")
        }
    }

    func showLoading(settings: AppSettings) {
        panel.allowsKeyStatus = false
        model.update(session: SwitchSession(windows: [], selectedIndex: 0), settings: settings)
        model.prepareNoWindowsPresentation()
        model.message = String(localized: "overlay.loading")
        if let fixedPanelSize = screenshotMode?.panelSize {
            model.panelSize = fixedPanelSize
        }
        applyPanelSize()
        if screenshotMode != nil {
            centerOnMainDisplay()
        } else {
            positionPanel(settings: settings, selectedWindow: nil)
        }
        presentPanel(settings: settings)
    }

    func beginThumbnailEpoch(_ epoch: UInt64) {
        thumbnailEpoch = epoch
    }

    func rememberThumbnails(_ images: [CGWindowID: CGImage]) {
        imagesByCGWindowID = OverlayThumbnailCache.capped(
            OverlayThumbnailCache.fillingGaps(
                existing: imagesByCGWindowID,
                remembered: images
            ),
            preferring: Array(imagesByCGWindowID.keys) + Array(images.keys)
        )
    }

    func updateThumbnail(windowID: WindowRecord.ID, image: CGImage, epoch: UInt64, cgWindowID: CGWindowID?) {
        guard epoch == thumbnailEpoch else { return }
        let resolvedCGWindowID = cgWindowID
            ?? model.session.windows.first(where: { $0.id == windowID })?.cgWindowID
        if let resolvedCGWindowID {
            imagesByCGWindowID[resolvedCGWindowID] = image
            imagesByCGWindowID = OverlayThumbnailCache.capped(
                imagesByCGWindowID,
                preferring: [resolvedCGWindowID]
            )
        }
        model.thumbnails[windowID] = image
    }

    func seedThumbnailIfMissing(
        windowID: WindowRecord.ID,
        image: CGImage,
        epoch: UInt64,
        cgWindowID: CGWindowID?
    ) {
        guard epoch == thumbnailEpoch, model.thumbnails[windowID] == nil else { return }
        updateThumbnail(windowID: windowID, image: image, epoch: epoch, cgWindowID: cgWindowID)
    }

    func pruneThumbnails(keeping ids: Set<WindowRecord.ID>) {
        model.thumbnails = model.thumbnails.filter { ids.contains($0.key) }
    }

    func discardCachedThumbnails(forClosedWindowIDs windowIDs: Set<CGWindowID>) {
        for windowID in windowIDs {
            imagesByCGWindowID.removeValue(forKey: windowID)
        }
        let remainingIDs = Set(
            model.session.windows.compactMap { window -> WindowRecord.ID? in
                guard let cgWindowID = window.cgWindowID, windowIDs.contains(cgWindowID) else {
                    return nil
                }
                return window.id
            }
        )
        if !remainingIDs.isEmpty {
            model.thumbnails = model.thumbnails.filter { !remainingIDs.contains($0.key) }
        }
    }

    func clearThumbnails() {
        model.thumbnails.removeAll()
        imagesByCGWindowID.removeAll()
    }

    func setAppearance(_ appearance: NSAppearance?) {
        panel.appearance = appearance
    }

    func showMessage(_ message: String) {
        model.showsNoWindowsActions = false
        model.showsActivationFailureActions = false
        model.message = message
        panel.orderFrontRegardless()
    }

    func showNoWindows() {
        panel.allowsKeyStatus = true
        model.prepareNoWindowsPresentation()
        if let fixedPanelSize = screenshotMode?.panelSize {
            model.panelSize = fixedPanelSize
        }
        applyPanelSize()
        model.message = nil
        model.showsActivationFailureActions = false
        model.showsNoWindowsActions = true
        if screenshotMode != nil {
            centerOnMainDisplay()
        } else if let settings = model.settings {
            positionPanel(settings: settings, selectedWindow: nil)
        } else {
            centerOnMainDisplay()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func showActivationFailure(_ message: String) {
        panel.allowsKeyStatus = true
        model.prepareNoWindowsPresentation()
        if let fixedPanelSize = screenshotMode?.panelSize {
            model.panelSize = fixedPanelSize
        }
        applyPanelSize()
        model.showsNoWindowsActions = false
        model.showsActivationFailureActions = true
        model.message = message
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.allowsKeyStatus = false
        model.showsActivationFailureActions = false
        model.showsNoWindowsActions = false
        model.message = nil
        model.thumbnails.removeAll()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
        panel.orderOut(nil)
    }

    private func applyCachedThumbnails(from session: SwitchSession) {
        let remapped = ThumbnailImageIndex.overlayThumbnails(
            windows: session.windows,
            imagesByCGWindowID: imagesByCGWindowID
        )
        let liveIDs = Set(session.windows.map(\.id))
        var next = model.thumbnails.filter { liveIDs.contains($0.key) }
        for (windowID, image) in remapped {
            next[windowID] = image
        }
        model.thumbnails = next
    }

    func bringToFront() {
        panel.orderFrontRegardless()
    }

    func centerOnMainDisplay() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(
            OverlayPanelPlacement.centeredFrame(
                size: NSSize(width: model.panelSize.width, height: model.panelSize.height),
                in: screen.frame
            ),
            display: true
        )
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.collectionBehavior = screenshotMode == nil
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hostingView = NSHostingView(rootView: SwitcherOverlayView(model: model))
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        return panel
    }

    private func applyPanelSize() {
        panel.setContentSize(NSSize(width: model.panelSize.width, height: model.panelSize.height))
    }

    private func presentPanel(settings: AppSettings) {
        let motion = OverlayAnimationPolicy.motion(
            preference: settings.animationPreference,
            reduceMotion: OverlayAnimationEnvironment.reduceMotion
        )
        if motion.fadesPanel {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = motion.fadeDuration
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func positionPanel(settings: AppSettings, selectedWindow: WindowRecord?) {
        guard let screen = screenForPresentation(settings: settings, selectedWindow: selectedWindow) else { return }
        positionPanel(on: screen)
    }

    private func screenForPresentation(settings: AppSettings, selectedWindow: WindowRecord?) -> NSScreen? {
        switch settings.overlayPosition {
        case .activeWindowDisplay:
            selectedWindow.flatMap(screen(containing:)) ?? screenUnderMouse() ?? NSScreen.main
        case .mouseDisplay:
            screenUnderMouse() ?? NSScreen.main
        case .mainDisplay:
            NSScreen.main
        case .fixedDisplay:
            screen(identifier: settings.fixedDisplayIdentifier) ?? NSScreen.main
        }
    }

    private func positionPanel(on screen: NSScreen) {
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - panel.frame.width / 2,
            y: screen.visibleFrame.midY - panel.frame.height / 2
        ))
        constrainPanelToScreen()
    }

    private func constrainPanelToScreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let maximum = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        var frame = panel.frame
        frame.size.width = min(frame.width, maximum.width)
        frame.size.height = min(frame.height, maximum.height)
        frame.origin.x = min(max(frame.minX, maximum.minX), maximum.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, maximum.minY), maximum.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func screen(identifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.stringValue == identifier
        }
    }

    private func screen(containing window: WindowRecord) -> NSScreen? {
        if let displayName = window.displayName,
           let namedScreen = NSScreen.screens.first(where: { $0.localizedName == displayName }) {
            return namedScreen
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.max { lhs, rhs in
            DisplayCoordinateSpace.intersectionArea(
                DisplayCoordinateSpace.cgFrame(fromAppKitFrame: lhs.frame, primaryTop: primaryTop),
                window.frame
            ) < DisplayCoordinateSpace.intersectionArea(
                DisplayCoordinateSpace.cgFrame(fromAppKitFrame: rhs.frame, primaryTop: primaryTop),
                window.frame
            )
        }
    }
}

enum OverlayPanelPlacement {
    static func centeredFrame(size: CGSize, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: (screenFrame.midX - size.width / 2).rounded(),
            y: (screenFrame.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }
}

final class SwitcherPanel: NSPanel {
    var allowsKeyStatus = false

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }
}
