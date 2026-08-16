import AppKit
import OSLog

@MainActor
final class SwitcherCoordinator {
    private let windows: WindowProviding
    private let activator: WindowActivating
    private let thumbnails: ThumbnailProviding
    private let overlay: OverlayPresenting
    private let settings: AppSettings
    private let waitsForThumbnails: Bool
    private let allowedBundleIdentifiers: Set<String>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tabflow", category: "activation")

    private(set) var session: SwitchSession?
    var initialSelectionOverride: Int?
    var onVisibilityChange: ((Bool) -> Void)?
    var onActivationFailure: ((String) -> Void)?
    var onReadyForScreenshot: (() -> Void)?
    private var openingTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var thumbnailEpoch: UInt64 = 0
    private var captureSessionGeneration: UInt64 = 0
    private var capturedInOverlaySession: Set<CGWindowID> = []
    private var validationTask: Task<Void, Never>?
    private var pendingDirections: [SwitchDirection] = []
    private var isPresentingEmptyState = false
    private var pendingCommit = false
    private var isActivating = false

    var isVisible: Bool { session != nil || openingTask != nil || isPresentingEmptyState }
    var hasSearchQuery: Bool { session?.query.isEmpty == false }

    init(
        windows: WindowProviding,
        activator: WindowActivating,
        thumbnails: ThumbnailProviding,
        overlay: OverlayPresenting,
        settings: AppSettings,
        waitsForThumbnails: Bool = false,
        allowedBundleIdentifiers: Set<String>? = nil
    ) {
        self.windows = windows
        self.activator = activator
        self.thumbnails = thumbnails
        self.overlay = overlay
        self.settings = settings
        self.waitsForThumbnails = waitsForThumbnails
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
    }

    func begin(direction: SwitchDirection) {
        guard !settings.isPaused, !isActivating else { return }
        if session != nil {
            advance(direction)
            return
        }
        guard openingTask == nil else {
            pendingDirections.append(direction)
            return
        }

        openingTask = Task { [weak self] in
            guard let self else { return }
            logger.info(
                "Switcher begin sort=\(settings.sortOrder.rawValue, privacy: .public) selectPrevious=\(settings.selectsPreviousWindow, privacy: .public) group=\(settings.groupsApplications, privacy: .public)"
            )
            let options = WindowQueryOptions(settings: settings)
            let cachedRecords = visibleWindows(await windows.cachedWindows(options: options))
            guard !Task.isCancelled else { return }
            logger.info("Switcher cache \(WindowScanTrace.summary(records: cachedRecords), privacy: .public)")

            if cachedRecords.isEmpty {
                let refreshedRecords = visibleWindows(await windows.refreshWindows(options: options))
                guard !Task.isCancelled else { return }
                openingTask = nil
                logger.info("Switcher refresh-source \(WindowScanTrace.summary(records: refreshedRecords), privacy: .public)")
                guard !refreshedRecords.isEmpty else {
                    pendingDirections.removeAll()
                    isPresentingEmptyState = true
                    onVisibilityChange?(true)
                    overlay.showNoWindows()
                    finishPendingCommitIfNeeded()
                    return
                }
                await showSession(with: refreshedRecords, direction: direction)
                finishPendingCommitIfNeeded()
            } else {
                await showSession(with: cachedRecords, direction: direction)
                openingTask = nil
                finishPendingCommitIfNeeded()
                await Task.yield()
                let refreshedRecords = visibleWindows(await windows.refreshWindows(options: options))
                guard !Task.isCancelled, session != nil, !refreshedRecords.isEmpty else { return }
                logger.info("Switcher refresh-source \(WindowScanTrace.summary(records: refreshedRecords), privacy: .public)")
                replaceWindowsPreservingVisibleOrder(refreshedRecords)
            }

            if waitsForThumbnails {
                await thumbnailTask?.value
                onReadyForScreenshot?()
            }
        }
    }

