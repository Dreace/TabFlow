import SwiftUI

struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .safeAreaInset(edge: .bottom) {
                statusFooter
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Form {
                content
            }
            .formStyle(.grouped)
            .navigationTitle(model.selectedSection.title)
        }
        .frame(minWidth: 780, minHeight: 560)
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: model.selectedSection) { _, section in
            if section == .permissions {
                model.refreshPermissions()
            }
            if section == .shortcuts {
                model.refreshShortcutConflictProbe()
            }
        }
        .onChange(of: model.settings.shortcut) { _, _ in
            model.refreshShortcutConflictProbe()
        }
        .alert("settings.reset.confirm.title", isPresented: $model.confirmsReset) {
            Button("action.cancel", role: .cancel) {}
            Button("settings.reset.action", role: .destructive) {
                model.settings.restoreDefaults()
            }
        } message: {
            Text("settings.reset.confirm.message")
        }
        .alert("settings.menuBar.hide.title", isPresented: $model.confirmsHideMenuBar) {
            Button("action.cancel", role: .cancel) {}
            Button("settings.menuBar.hide.action") {
                model.confirmHideMenuBar()
            }
        } message: {
            Text("settings.menuBar.hide.message")
        }
        .alert("error.generic.title", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("action.ok") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $model.showsDiagnosticPreview) {
            DiagnosticExportView(
                report: model.diagnosticReport,
                onExport: model.exportDiagnosticReport
            )
        }
        .sheet(item: $model.activeAboutSheet) { _ in
            AboutInformationView()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .general: general
        case .shortcuts: shortcuts
        case .appearance: appearance
        case .windowScope: windowScope
        case .behavior: behavior
        case .permissions: permissions
        case .privacy: privacy
        case .about: about
        }
    }

    private var general: some View {
        Group {
            if let activationFailureMessage = model.activationFailureMessage {
                Section("error.activationFailed") {
                    Label("error.activationFailed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(activationFailureMessage)
                    Button("overlay.activationFailed.permissions") {
                        model.activationFailureMessage = nil
                        model.selectedSection = .permissions
                    }
                    Button("action.ok") {
                        model.activationFailureMessage = nil
                    }
                }
            }
            Section {
                Toggle("settings.general.launchAtLogin", isOn: Binding(
                    get: { model.isLaunchAtLoginEnabled },
                    set: model.setLaunchAtLogin
                ))
                Toggle("settings.general.showMenuBar", isOn: Binding(
                    get: { model.settings.showsMenuBarIcon },
                    set: model.setMenuBarVisible
                ))
                Toggle("settings.general.checkPermissions", isOn: $model.settings.checksPermissionsAtLaunch)
                Toggle("settings.general.pause", isOn: $model.settings.isPaused)
            }
            Section {
                Button("settings.reset.action", role: .destructive) {
                    model.confirmsReset = true
                }
            }
        }
    }

    private var shortcuts: some View {
        Group {
            Section("settings.shortcuts.primary") {
                LabeledContent("settings.shortcuts.forward") {
                    ShortcutRecorder(
                        shortcut: $model.settings.shortcut,
                        onRecordingChange: model.setShortcutRecording
                    )
                        .frame(width: 150)
                }
                LabeledContent(
                    "settings.shortcuts.backward",
                    value: model.settings.shortcut.isConfigured
                        ? model.settings.shortcut.displayName + " ⇧"
                        : String(localized: "shortcut.none")
                )
                if let shortcutStatus = model.shortcutStatus {
                    Label(
                        shortcutStatus.text,
                        systemImage: shortcutStatus.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: shortcutStatus.tint))
                }
            }
            Section {
                Toggle("settings.shortcuts.confirmOnRelease", isOn: $model.settings.confirmsOnModifierRelease)
                Toggle("settings.shortcuts.confirmWithReturn", isOn: $model.settings.confirmsWithReturn)
                Toggle("settings.shortcuts.arrows", isOn: $model.settings.supportsArrowNavigation)
                LabeledContent("settings.shortcuts.escape", value: String(localized: "settings.alwaysEnabled"))
            }
        }
    }

    private var appearance: some View {
        Group {
            Section {
                AppearancePreviewView(settings: model.settings)
                Picker("settings.appearance.layout", selection: $model.settings.overlayLayout) {
                    Text("settings.option.automatic").tag(OverlayLayout.automatic)
                    Text("settings.option.horizontal").tag(OverlayLayout.horizontal)
                    Text("settings.option.grid").tag(OverlayLayout.grid)
                    Text("settings.option.list").tag(OverlayLayout.list)
                }
                .pickerStyle(.segmented)
                if OverlayLayoutAppearanceSupport.supportsCardSize(model.settings.overlayLayout) {
                    Picker("settings.appearance.cardSize", selection: $model.settings.cardSize) {
                        Text("settings.option.small").tag(CardSize.small)
                        Text("settings.option.medium").tag(CardSize.medium)
                        Text("settings.option.large").tag(CardSize.large)
                    }
                }
                if OverlayLayoutAppearanceSupport.supportsThumbnails(model.settings.overlayLayout) {
                    Toggle("settings.appearance.thumbnails", isOn: $model.settings.showsThumbnails)
                }
                Toggle("settings.appearance.applicationName", isOn: $model.settings.showsApplicationName)
                Toggle("settings.appearance.windowTitle", isOn: $model.settings.showsWindowTitle)
                Toggle("settings.appearance.status", isOn: $model.settings.showsWindowStatus)
                Toggle("settings.appearance.searchField", isOn: $model.settings.showsSearchField)
                Toggle("settings.appearance.keyboardHint", isOn: $model.settings.showsKeyboardHint)
            }
            Section {
                Picker("settings.appearance.position", selection: $model.settings.overlayPosition) {
                    Text("settings.option.activeDisplay").tag(OverlayPosition.activeWindowDisplay)
                    Text("settings.option.mouseDisplay").tag(OverlayPosition.mouseDisplay)
                    Text("settings.option.mainDisplay").tag(OverlayPosition.mainDisplay)
                    Text("settings.option.fixedDisplay").tag(OverlayPosition.fixedDisplay)
                }
                if model.settings.overlayPosition == .fixedDisplay {
                    Picker("settings.appearance.fixedDisplay", selection: $model.settings.fixedDisplayIdentifier) {
                        Text("settings.option.mainDisplay").tag("")
                        ForEach(model.availableDisplays) { display in
                            Text(display.name).tag(display.id)
                        }
                    }
                    Button("settings.appearance.refreshDisplays", action: model.refreshAvailableDisplays)
                }
                Picker("settings.appearance.animation", selection: $model.settings.animationPreference) {
                    Text("settings.option.system").tag(AnimationPreference.system)
                    Text("settings.option.reduced").tag(AnimationPreference.reduced)
                    Text("settings.option.none").tag(AnimationPreference.none)
                }
                Picker("settings.appearance.mode", selection: $model.settings.appearance) {
                    Text("settings.option.system").tag(AppAppearance.system)
                    Text("settings.option.light").tag(AppAppearance.light)
                    Text("settings.option.dark").tag(AppAppearance.dark)
                }
            }
        }
    }

    private var windowScope: some View {
        Group {
            Section {
                Toggle("settings.scope.currentSpace", isOn: $model.settings.currentSpaceOnly)
                Toggle("settings.scope.currentDisplay", isOn: $model.settings.currentDisplayOnly)
                Toggle("settings.scope.minimized", isOn: $model.settings.includesMinimizedWindows)
                Toggle("settings.scope.hidden", isOn: $model.settings.includesHiddenApplications)
                Toggle("settings.scope.dialogs", isOn: $model.settings.includesDialogs)
                Toggle("settings.scope.untitled", isOn: $model.settings.includesUntitledWindows)
            }
            Section("settings.scope.ignored") {
                if model.settings.ignoredBundleIdentifiers.isEmpty {
                    Text("settings.scope.noIgnored")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.settings.ignoredBundleIdentifiers.sorted(), id: \.self) { identifier in
                        HStack {
                            Text(identifier)
                            Spacer()
                            Button("action.remove") {
                                model.settings.ignoredBundleIdentifiers.remove(identifier)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Button("settings.scope.addApplication", action: model.addIgnoredApplication)
                    Button("settings.scope.clearIgnored") {
                        model.settings.ignoredBundleIdentifiers = []
                    }
                    .disabled(model.settings.ignoredBundleIdentifiers.isEmpty)
                }
            }
        }
    }

    private var behavior: some View {
        Group {
            Section {
                Picker("settings.behavior.sort", selection: $model.settings.sortOrder) {
                    Text("settings.option.recent").tag(WindowSortOrder.recent)
                    Text("settings.option.application").tag(WindowSortOrder.application)
                    Text("settings.option.title").tag(WindowSortOrder.title)
                    Text("settings.option.display").tag(WindowSortOrder.display)
                }
                Toggle("settings.behavior.includeCurrent", isOn: $model.settings.includesCurrentWindow)
                Toggle("settings.behavior.selectPrevious", isOn: $model.settings.selectsPreviousWindow)
                Toggle("settings.behavior.groupApplications", isOn: $model.settings.groupsApplications)
                Toggle("settings.behavior.restoreMinimized", isOn: $model.settings.restoresMinimizedWindows)
                Picker("settings.behavior.pointer", selection: $model.settings.pointerMovement) {
                    Text("settings.option.pointerNone").tag(PointerMovement.none)
                    Text("settings.option.pointerWindow").tag(PointerMovement.windowCenter)
                    Text("settings.option.pointerDisplay").tag(PointerMovement.displayCenter)
                }
                Picker("settings.behavior.backgroundRefresh", selection: $model.settings.windowRefreshInterval) {
                    Text("settings.option.fiveSeconds").tag(WindowRefreshInterval.fiveSeconds)
                    Text("settings.option.tenSeconds").tag(WindowRefreshInterval.tenSeconds)
                    Text("settings.option.thirtySeconds").tag(WindowRefreshInterval.thirtySeconds)
                }
            }
            Section {
                LabeledContent("settings.behavior.freeze", value: String(localized: "settings.alwaysEnabled"))
            }
        }
    }

    private var permissions: some View {
        Group {
            permissionRow(
                title: "permissions.accessibility",
                state: model.permissions.accessibility,
                actionTitle: "permissions.openAccessibility",
                action: model.permissions.openAccessibilitySettings
            )
            permissionRow(
                title: "permissions.input",
                state: model.permissions.inputMonitoring,
                actionTitle: "permissions.openInput",
                action: {
                    model.settings.hasRequestedInputMonitoringPermission = true
                    model.permissions.openInputMonitoringSettings()
                }
            )
            permissionRow(
                title: "permissions.screen",
                state: model.permissions.screenRecording,
                actionTitle: "permissions.openScreen",
                action: {
                    model.settings.hasRequestedScreenRecordingPermission = true
                    model.permissions.openScreenRecordingSettings()
                }
            )
            Section {
                Button("permissions.refresh", action: model.refreshPermissions)
            }
        }
    }

    private var privacy: some View {
        Group {
            Section {
                Toggle("settings.privacy.disableThumbnails", isOn: Binding(
                    get: { !model.settings.showsThumbnailsInAnySupportedLayout },
                    set: { model.settings.setShowsThumbnailsForAllLayouts(!$0) }
                ))
                Button("settings.privacy.clearCache", action: model.clearThumbnails)
                Toggle("settings.privacy.diagnostics", isOn: $model.settings.diagnosticsEnabled)
                Button("settings.privacy.exportDiagnostics", action: model.prepareDiagnosticExport)
            }
            Section("settings.privacy.statement.title") {
                Text("settings.privacy.statement")
            }
        }
    }

    private var about: some View {
        Group {
            Section {
                LabeledContent("settings.about.name", value: String(localized: "app.name"))
                LabeledContent(
                    "settings.about.version",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
                )
            }
            Section {
                Button("settings.about.help") {
                    model.activeAboutSheet = .help
                }
                Button("settings.about.quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func permissionRow(
        title: LocalizedStringKey,
        state: PermissionState,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Section {
            LabeledContent {
                Label(
                    permissionStatus(state),
                    systemImage: state == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(state == .granted ? .green : .orange)
            } label: {
                Text(title)
            }
            Button(actionTitle, action: action)
        }
    }

    private func permissionStatus(_ state: PermissionState) -> String {
        switch state {
        case .granted: String(localized: "permissions.granted")
        case .denied: String(localized: "permissions.denied")
        case .unavailable: String(localized: "permissions.unavailable")
        }
    }

    private var statusFooter: some View {
        Button {
            model.selectedSection = .permissions
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    model.permissions.hasCorePermission
                        ? String(localized: "status.running")
                        : String(localized: "status.permissionRequired"),
                    systemImage: model.permissions.hasCorePermission ? "circle.fill" : "exclamationmark.circle.fill"
                )
                .foregroundStyle(model.permissions.hasCorePermission ? .green : .orange)
                Text(model.settings.shortcut.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding()
    }
}

private struct DiagnosticExportView: View {
    let report: String
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.privacy.diagnosticPreview.title")
                .font(.title2.bold())
            Text("settings.privacy.diagnosticPreview.description")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("action.cancel", action: dismiss.callAsFunction)
                Button("settings.privacy.exportDiagnostics") {
                    onExport()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620, height: 440)
    }
}

private struct AboutInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            information
            HStack {
                Spacer()
                Button("action.ok", action: dismiss.callAsFunction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private var information: some View {
        Text("settings.about.help.title")
            .font(.title2.bold())
        Text("settings.about.help.body")
            .fixedSize(horizontal: false, vertical: true)
    }
}
