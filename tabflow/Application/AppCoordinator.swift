import AppKit
import SwiftUI
import UserNotifications

private enum NotificationUserInfoKey {
    static let activationFailureMessage = "activationFailureMessage"
}

@MainActor
final class AppCoordinator: NSObject {
    private let screenshotMode = ScreenshotModeConfiguration()
    private let settings = AppSettings(store: UserDefaultsSettingsStore())
    private let permissions = PermissionManager()
    private let mruStore = MRUStore()
    private lazy var repository = AccessibilityWindowRepository(mruStore: mruStore)
    private let thumbnailService = ThumbnailService()
    private lazy var overlayController = OverlayController(
        screenshotMode: screenshotMode.isEnabled ? screenshotMode : nil
    )
    private let shortcutEngine = ShortcutEngine()
    private lazy var switcher = SwitcherCoordinator(
        windows: repository,
        activator: repository,
        thumbnails: thumbnailService,
        overlay: overlayController,
        settings: settings,
        waitsForThumbnails: screenshotMode.isEnabled,
        allowedBundleIdentifiers: screenshotMode.isEnabled
            ? ScreenshotModeConfiguration.fixtureBundleIdentifiers
            : nil
    )

    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var permissionRefreshObserver: NSObjectProtocol?
    private var windowRefreshTask: Task<Void, Never>?
    private var permissionWatchTask: Task<Void, Never>?
    private let shortcutProbe = ShortcutProbeState()
    private var pendingActivationFailure: String?

    func start() {
        if screenshotMode.isEnabled {
            screenshotMode.scenario.apply(to: settings)
            NSApp.setActivationPolicy(.regular)
        }
        shortcutEngine.delegate = self
        shortcutEngine.onProbeRecognized = { [weak self] in
            self?.shortcutProbe.recognized = true
        }
        UNUserNotificationCenter.current().delegate = self
        switcher.onVisibilityChange = { [weak self] isVisible in
            self?.shortcutEngine.isSwitcherVisible = isVisible
            self?.repository.setLiveAccessibilityUpdatesEnabled(isVisible)
            self?.updateSearchInputState()
        }
        overlayController.onSelect = { [weak self] windowID in
            self?.switcher.selectAndCommit(windowID: windowID)
        }
        overlayController.onRescan = { [weak self] in
            self?.switcher.showFromMenu()
        }
        overlayController.onOpenWindowScope = { [weak self] in
            self?.switcher.cancel()
            self?.showSettings(section: .windowScope)
        }
        overlayController.onCancel = { [weak self] in
            self?.switcher.cancel()
        }
        overlayController.onRetryActivation = { [weak self] in
            self?.switcher.retryActivation()
        }
        overlayController.onRemoveFailedWindow = { [weak self] in
            self?.switcher.removeFailedWindow()
        }
        overlayController.onOpenPermissions = { [weak self] in
            self?.switcher.cancel()
            self?.showSettings(section: .permissions)
        }
        overlayController.onQueryChange = { [weak self] query in
            self?.switcher.updateSearch(query)
            self?.updateSearchInputState()
        }
        switcher.onActivationFailure = { [weak self] message in
            self?.postActivationFailureNotification(message)
        }
        switcher.onReadyForScreenshot = { [weak self] in
            self?.hideOtherApplicationsForScreenshot()
        }
        settings.onShortcutConfigurationChange = { [weak self] in
            self?.applySettings()
        }
        settings.onThumbnailVisibilityChange = { [weak self] isEnabled in
            guard !isEnabled else { return }
            self?.overlayController.clearThumbnails()
            Task {
                await self?.thumbnailService.clearCache()
            }
        }
        settings.onWindowRefreshIntervalChange = { [weak self] in
            self?.restartWindowRefresh()
        }
        settings.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
        }

        permissions.refresh()
        requestInputMonitoringIfNeeded()
        applySettings()
        applyAppearance()
        setMenuBarVisible(screenshotMode.isEnabled ? false : settings.showsMenuBarIcon)
        observeWorkspaceActivation()
        observePermissionRefresh()
        observeWakeAndDisplayChanges()
        startPermissionWatchIfNeeded()
        startWindowRefreshIfNeeded()