    private func visibleWindows(_ records: [WindowRecord]) -> [WindowRecord] {
        guard let allowedBundleIdentifiers else { return records }
        return records.filter { record in
            guard let identifier = record.bundleIdentifier else { return false }
            return allowedBundleIdentifiers.contains(identifier)
        }
    }

    private func showSession(
        with records: [WindowRecord],
        direction: SwitchDirection
    ) async {
        let initialIndex = SwitcherInitialSelection.index(
            in: records,
            direction: direction,
            selectsPreviousWindow: settings.selectsPreviousWindow,
            liveCurrentCGWindowID: WindowServerList.onScreenLayer0IDsFrontToBack().first,
            override: initialSelectionOverride
        )

        var newSession = SwitchSession(windows: records, selectedIndex: initialIndex)
        pendingDirections.forEach { newSession.move($0) }
        pendingDirections.removeAll()
        isPresentingEmptyState = false
        session = newSession
        onVisibilityChange?(true)
        logger.info("Switcher show \(WindowScanTrace.sessionSummary(newSession), privacy: .public)")
        if settings.shouldCaptureThumbnails {
            overlay.rememberThumbnails(await thumbnails.cachedThumbnails(for: records))
        }
        overlay.show(session: newSession, settings: settings)
        overlay.pruneThumbnails(keeping: Set(newSession.windows.map(\.id)))
        capturedInOverlaySession.removeAll()
        loadThumbnails(for: newSession, startsNewCaptureSession: true)
        startSelectionValidation()
    }

    private func replaceWindowsPreservingVisibleOrder(_ records: [WindowRecord]) {
        guard let currentSession = session else { return }
        let merged = SwitcherListFreeze.merge(visible: currentSession.windows, refreshed: records)
        let selectedID = currentSession.selectedWindow?.id
        let selectedCGWindowID = currentSession.selectedWindow?.cgWindowID
        var refreshedSession = SwitchSession(
            windows: merged,
            selectedIndex: 0,
            query: currentSession.query
        )
        if let selectedID,
           let index = refreshedSession.filteredWindows.firstIndex(where: { $0.id == selectedID }) {
            refreshedSession.selectedIndex = index
        } else if let selectedCGWindowID,
                  let index = refreshedSession.filteredWindows.firstIndex(where: { $0.cgWindowID == selectedCGWindowID }) {
            refreshedSession.selectedIndex = index
        } else {
            refreshedSession.selectedIndex = min(
                currentSession.selectedIndex,
                max(refreshedSession.filteredWindows.count - 1, 0)
            )
        }
        session = refreshedSession
        logger.info("Switcher freeze-merge \(WindowScanTrace.sessionSummary(refreshedSession), privacy: .public)")
        overlay.update(session: refreshedSession, settings: settings)
        overlay.pruneThumbnails(keeping: Set(refreshedSession.windows.map(\.id)))
        loadThumbnails(for: refreshedSession)
    }

    func advance(_ direction: SwitchDirection) {
        guard var session else {
            begin(direction: direction)
            return
        }
        session.move(direction)
        self.session = session
        overlay.update(session: session, settings: settings)
        loadThumbnails(for: session)
    }

    func moveVertically(_ direction: GridVerticalDirection) {
        guard var session else {
            advance(direction == .down ? .forward : .backward)
            return
        }
        let resolved = OverlayLayoutResolver.resolve(
            settings.overlayLayout,
            windowCount: session.filteredWindows.count,
            cardSize: settings.cardSize,
            screenWidth: NSScreen.main?.visibleFrame.width ?? 1_440
        )
        guard resolved == .grid else {
            advance(direction == .down ? .forward : .backward)
            return
        }
        let columnCount = min(max(session.filteredWindows.count, 1), OverlayLayoutResolver.maximumGridColumns)
        session.moveVertically(direction, columns: columnCount)
        self.session = session
        overlay.update(session: session, settings: settings)
        loadThumbnails(for: session)
    }

