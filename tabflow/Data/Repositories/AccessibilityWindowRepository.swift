import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

@MainActor
final class AccessibilityWindowRepository: WindowProviding, WindowActivating {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tabflow", category: "window-scan")
    private let mruStore: MRUStore
    private var accessibleWindows: [WindowRecord.ID: ScannedAccessibleWindow] = [:]
    private var generations: [pid_t: [(element: AXUIElement, generation: UInt64)]] = [:]
    private var nextGeneration: UInt64 = 1
    private var cachedOptions: WindowQueryOptions?
    private var cachedRecords: [WindowRecord] = []
    private var cacheRefreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var accessibilityObservers: [pid_t: RegisteredAccessibilityObserver] = [:]
    private var liveAccessibilityUpdatesEnabled = false
    private let iconCache = ApplicationIconCache()

    init(mruStore: MRUStore) {
        self.mruStore = mruStore
    }

    func setLiveAccessibilityUpdatesEnabled(_ enabled: Bool) {
        guard liveAccessibilityUpdatesEnabled != enabled else { return }
        liveAccessibilityUpdatesEnabled = enabled
        if !enabled {
            removeAllAccessibilityObservers()
        }
    }

    func cachedWindows(options: WindowQueryOptions) -> [WindowRecord] {
        CachedWindowFilter.apply(cachedRecords, options: options)
    }

    func noteApplicationActivated(pid: pid_t) async {
        let focused = await WindowScanRuntime.runOffMain {
            AXWindowActions.focusedElement(pid: pid, timeout: 0.05)
        }
        if let focused,
           let focusedWindow = accessibleWindows.first(where: {
               AXElementComparison.isEqual($0.value.element, focused.element)
           })?.value {
            await mruStore.recordFocus(focusedWindow.record)
        } else {
            await recordFrontmostWindow(for: pid)
        }
        guard let cachedOptions else { return }
        await refreshCachedFocusedWindow(options: cachedOptions)
    }

    private func recordFrontmostWindow(for pid: pid_t) async {
        let snapshots = windowServerSnapshots()
        guard let cgWindowID = RecentWindowOrder.frontmostCGWindowID(
            for: pid,
            frontToBackCGWindowIDs: snapshots.filter { $0.isOnScreen && $0.layer == 0 }.map(\.id),
            snapshots: snapshots.map { ($0.id, $0.pid) }
        ) else { return }
        if let record = accessibleWindows.values.first(where: { $0.record.cgWindowID == cgWindowID })?.record
            ?? cachedRecords.first(where: { $0.cgWindowID == cgWindowID }) {
            await mruStore.recordFocus(record)
        } else {
            await mruStore.recordFocus(cgWindowID: cgWindowID)
        }
    }

