import CoreGraphics
import ScreenCaptureKit

nonisolated enum ThumbnailCaptureSize {
    static let maximumPixelDimension: CGFloat = 400

    static func pixelSize(
        for windowSize: CGSize,
        fitting pointSize: CGSize,
        backingScale: CGFloat = 2
    ) -> CGSize {
        let bounds = CGSize(
            width: max(pointSize.width * backingScale, 1),
            height: max(pointSize.height * backingScale, 1)
        )
        let scale = min(
            bounds.width / max(windowSize.width, 1),
            bounds.height / max(windowSize.height, 1)
        )
        var width = max((windowSize.width * scale).rounded(), 1)
        var height = max((windowSize.height * scale).rounded(), 1)
        let longest = max(width, height)
        if longest > maximumPixelDimension {
            let factor = maximumPixelDimension / longest
            width = max((width * factor).rounded(), 1)
            height = max((height * factor).rounded(), 1)
        }
        return CGSize(width: width, height: height)
    }
}

nonisolated enum ThumbnailRasterizer {
    static func constrained(_ image: CGImage, fitting pointSize: CGSize) -> CGImage {
        let target = ThumbnailCaptureSize.pixelSize(
            for: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)),
            fitting: pointSize
        )
        guard CGFloat(image.width) > target.width + 0.5
            || CGFloat(image.height) > target.height + 0.5
        else {
            return image
        }
        guard let context = CGContext(
            data: nil,
            width: Int(target.width),
            height: Int(target.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        return context.makeImage() ?? image
    }
}

nonisolated enum ThumbnailLoadLimiter {
    static let maximumConcurrentCaptures = 3
    static let shareableContentReuseInterval: TimeInterval = 2
    static let maximumCachedThumbnails = 128
    static let maximumCachedBytes = 24 * 1_024 * 1_024
}

nonisolated enum ThumbnailCapturePersistence {
    static func shouldReplaceCachedEntry(existingGeneration: UInt64, incomingGeneration: UInt64) -> Bool {
        incomingGeneration >= existingGeneration
    }
}

actor ThumbnailService: ThumbnailProviding {
    private struct CacheEntry {
        let image: CGImage
        let capturedAt: Date
        let byteCount: Int
        let generation: UInt64
    }

    private var entries: [CGWindowID: CacheEntry] = [:]
    private var inflightCaptures: [CGWindowID: Task<CGImage?, Never>] = [:]
    private var captureGeneration: UInt64 = 0
    private var shareableContentTask: Task<SCShareableContent, Error>?
    private var shareableContent: SCShareableContent?
    private var shareableContentCapturedAt: Date?

    func cachedThumbnail(for window: WindowRecord) -> CGImage? {
        guard let windowID = window.cgWindowID else { return nil }
        return entries[windowID]?.image
    }

    func cachedThumbnails(for windows: [WindowRecord]) -> [CGWindowID: CGImage] {
        var images: [CGWindowID: CGImage] = [:]
        for window in windows {
            guard let windowID = window.cgWindowID, let image = entries[windowID]?.image else {
                continue
            }
            images[windowID] = image
        }
        return images
    }

    func beginOverlayCaptureSession() {
        captureGeneration += 1
        inflightCaptures.removeAll()
    }

    func refreshThumbnail(for window: WindowRecord, size: CGSize) async -> CGImage? {
        guard let windowID = window.cgWindowID else { return nil }
        if let inflight = inflightCaptures[windowID] {
            return await inflight.value
        }

        let generation = captureGeneration
        let task = Task<CGImage?, Never> {
            await self.captureAndStore(windowID: windowID, size: size, generation: generation)
        }
        inflightCaptures[windowID] = task
        let image = await task.value
        inflightCaptures[windowID] = nil
        return image
    }

    private func captureAndStore(
        windowID: CGWindowID,
        size: CGSize,
        generation: UInt64
    ) async -> CGImage? {
        let previous = entries[windowID]?.image
        guard let content = try? await shareableContentSnapshot(),
              let captured = await Self.captureImage(windowID: windowID, size: size, content: content)
        else { return previous }
        let image = ThumbnailRasterizer.constrained(captured, fitting: size)
        store(image, for: windowID, generation: generation)
        return image
    }

    func discardThumbnails(forClosedWindowIDs windowIDs: Set<CGWindowID>) {
        for windowID in windowIDs {
            entries.removeValue(forKey: windowID)
        }
    }

    func clearCache() {
        entries.removeAll()
        releaseShareableContent()
    }

    func finishCaptureSession() async {
        let pending = inflightCaptures
        for task in pending.values {
            _ = await task.value
        }
        releaseShareableContent()
    }

    private func store(_ image: CGImage, for windowID: CGWindowID, generation: UInt64) {
        if let existing = entries[windowID],
           !ThumbnailCapturePersistence.shouldReplaceCachedEntry(
            existingGeneration: existing.generation,
            incomingGeneration: generation
           ) {
            return
        }
        entries[windowID] = CacheEntry(
            image: image,
            capturedAt: .now,
            byteCount: image.bytesPerRow * image.height,
            generation: generation
        )
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while entries.count > ThumbnailLoadLimiter.maximumCachedThumbnails
            || totalCachedBytes > ThumbnailLoadLimiter.maximumCachedBytes
        {
            guard let oldest = entries.min(by: { $0.value.capturedAt < $1.value.capturedAt }) else {
                return
            }
            entries.removeValue(forKey: oldest.key)
        }
    }

    private var totalCachedBytes: Int {
        entries.values.reduce(0) { $0 + $1.byteCount }
    }

    private func releaseShareableContent() {
        shareableContent = nil
        shareableContentCapturedAt = nil
        shareableContentTask = nil
    }

    private func shareableContentSnapshot() async throws -> SCShareableContent {
        if let shareableContent,
           let shareableContentCapturedAt,
           Date.now.timeIntervalSince(shareableContentCapturedAt) < ThumbnailLoadLimiter.shareableContentReuseInterval {
            return shareableContent
        }
        if let shareableContentTask {
            return try await shareableContentTask.value
        }

        let task = Task { try await SCShareableContent.current }
        shareableContentTask = task
        do {
            let content = try await task.value
            shareableContent = content
            shareableContentCapturedAt = .now
            shareableContentTask = nil
            return content
        } catch {
            shareableContentTask = nil
            throw error
        }
    }

    private static func captureImage(
        windowID: CGWindowID,
        size: CGSize,
        content: SCShareableContent
    ) async -> CGImage? {
        guard let shareableWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
        let captureSize = ThumbnailCaptureSize.pixelSize(
            for: shareableWindow.frame.size,
            fitting: size
        )
        let configuration = SCStreamConfiguration()
        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}