    func appendSearch(_ characters: String) {
        guard var session else { return }
        updateSearch(session.query + characters, session: &session)
    }

    func updateSearch(_ query: String) {
        guard var session else { return }
        updateSearch(query, session: &session)
    }

    private func updateSearch(_ query: String, session: inout SwitchSession) {
        session.updateQuery(query)
        self.session = session
        overlay.update(session: session, settings: settings)
        loadThumbnails(for: session)
    }

    func deleteBackward() {
        guard var session, !session.query.isEmpty else { return }
        session.updateQuery(String(session.query.dropLast()))
        self.session = session
        overlay.update(session: session, settings: settings)
    }

    func clearSearch() {
        guard var session, !session.query.isEmpty else { return }
        session.updateQuery("")
        self.session = session
        overlay.update(session: session, settings: settings)
    }

    func selectAndCommit(windowID: WindowRecord.ID) {
        guard var session,
              let index = session.filteredWindows.firstIndex(where: { $0.id == windowID })
        else { return }
        session.selectedIndex = index
        self.session = session
        commit()
    }

    func commit() {
        guard !isActivating else { return }
        switch SwitcherCommitPolicy.action(
            hasSelectedWindow: session?.selectedWindow != nil,
            isOpening: openingTask != nil
        ) {
        case .activate:
            guard let selected = session?.selectedWindow else { return }
            beginActivation(selected)
        case .waitForSession:
            pendingCommit = true
        case .cancel:
            pendingCommit = false
            cancel()
        }
    }

    private func finishPendingCommitIfNeeded() {
        guard pendingCommit else { return }
        commit()
    }

    private func beginActivation(_ selected: WindowRecord) {
        pendingCommit = false
        isActivating = true
        validationTask?.cancel()
        validationTask = nil
        if WindowActivationSequence.shouldHideOverlayBeforeActivation() {
            overlay.hide()
            finishCaptureSession()
        }
        activate(selected)
    }

    private func activate(_ selected: WindowRecord) {
        Task { [weak self] in
            guard let self else { return }
            defer { isActivating = false }
            do {
                try await activator.activate(
                    windowID: selected.id,
                    restoreMinimized: settings.restoresMinimizedWindows
                )
                discardSessionState()
                overlay.hide()
                finishCaptureSession()
                if WindowActivationSequence.shouldRefocusAfterOverlayDismiss() {
                    do {
                        try await activator.activate(
                            windowID: selected.id,
                            restoreMinimized: settings.restoresMinimizedWindows
                        )
                    } catch {
                        logger.error(
                            "Window refocus after overlay dismiss failed pid=\(selected.pid, privacy: .public) error=\(String(describing: error), privacy: .public)"
                        )
                    }
                }
                movePointerIfNeeded(to: selected)
            } catch {
                logger.error("Window activation failed pid=\(selected.pid, privacy: .public) error=\(String(describing: error), privacy: .public)")
                overlay.showActivationFailure(error.localizedDescription)
                startSelectionValidation()
                onActivationFailure?(error.localizedDescription)
            }
        }
    }

    func cancel() {
        pendingCommit = false
        openingTask?.cancel()
        openingTask = nil
        pendingDirections.removeAll()
        closeSession()
    }

    func retryActivation() {
        guard !isActivating, let selected = session?.selectedWindow else { return }
        beginActivation(selected)
    }

    func removeFailedWindow() {
        guard var session else { return }
        let previousWindows = session.windows
        session.removeSelectedWindow()
        if session.windows.isEmpty {
            cancel()
            return
        }
        self.session = session
        overlay.show(session: session, settings: settings)
        overlay.pruneThumbnails(keeping: Set(session.windows.map(\.id)))
        discardClosedThumbnails(from: previousWindows, to: session.windows)
        loadThumbnails(for: session)
    }