        if screenshotMode.isEnabled {
            switcher.initialSelectionOverride = screenshotMode.initialSelection
            if !settings.onboardingCompleted {
                showOnboarding()
                return
            }
            if screenshotMode.scenario != .settings,
               !permissions.hasCorePermission {
                permissions.requestAccessibility()
                if !permissions.hasCorePermission {
                    return
                }
            }
            if screenshotMode.scenario != .settings {
                requestScreenRecordingIfNeeded()
            }
            DispatchQueue.main.async { [weak self] in
                self?.showScreenshotScenario()
            }
            return
        }

        if !settings.onboardingCompleted {
            showOnboarding()
        } else if settings.checksPermissionsAtLaunch, !permissions.hasCorePermission {
            permissions.requestAccessibility()
        }
    }

    func reopen() {
        showSettings(section: .general)
    }

    func stop() {
        for observer in lifecycleObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        lifecycleObservers.removeAll()
        if let permissionRefreshObserver {
            NotificationCenter.default.removeObserver(permissionRefreshObserver)
            self.permissionRefreshObserver = nil
        }
        shortcutEngine.isProbingShortcut = false
        shortcutEngine.stop()
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
        permissions.cancelPendingAccessibilityRefresh()
        switcher.cancel()
    }

    private func observeWorkspaceActivation() {
        guard lifecycleObservers.isEmpty else { return }
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task {
                await self?.repository.noteApplicationActivated(pid: application.processIdentifier)
            }
        }
        lifecycleObservers.append(activationObserver)

        let windowListUpdateNames: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in windowListUpdateNames {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowCache()
                }
            }
            lifecycleObservers.append(observer)
        }
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowCache()
            }
        }
        lifecycleObservers.append(screenObserver)
    }

    private func observeWakeAndDisplayChanges() {
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]
        for name in names {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.permissions.refresh()
                    self?.refreshWindowCache()
                    self?.restartWindowRefresh()
                }
            }
            lifecycleObservers.append(observer)
        }
    }

    private func observePermissionRefresh() {
        guard permissionRefreshObserver == nil else { return }
        permissionRefreshObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.permissions.refresh()
                self?.startWindowRefreshIfNeeded()
            }
        }
    }

    private func startPermissionWatchIfNeeded() {
        let accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityTrustReading.apiChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleAccessibilityAPIChange()
            }
        }
        lifecycleObservers.append(accessibilityObserver)

        guard permissionWatchTask == nil else { return }
        permissionWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.permissions.refresh()
                if self.permissions.hasCorePermission {
                    self.startWindowRefreshIfNeeded()
                }
                let delay: Duration = self.permissions.hasCorePermission ? .seconds(30) : .seconds(2)
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func handleAccessibilityAPIChange() async {
        await permissions.refreshAfterAccessibilityAPIChange()
        startWindowRefreshIfNeeded()
        if permissions.hasCorePermission {
            applySettings()
        }
    }

    private func refreshWindowCache() {
        repository.scheduleCacheRefresh(options: WindowQueryOptions(settings: settings))
    }

    private func startWindowRefreshIfNeeded() {
        guard permissions.hasCorePermission, windowRefreshTask == nil else { return }
        windowRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !switcher.isVisible {
                    let options = WindowQueryOptions(settings: settings)
                    _ = await repository.refreshWindows(options: options)
                }
                do {
                    try await Task.sleep(for: settings.windowRefreshInterval.duration)
                } catch {
                    return
                }
            }
        }
    }

    private func restartWindowRefresh() {
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        startWindowRefreshIfNeeded()
    }

    private func updateSearchInputState() {
        shortcutEngine.keepsSwitcherOpenForSearchInput = switcher.hasSearchQuery
    }

    private var resolvedAppearance: NSAppearance? {
        switch settings.appearance {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    private func applyAppearance() {
        let appearance = resolvedAppearance
        settingsWindowController?.window?.appearance = appearance
        overlayController.setAppearance(appearance)
    }

    private func applySettings() {
        shortcutEngine.isPaused = settings.isPaused
        shortcutEngine.confirmsOnModifierRelease = settings.confirmsOnModifierRelease
        shortcutEngine.confirmsWithReturn = settings.confirmsWithReturn
        shortcutEngine.supportsArrowNavigation = settings.supportsArrowNavigation
        updateSearchInputState()
        shortcutEngine.shortcut = settings.shortcut
        setMenuBarVisible(settings.showsMenuBarIcon)

        if settings.isPaused {
            shortcutEngine.stop()
            updateStatusIcon()
            return
        }
        do {
            try shortcutEngine.start()
        } catch {
            permissions.setEventTapAvailable(false)
            requestInputMonitoringIfNeeded()
        }
        updateStatusIcon()
    }

    private func requestInputMonitoringIfNeeded() {
        guard settings.onboardingCompleted,
              settings.checksPermissionsAtLaunch,
              permissions.inputMonitoring != .granted,
              !settings.hasRequestedInputMonitoringPermission
        else { return }
        settings.hasRequestedInputMonitoringPermission = true
        permissions.requestInputMonitoring()
    }

    private func requestScreenRecordingIfNeeded() {
        guard settings.shouldCaptureThumbnails,
              permissions.screenRecording != .granted,
              !settings.hasRequestedScreenRecordingPermission
        else { return }
        settings.hasRequestedScreenRecordingPermission = true
        permissions.requestScreenRecording()
    }

    private func showScreenshotScenario() {
        guard screenshotMode.isEnabled else { return }
        switch screenshotMode.scenario {
        case .settings:
            showSettings(section: .appearance)
            hideOtherApplicationsForScreenshot()
        case .windowGrid, .windowPreview, .windowList:
            unhideFixtureApplicationsForScreenshot()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.switcher.showFromMenu()
                self?.shortcutEngine.isSwitcherVisible = self?.switcher.isVisible ?? false
            }
        }
    }

    private func hideOtherApplicationsForScreenshot() {
        guard screenshotMode.isEnabled else { return }
        for application in NSWorkspace.shared.runningApplications {
            hideApplicationIfScreenshotCapture(application)
        }
        NSApp.activate(ignoringOtherApps: true)
        bringScreenshotChromeToFront()
    }

    private func unhideFixtureApplicationsForScreenshot() {
        guard screenshotMode.isEnabled else { return }
        for application in NSWorkspace.shared.runningApplications {
            guard let identifier = application.bundleIdentifier else { continue }
            guard ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains(identifier) else { continue }
            application.unhide()
        }
    }

    private func hideApplicationIfScreenshotCapture(_ application: NSRunningApplication) {
        guard screenshotMode.isEnabled else { return }
        guard application.activationPolicy == .regular else { return }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        application.hide()
    }

    private func bringScreenshotChromeToFront() {
        guard screenshotMode.isEnabled else { return }
        if screenshotMode.scenario != .settings {
            overlayController.bringToFront()
            overlayController.centerOnMainDisplay()
        }
        if let window = settingsWindowController?.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func setMenuBarVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else {
                updateStatusIcon()
                return
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.setAccessibilityLabel(String(localized: "menu.accessibilityLabel"))
            item.menu = NSMenu()
            item.menu?.delegate = self
            statusItem = item
            updateStatusIcon()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func updateStatusIcon() {
        if let symbolName = StatusBarIconPolicy.systemSymbolName(isPaused: settings.isPaused),
           let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: String(localized: "status.paused")
           ) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            statusItem?.button?.image = image
            return
        }
        guard let image = NSImage(named: "StatusBarIcon") else { return }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
    }

    private func showSettings(section: SettingsSection, notice: String? = nil) {
        if settingsWindowController == nil {
            let viewModel = SettingsViewModel(
                settings: settings,
                permissions: permissions,
                onMenuBarVisibilityChanged: { [weak self] visible in
                    self?.setMenuBarVisible(visible)
                },
                onClearThumbnails: { [weak self] in
                    Task {
                        await self?.thumbnailService.clearCache()
                    }
                    self?.overlayController.clearThumbnails()
                }
            )
            let rootView = SettingsRootView(model: viewModel)
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.title = String(localized: "settings.title")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            if screenshotMode.isEnabled {
                window.setContentSize(NSSize(width: 1_200, height: 760))
                window.setFrameOrigin(NSPoint(x: 320, y: 160))
            } else {
                window.setContentSize(NSSize(width: 860, height: 620))
                window.center()
            }
            window.isReleasedWhenClosed = false
            window.appearance = resolvedAppearance
            settingsWindowController = NSWindowController(window: window)
        }
        if let hostingController = settingsWindowController?.contentViewController as? NSHostingController<SettingsRootView> {
            hostingController.rootView.model.selectedSection = section
            if let notice {
                hostingController.rootView.model.activationFailureMessage = notice
                pendingActivationFailure = nil
            } else if section == .general, let pendingActivationFailure {
                hostingController.rootView.model.activationFailureMessage = pendingActivationFailure
                self.pendingActivationFailure = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        if screenshotMode.isEnabled {
            settingsWindowController?.window?.level = .floating
            settingsWindowController?.window?.orderFrontRegardless()
        }
    }

    private func postActivationFailureNotification(_ message: String) {
        pendingActivationFailure = message
        Task {
            let center = UNUserNotificationCenter.current()
            var notificationSettings = await center.notificationSettings()
            if notificationSettings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert])
                notificationSettings = await center.notificationSettings()
            }
            guard notificationSettings.authorizationStatus == .authorized
                || notificationSettings.authorizationStatus == .provisional
            else { return }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.activationFailure.title")
            content.body = message
            content.userInfo = [NotificationUserInfoKey.activationFailureMessage: message]
            let request = UNNotificationRequest(
                identifier: "tabflow.activation-failure",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func showOnboarding() {
        guard onboardingWindowController == nil else {
            onboardingWindowController?.showWindow(nil)
            return
        }
        let rootView = OnboardingView(
            settings: settings,
            permissions: permissions,
            shortcutProbe: shortcutProbe,
            onShortcutProbeActive: { [weak self] isActive in
                self?.shortcutEngine.isProbingShortcut = isActive
            },
            onComplete: { [weak self] in
                self?.shortcutEngine.isProbingShortcut = false
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
            },
            onOpenSettings: { [weak self] in
                self?.showSettings(section: .general)
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = String(localized: "onboarding.title")
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.showWindow(nil)
    }

    @objc private func showSwitcher() {
        guard permissions.hasCorePermission else {
            showSettings(section: .permissions)
            return
        }
        requestScreenRecordingIfNeeded()
        switcher.showFromMenu()
        shortcutEngine.isSwitcherVisible = switcher.isVisible
    }

    @objc private func togglePaused() {
        settings.isPaused.toggle()
    }

    @objc private func openSettings() {
        showSettings(section: .general)
    }

    @objc private func openAbout() {
        showSettings(section: .about)
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}

extension AppCoordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        updateStatusIcon()
        menu.removeAllItems()

        let statusTitle: String
        if settings.isPaused {
            statusTitle = String(localized: "status.paused")
        } else if !permissions.hasCorePermission {
            statusTitle = String(localized: "status.permissionRequired")
        } else if !permissions.eventTapAvailable {
            statusTitle = String(localized: "status.shortcutUnavailable")
        } else {
            statusTitle = String(localized: "status.running")
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(withTitle: String(localized: "menu.showSwitcher"), action: #selector(showSwitcher), keyEquivalent: "")
            .target = self
        let pause = menu.addItem(
            withTitle: settings.isPaused ? String(localized: "menu.resume") : String(localized: "menu.pause"),
            action: #selector(togglePaused),
            keyEquivalent: ""
        )
        pause.target = self
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(.separator())

        menu.addItem(withTitle: String(localized: "menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: String(localized: "menu.about"), action: #selector(openAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "menu.quit"), action: #selector(terminate), keyEquivalent: "q")
            .target = self
    }
}

extension AppCoordinator: ShortcutEngineDelegate {
    func shortcutEngine(_ engine: ShortcutEngine, received action: ShortcutAction) {
        switch action {
        case let .cycle(direction):
            guard permissions.hasCorePermission else {
                showSettings(section: .permissions)
                return
            }
            requestScreenRecordingIfNeeded()
            switcher.begin(direction: direction)
        case .commit:
            switcher.commit()
        case .cancel:
            if switcher.session?.query.isEmpty == false {
                switcher.clearSearch()
            } else {
                switcher.cancel()
            }
        case .deleteBackward:
            switcher.deleteBackward()
        case let .search(characters):
            switcher.appendSearch(characters)
        case let .moveVertical(direction):
            switcher.moveVertically(direction)
        }
        engine.isSwitcherVisible = switcher.isVisible
        updateSearchInputState()
    }

    func shortcutEngineDidChangeAvailability(_ engine: ShortcutEngine, isAvailable: Bool) {
        permissions.setEventTapAvailable(isAvailable)
        updateStatusIcon()
    }
}

extension AppCoordinator: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let message = response.notification.request.content.userInfo[NotificationUserInfoKey.activationFailureMessage] as? String
        completionHandler()
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let message else { return }
        Task { @MainActor [weak self] in
            self?.showSettings(section: .general, notice: message)
        }
    }
}
