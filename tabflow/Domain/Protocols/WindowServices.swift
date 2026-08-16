import CoreGraphics

@MainActor
protocol WindowProviding: AnyObject {
    func cachedWindows(options: WindowQueryOptions) async -> [WindowRecord]
    func refreshWindows(options: WindowQueryOptions) async -> [WindowRecord]
    func isWindowValid(_ windowID: WindowRecord.ID) async -> Bool
}

@MainActor
protocol WindowActivating: AnyObject {
    func activate(windowID: WindowRecord.ID, restoreMinimized: Bool) async throws
}

nonisolated protocol ThumbnailProviding: AnyObject {
    func cachedThumbnail(for window: WindowRecord) async -> CGImage?
    func cachedThumbnails(for windows: [WindowRecord]) async -> [CGWindowID: CGImage]
    func refreshThumbnail(for window: WindowRecord, size: CGSize) async -> CGImage?
    func beginOverlayCaptureSession() async
    func discardThumbnails(forClosedWindowIDs windowIDs: Set<CGWindowID>) async
    func clearCache() async
    func finishCaptureSession() async
}

extension ThumbnailProviding {
    func cachedThumbnails(for windows: [WindowRecord]) async -> [CGWindowID: CGImage] {
        var images: [CGWindowID: CGImage] = [:]
        for window in windows {
            guard let windowID = window.cgWindowID else { continue }
            if let image = await cachedThumbnail(for: window) {
                images[windowID] = image
            }
        }
        return images
    }
}

@MainActor
protocol OverlayPresenting: AnyObject {
    func show(session: SwitchSession, settings: AppSettings)
    func update(session: SwitchSession, settings: AppSettings)
    func showLoading(settings: AppSettings)
    func beginThumbnailEpoch(_ epoch: UInt64)
    func updateThumbnail(windowID: WindowRecord.ID, image: CGImage, epoch: UInt64, cgWindowID: CGWindowID?)
    func seedThumbnailIfMissing(windowID: WindowRecord.ID, image: CGImage, epoch: UInt64, cgWindowID: CGWindowID?)
    func rememberThumbnails(_ images: [CGWindowID: CGImage])
    func pruneThumbnails(keeping ids: Set<WindowRecord.ID>)
    func discardCachedThumbnails(forClosedWindowIDs windowIDs: Set<CGWindowID>)
    func showMessage(_ message: String)
    func showNoWindows()
    func showActivationFailure(_ message: String)
    func hide()
}

extension OverlayPresenting {
    func rememberThumbnails(_ images: [CGWindowID: CGImage]) {}
    func seedThumbnailIfMissing(
        windowID: WindowRecord.ID,
        image: CGImage,
        epoch: UInt64,
        cgWindowID: CGWindowID?
    ) {}
}