    func showFromMenu() {
        begin(direction: .forward)
    }

    private func closeSession() {
        discardSessionState()
        overlay.hide()
        finishCaptureSession()
    }

    private func discardSessionState() {
        validationTask?.cancel()
        validationTask = nil
        session = nil
        isPresentingEmptyState = false
        onVisibilityChange?(false)
    }

    private func finishCaptureSession() {
        let pendingThumbnails = thumbnailTask
        thumbnailTask = nil
        captureSessionGeneration += 1
        let generation = captureSessionGeneration
        thumbnailEpoch += 1
        overlay.beginThumbnailEpoch(thumbnailEpoch)
        Task {
            await pendingThumbnails?.value
            guard generation == captureSessionGeneration else { return }
            await thumbnails.finishCaptureSession()
        }
    }

    private func discardClosedThumbnails(from previous: [WindowRecord], to current: [WindowRecord]) {
        let closed = ThumbnailCacheRetention.closedWindowIDs(
            previous: previous.compactMap(\.cgWindowID),
            current: current.compactMap(\.cgWindowID)
        )
        guard !closed.isEmpty else { return }
        overlay.discardCachedThumbnails(forClosedWindowIDs: closed)
        Task {
            await thumbnails.discardThumbnails(forClosedWindowIDs: closed)
        }
    }

    private func loadThumbnails(
        for session: SwitchSession,
        startsNewCaptureSession: Bool = false
    ) {
        guard settings.shouldCaptureThumbnails else { return }
        let windowsToLoad = ThumbnailLoadPlan.windows(
            in: session.filteredWindows,
            selectedID: session.selectedWindow?.id
        )
        let windowsNeedingCapture = ThumbnailCaptureDeduper.claim(
            windowsToLoad,
            started: &capturedInOverlaySession
        )
        let shouldCapture = !windowsNeedingCapture.isEmpty
        if shouldCapture {
            captureSessionGeneration += 1
            thumbnailEpoch += 1
            overlay.beginThumbnailEpoch(thumbnailEpoch)
        }
        let epoch = thumbnailEpoch
        let previousTask = thumbnailTask
        let thumbnailService = thumbnails
        thumbnailTask = Task { [weak self] in
            if startsNewCaptureSession {
                await thumbnailService.beginOverlayCaptureSession()
            }
            if !shouldCapture {
                await previousTask?.value
            }
            for window in windowsToLoad {
                guard let self else { return }
                if let cached = await thumbnailService.cachedThumbnail(for: window) {
                    self.overlay.seedThumbnailIfMissing(
                        windowID: window.id,
                        image: cached,
                        epoch: epoch,
                        cgWindowID: window.cgWindowID
                    )
                }
            }
            guard shouldCapture else { return }
            await withTaskGroup(of: (WindowRecord, CGImage?).self) { group in
                var iterator = windowsNeedingCapture.makeIterator()
                let limit = min(ThumbnailLoadLimiter.maximumConcurrentCaptures, windowsNeedingCapture.count)

                func startNext() {
                    guard let window = iterator.next() else { return }
                    group.addTask {
                        let image = await thumbnailService.refreshThumbnail(
                            for: window,
                            size: CGSize(width: 320, height: 200)
                        )
                        return (window, image)
                    }
                }

                for _ in 0..<limit {
                    startNext()
                }
                for await (window, image) in group {
                    startNext()
                    guard let image, let self else { continue }
                    let displayID = self.session?.windows.first(where: {
                        $0.cgWindowID != nil && $0.cgWindowID == window.cgWindowID
                    })?.id ?? window.id
                    self.overlay.updateThumbnail(
                        windowID: displayID,
                        image: image,
                        epoch: epoch,
                        cgWindowID: window.cgWindowID
                    )
                }
            }
        }
    }