    func scheduleCacheRefresh(options: WindowQueryOptions? = nil) {
        let resolved = options ?? cachedOptions
        guard let resolved else { return }
        cacheRefreshTask?.cancel()
        cacheRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            _ = await self.refreshWindows(options: resolved)
        }
    }

    private func synchronizeAccessibilityObservers(with applications: [ApplicationSnapshot]) {
        guard liveAccessibilityUpdatesEnabled else {
            removeAllAccessibilityObservers()
            return
        }
        let activePIDs = Set(applications.map(\.pid))
        let staleObservers = accessibilityObservers.filter { !activePIDs.contains($0.key) }
        for (pid, observer) in staleObservers {
            removeObserver(observer, pid: pid)
        }

        for application in applications where accessibilityObservers[application.pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(application.pid, accessibilityObserverCallback, &observer) == .success,
                  let observer else { continue }
            let element = AXUIElementCreateApplication(application.pid)
            let context = Unmanaged.passUnretained(self).toOpaque()
            var registered = false
            for notification in AccessibilityObserverPolicy.liveNotifications {
                if AXObserverAddNotification(observer, element, notification, context) == .success {
                    registered = true
                }
            }
            guard registered else { continue }
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            accessibilityObservers[application.pid] = RegisteredAccessibilityObserver(
                observer: observer,
                application: element
            )
        }
    }

    private func removeObserver(_ observer: RegisteredAccessibilityObserver, pid: pid_t) {
        for notification in AccessibilityObserverPolicy.liveNotifications {
            AXObserverRemoveNotification(observer.observer, observer.application, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer.observer),
            .commonModes
        )
        accessibilityObservers[pid] = nil
    }

    private func removeAllAccessibilityObservers() {
        let observers = accessibilityObservers
        for (pid, observer) in observers {
            removeObserver(observer, pid: pid)
        }
    }

    func handleAccessibilityNotification(pid: pid_t, notification: String) {
        guard AccessibilityObserverPolicy.handlesNotification(
            notification,
            liveUpdatesEnabled: liveAccessibilityUpdatesEnabled
        ) else { return }
        if notification == kAXFocusedWindowChangedNotification as String {
            Task { await noteApplicationActivated(pid: pid) }
        } else {
            scheduleCacheRefresh()
        }
    }

    private func refreshCachedFocusedWindow(options: WindowQueryOptions) async {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }

        let focused = await WindowScanRuntime.runOffMain {
            AXWindowActions.focusedElement(pid: pid, timeout: 0.05)
        }
        guard let focused,
              let focusedWindow = accessibleWindows.first(where: {
                  AXElementComparison.isEqual($0.value.element, focused.element)
              })?.value else { return }

        await mruStore.recordFocus(focusedWindow.record)
        await reorderCachedRecords(using: options, current: focusedWindow.record)
    }

    private func reorderCachedRecords(using options: WindowQueryOptions, current: WindowRecord) async {
        let usageIDs = usageOrderIDs(from: windowServerSnapshots())
        var updated = cachedRecords.map { $0.withCurrentState($0.id == current.id) }
        updated = WindowUsageOrder.markedCurrent(updated, frontToBackCGWindowIDs: usageIDs)
        updated = await mruStore.order(
            updated,
            frontToBackCGWindowIDs: usageIDs
        )
        if !options.includesCurrentWindow {
            updated.removeAll(where: \.isCurrent)
        }
        cachedRecords = updated
        if WindowDiagnosticLogging.isEnabled {
            logger.info("Window cache reordered \(WindowScanTrace.summary(records: updated), privacy: .public)")
        }
    }

    func refreshWindows(options: WindowQueryOptions) async -> [WindowRecord] {
        refreshGeneration += 1
        let generation = refreshGeneration
        let screens = Self.screenSnapshots()
        let cgWindows = windowServerSnapshots()
        let applications = collectApplications(windowPIDs: Set(cgWindows.map(\.pid)))
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        synchronizeAccessibilityObservers(with: applications)

        if WindowDiagnosticLogging.isEnabled {
            logger.info(
                "Window scan context apps=\(applications.count, privacy: .public) cgWindows=\(cgWindows.count, privacy: .public) axTrusted=\(AXIsProcessTrusted(), privacy: .public)"
            )
        }

        let generationState = AXGenerationState(generations: generations, nextGeneration: nextGeneration)
        let scanResult = await WindowScanRuntime.runOffMain {
            WindowListScanner.scan(
                applications: applications,
                cgWindows: cgWindows,
                screens: screens,
                options: options,
                frontmostPID: frontmostPID,
                selfPID: selfPID,
                generationState: generationState
            )
        }
        generations = scanResult.generationState.generations
        nextGeneration = scanResult.generationState.nextGeneration
        let discovered = scanResult.windows

        pruneGenerations(liveWindows: discovered)
        iconCache.retainKeys(Set(applications.map(\.iconCacheKey)))
        accessibleWindows = Dictionary(uniqueKeysWithValues: discovered.map { ($0.record.id, $0) })
        let usageIDs = usageOrderIDs(from: cgWindows)
        var records = WindowUsageOrder.markedCurrent(
            discovered.map(\.record),
            frontToBackCGWindowIDs: usageIDs
        )
        if options.currentDisplayOnly {
            let currentDisplayName = records.first(where: \.isCurrent)?.displayName
                ?? screens.first(where: \.isMain)?.localizedName
            records.removeAll { $0.displayName != currentDisplayName }
            records = WindowUsageOrder.markedCurrent(records, frontToBackCGWindowIDs: usageIDs)
        }
        await mruStore.discardMissing(from: records)
        if let current = records.first(where: \.isCurrent) {
            await mruStore.recordFocus(current)
        }
        records = await mruStore.order(
            records,
            frontToBackCGWindowIDs: usageIDs
        )
        if !options.includesCurrentWindow {
            records.removeAll(where: \.isCurrent)
        }
        let sortedRecords = WindowRecordSorting.sorted(records, using: options.sortOrder)

        let duplicateIDs = WindowScanTrace.duplicateCGWindowIDs(in: sortedRecords)
        if WindowDiagnosticLogging.isEnabled {
            let liveZOrder = WindowScanTrace.liveZOrderSummary(
                cgWindows.filter { $0.isOnScreen && $0.layer == 0 }.map {
                    WindowServerList.OnScreenWindow(id: $0.id, pid: $0.pid, ownerName: "")
                }
            )
            logger.info(
                "Window scan options sort=\(options.sortOrder.rawValue, privacy: .public) includeCurrent=\(options.includesCurrentWindow, privacy: .public)"
            )
            logger.info(
                "Window scan z-order \(liveZOrder, privacy: .public)"
            )
            logger.info(
                "Window scan result \(WindowScanTrace.summary(records: sortedRecords), privacy: .private)"
            )
        }
        if !duplicateIDs.isEmpty {
            logger.error(
                "Window scan assigned duplicate CGWindowIDs \(duplicateIDs.map(String.init).joined(separator: ","), privacy: .public)"
            )
        }
        if generation == refreshGeneration {
            cachedOptions = options
            cachedRecords = records
        }
        return sortedRecords
    }

    func isWindowValid(_ windowID: WindowRecord.ID) async -> Bool {
        guard let window = accessibleWindows[windowID] else { return false }
        guard let element = window.element else {
            guard let cgWindowID = window.record.cgWindowID else { return false }
            return windowServerSnapshots().contains { $0.id == cgWindowID }
        }
        let boxed = AXTransfer(element: element)
        let isValid = await WindowScanRuntime.runOffMain {
            AXWindowActions.isValid(boxed.element)
        }
        if !isValid {
            accessibleWindows[windowID] = nil
            cachedRecords.removeAll { $0.id == windowID }
        }
        return isValid
    }

    func activate(windowID: WindowRecord.ID, restoreMinimized: Bool) async throws {
        guard let window = accessibleWindows[windowID] else {
            let known = cachedRecords.first { $0.id == windowID }
            throw WindowActivationError.windowClosed(
                applicationName: known?.applicationName ?? String(localized: "application.unknown"),
                title: known?.displayTitle ?? String(localized: "window.untitled")
            )
        }
        let record = window.record
        let isOwnProcess = OwnProcessWindowActivation.applies(to: record.pid)

        if restoreMinimized && record.isMinimized {
            if isOwnProcess {
                restoreOwnWindowIfNeeded(record)
            } else if let element = window.element {
                let boxed = AXTransfer(element: element)
                await WindowScanRuntime.runOffMain {
                    AXWindowActions.restoreMinimized(boxed.element)
                }
            }
        }

        guard let application = NSRunningApplication(processIdentifier: record.pid),
              !WindowActivationPolicy.processHasExited(application)
        else {
            throw WindowActivationError.applicationExited(applicationName: record.applicationName)
        }
        if application.isHidden {
            application.unhide()
        }
        let targetElement: AXUIElement?
        if isOwnProcess {
            targetElement = nil
        } else if let element = window.element {
            targetElement = element
        } else {
            targetElement = await matchingWindowElement(for: record)
        }

        let isFrontmost = application.isActive
            || NSWorkspace.shared.frontmostApplication?.processIdentifier == record.pid
        let hasWindowID = WindowServerFocusPolicy.canFocusSpecificWindow(cgWindowID: record.cgWindowID)
        var activateReturned = true
        if WindowServerFocusPolicy.shouldActivateApplication(
            hasWindowID: hasWindowID,
            isFrontmost: isFrontmost,
            isHidden: application.isHidden
        ) {
            activateReturned = application.activate()
        }
        var focusedByWindowServer = false
        if let windowID = record.cgWindowID {
            focusedByWindowServer = await WindowServerFocus.focus(
                pid: record.pid,
                windowID: windowID,
                currentlyFrontWindowID: WindowServerList.frontmostLayer0WindowID(for: record.pid)
            )
        }

        var raiseError: AXError?
        if isOwnProcess {
            raiseError = raiseOwnWindow(record)
        } else if let targetElement {
            raiseError = await raiseWindow(targetElement, pid: record.pid)
        }
        var raiseAttempts = 1
        var outcome = await activationOutcome(
            record: record,
            application: application,
            targetElement: targetElement,
            activateReturned: activateReturned,
            raiseError: raiseError
        )
        while WindowRaiseRetryPolicy.shouldRetry(
            targetConfirmed: outcome.targetConfirmed,
            raiseAttemptsUsed: raiseAttempts
        ) {
            try await Task.sleep(for: WindowRaiseRetryPolicy.delay)
            if let windowID = record.cgWindowID {
                focusedByWindowServer = await WindowServerFocus.focus(
                    pid: record.pid,
                    windowID: windowID
                )
            }
            if isOwnProcess {
                raiseError = raiseOwnWindow(record)
            } else if let targetElement {
                raiseError = await raiseWindow(targetElement, pid: record.pid)
            }
            raiseAttempts += 1
            outcome = await activationOutcome(
                record: record,
                application: application,
                targetElement: targetElement,
                activateReturned: activateReturned,
                raiseError: raiseError
            )
        }

        if !outcome.targetConfirmed {
            let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            logger.error(
                "Window activation failed app=\(record.applicationName, privacy: .public) pid=\(record.pid, privacy: .public) title=\(record.title, privacy: .private) activateReturned=\(activateReturned, privacy: .public) windowServerFocus=\(focusedByWindowServer, privacy: .public) raise=\(raiseError?.diagnosticName ?? "none", privacy: .public) front=\(outcome.windowIsFrontForProcess, privacy: .public) focused=\(outcome.focusedWindowMatches, privacy: .public) sandboxed=\(sandboxed, privacy: .public)"
            )
            throw WindowActivationError.couldNotBringToFront(
                applicationName: record.applicationName,
                title: record.displayTitle,
                reason: WindowActivationPolicy.failureReason(
                    didBringApplicationForward: outcome.didBringApplicationForward,
                    raiseError: raiseError
                )
            )
        }

        await mruStore.recordFocus(record)
        if let cachedOptions {
            Task { [weak self] in
                await self?.reorderCachedRecords(using: cachedOptions, current: record)
            }
        }
    }

    private func raiseWindow(_ element: AXUIElement, pid: pid_t) async -> AXError {
        let boxed = AXTransfer(element: element)
        return await WindowScanRuntime.runOffMain {
            AXWindowActions.raise(boxed.element, pid: pid)
        }
    }

    private func raiseOwnWindow(_ record: WindowRecord) -> AXError {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = ownNSWindow(matching: record) else {
            return .invalidUIElement
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return .success
    }

    private func restoreOwnWindowIfNeeded(_ record: WindowRecord) {
        guard let window = ownNSWindow(matching: record), window.isMiniaturized else { return }
        window.deminiaturize(nil)
    }

    private func ownWindowIsKeyOrMain(_ record: WindowRecord) -> Bool {
        guard let window = ownNSWindow(matching: record) else { return false }
        return window.isKeyWindow || window.isMainWindow
    }

    private func ownNSWindow(matching record: WindowRecord) -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            OwnApplicationWindowMatch.isCandidate(
                styleMaskContainsTitled: window.styleMask.contains(.titled),
                isSheet: window.isSheet
            )
        }
        guard let index = OwnApplicationWindowMatch.index(
            windowNumbers: candidates.map(\.windowNumber),
            titles: candidates.map(\.title),
            cgWindowID: record.cgWindowID,
            recordTitle: record.title
        ) else {
            return nil
        }
        return candidates[index]
    }

    private func activationOutcome(
        record: WindowRecord,
        application: NSRunningApplication,
        targetElement: AXUIElement?,
        activateReturned: Bool,
        raiseError: AXError?
    ) async -> (
        targetConfirmed: Bool,
        didBringApplicationForward: Bool,
        focusedWindowMatches: Bool,
        windowIsFrontForProcess: Bool
    ) {
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == record.pid
        let didBringApplicationForward = WindowActivationPolicy.didBringApplicationForward(
            activateReturned: activateReturned,
            isActive: application.isActive,
            isFrontmost: isFrontmost
        )
        let focusedWindowMatches: Bool
        if OwnProcessWindowActivation.applies(to: record.pid) {
            focusedWindowMatches = ownWindowIsKeyOrMain(record)
        } else if let targetElement {
            let boxed = AXTransfer(element: targetElement)
            focusedWindowMatches = await WindowScanRuntime.runOffMain {
                AXWindowActions.focusedWindow(is: boxed.element, pid: record.pid)
            }
        } else {
            focusedWindowMatches = false
        }
        let windowIsFrontForProcess = WindowFrontVerification.isFront(
            targetID: record.cgWindowID,
            frontmostIDForProcess: WindowServerList.frontmostLayer0WindowID(for: record.pid)
        )
        let targetConfirmed = WindowActivationPolicy.didActivateTargetWindow(
            didBringApplicationForward: didBringApplicationForward,
            raiseSucceeded: raiseError == .success,
            focusedWindowMatches: focusedWindowMatches,
            windowIsFrontForProcess: windowIsFrontForProcess,
            canVerifyWindowFront: record.cgWindowID != nil
        )
        return (
            targetConfirmed,
            didBringApplicationForward,
            focusedWindowMatches,
            windowIsFrontForProcess
        )
    }

    private func matchingWindowElement(for record: WindowRecord) async -> AXUIElement? {
        for attempt in 1...AXActivationRetry.attempts {
            let result = await WindowScanRuntime.runOffMain {
                AXWindowActions.matchingWindow(for: record)
            }
            if let matched = result.element {
                return matched
            }
            if AXActivationRetry.shouldRetry(windowsFound: result.windowCount, attempt: attempt) {
                try? await Task.sleep(for: AXActivationRetry.delay)
            }
        }
        return nil
    }

    private func pruneGenerations(liveWindows: [ScannedAccessibleWindow]) {
        generations = AXElementGenerationIndex.pruned(
            generations,
            liveWindows: liveWindows.compactMap { window in
                guard let element = window.element else { return nil }
                return (pid: window.record.pid, element: element)
            }
        )
    }

    @MainActor
    private static func screenSnapshots() -> [ScreenSnapshot] {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.map {
            ScreenSnapshot(
                frame: DisplayCoordinateSpace.cgFrame(fromAppKitFrame: $0.frame, primaryTop: primaryTop),
                localizedName: $0.localizedName,
                isMain: $0 == NSScreen.main
            )
        }
    }

    @MainActor
    private func collectApplications(windowPIDs: Set<pid_t>) -> [ApplicationSnapshot] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let pids = WindowProcessEnumerator.pidsToInspect(
            workspacePIDs: Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)),
            windowPIDs: windowPIDs,
            excluding: selfPID
        ).union([selfPID])
        return pids.sorted().compactMap { pid in
            guard let application = NSRunningApplication(processIdentifier: pid),
                  !application.isTerminated
            else { return nil }
            let isSelf = pid == selfPID
            guard isSelf || application.activationPolicy == .regular else { return nil }
            return ApplicationSnapshot(
                pid: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                name: application.localizedName ?? String(localized: "application.unknown"),
                iconData: iconCache.data(for: application),
                isHidden: application.isHidden
            )
        }
    }

    private func usageOrderIDs(from snapshots: [CGWindowSnapshot]) -> [CGWindowID] {
        WindowUsageOrder.idsFrontToBack(
            onScreen: WindowServerList.onScreenLayer0IDsFrontToBack(),
            remaining: snapshots.filter { $0.layer == 0 }.map(\.id)
        )
    }

    private func windowServerSnapshots() -> [CGWindowSnapshot] {
        autoreleasepool {
            guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
            else { return [] }

            return raw.compactMap { info in
                guard let idValue = info[kCGWindowNumber as String] as? NSNumber,
                      let pidValue = info[kCGWindowOwnerPID as String] as? NSNumber,
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
                else { return nil }
                return CGWindowSnapshot(
                    id: idValue.uint32Value,
                    pid: pidValue.int32Value,
                    title: info[kCGWindowName as String] as? String ?? "",
                    frame: frame,
                    isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                    alpha: CGFloat((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1),
                    layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                )
            }
        }
    }
}