    private func startSelectionValidation() {
        guard !waitsForThumbnails else { return }
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard let self, var session = self.session,
                      let selected = session.selectedWindow
                else { return }
                let liveIDs = Set(WindowServerList.layer0IDsFrontToBack(onScreenOnly: false))
                let remaining = session.windows.filter { window in
                    guard let windowID = window.cgWindowID else { return true }
                    return liveIDs.contains(windowID)
                }
                if remaining.count != session.windows.count {
                    let selectedID = selected.id
                    let previousWindows = session.windows
                    var rebuilt = SwitchSession(
                        windows: remaining,
                        selectedIndex: 0,
                        query: session.query
                    )
                    if rebuilt.windows.isEmpty {
                        discardClosedThumbnails(from: previousWindows, to: [])
                        cancel()
                        continue
                    }
                    if let index = rebuilt.filteredWindows.firstIndex(where: { $0.id == selectedID }) {
                        rebuilt.selectedIndex = index
                    } else if !rebuilt.filteredWindows.isEmpty {
                        rebuilt.selectedIndex = min(session.selectedIndex, rebuilt.filteredWindows.count - 1)
                    }
                    session = rebuilt
                    self.session = rebuilt
                    overlay.update(session: rebuilt, settings: settings)
                    overlay.pruneThumbnails(keeping: Set(rebuilt.windows.map(\.id)))
                    discardClosedThumbnails(from: previousWindows, to: rebuilt.windows)
                }
                guard let currentSelected = session.selectedWindow else { continue }
                guard await windows.isWindowValid(currentSelected.id) else {
                    let previousWindows = session.windows
                    session.removeSelectedWindow()
                    if session.windows.isEmpty {
                        discardClosedThumbnails(from: previousWindows, to: [])
                        cancel()
                    } else {
                        self.session = session
                        overlay.update(session: session, settings: settings)
                        overlay.pruneThumbnails(keeping: Set(session.windows.map(\.id)))
                        discardClosedThumbnails(from: previousWindows, to: session.windows)
                    }
                    continue
                }
            }
        }
    }

    private func movePointerIfNeeded(to window: WindowRecord) {
        switch settings.pointerMovement {
        case .none:
            return
            case .windowCenter:
            CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: window.frame.midY))
        case .displayCenter:
            let screen = window.displayName.flatMap { name in
                NSScreen.screens.first { $0.localizedName == name }
            } ?? NSScreen.main
            guard let screen else { return }
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            let center = DisplayCoordinateSpace.cgPoint(
                fromAppKitPoint: CGPoint(x: screen.frame.midX, y: screen.frame.midY),
                primaryTop: primaryTop
            )
            CGWarpMouseCursorPosition(center)
        }
    }
}

enum SwitcherInitialSelection {
    static func index(
        in records: [WindowRecord],
        direction: SwitchDirection,
        selectsPreviousWindow: Bool,
        liveCurrentCGWindowID: CGWindowID? = nil,
        override: Int? = nil
    ) -> Int {
        guard !records.isEmpty else { return 0 }
        if let override {
            return min(max(override, 0), records.count - 1)
        }
        let currentIndex = Self.currentIndex(in: records, liveCurrentCGWindowID: liveCurrentCGWindowID)
        if !selectsPreviousWindow || records.count == 1 {
            return currentIndex ?? 0
        }
        if direction == .forward {
            if let currentIndex {
                return records.indices.first { $0 != currentIndex } ?? 0
            }
            if liveCurrentCGWindowID != nil {
                return 0
            }
            return 1
        }
        if let currentIndex {
            return (currentIndex - 1 + records.count) % records.count
        }
        return records.count - 1
    }

    static func currentIndex(
        in records: [WindowRecord],
        liveCurrentCGWindowID: CGWindowID?
    ) -> Int? {
        if let liveCurrentCGWindowID,
           let index = records.firstIndex(where: { $0.cgWindowID == liveCurrentCGWindowID }) {
            return index
        }
        return records.firstIndex(where: \.isCurrent)
    }
}