enum AXElementGenerationIndex {
    static func pruned(
        _ generations: [pid_t: [(element: AXUIElement, generation: UInt64)]],
        liveWindows: [(pid: pid_t, element: AXUIElement)]
    ) -> [pid_t: [(element: AXUIElement, generation: UInt64)]] {
        var liveElementsByPID: [pid_t: [AXUIElement]] = [:]
        for window in liveWindows {
            liveElementsByPID[window.pid, default: []].append(window.element)
        }
        let livePIDs = Set(liveElementsByPID.keys)
        var next: [pid_t: [(element: AXUIElement, generation: UInt64)]] = [:]
        for (pid, entries) in generations where livePIDs.contains(pid) {
            let live = liveElementsByPID[pid] ?? []
            let kept = entries.filter { entry in
                live.contains { CFEqual($0, entry.element) }
            }
            if !kept.isEmpty {
                next[pid] = kept
            }
        }
        return next
    }
}

enum AXElementComparison {
    static func isEqual(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        guard let lhs, let rhs else { return false }
        return CFEqual(lhs, rhs)
    }
}

private struct RegisteredAccessibilityObserver {
    let observer: AXObserver
    let application: AXUIElement
}

nonisolated enum ApplicationIconRasterizer {
    static let pixelDimension = 64

    static func pngData(from image: NSImage) -> Data? {
        var proposed = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(pixelDimension),
            height: CGFloat(pixelDimension)
        )
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.clear(CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension))
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension)
        )
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}

@MainActor
final class ApplicationIconCache {
    private var dataByKey: [String: Data] = [:]

    func data(for application: NSRunningApplication) -> Data? {
        let key = application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
        if let cached = dataByKey[key] {
            return cached
        }
        guard let icon = application.icon, let data = ApplicationIconRasterizer.pngData(from: icon) else {
            return nil
        }
        dataByKey[key] = data
        return data
    }

    func retainKeys(_ keys: Set<String>) {
        dataByKey = dataByKey.filter { keys.contains($0.key) }
    }
}

nonisolated(unsafe) private let accessibilityObserverCallback: AXObserverCallback = { _, element, notification, context in
    guard let context else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    let repository = Unmanaged<AccessibilityWindowRepository>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            repository.handleAccessibilityNotification(pid: pid, notification: name)
        }
    } else {
        Task { @MainActor in
            repository.handleAccessibilityNotification(pid: pid, notification: name)
        }
    }
}
