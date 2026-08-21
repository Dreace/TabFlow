import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    var onRecordingChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.onShortcut = { newValue in
            shortcut = newValue
        }
        view.onRecordingChange = onRecordingChange
        return view
    }

    static func dismantleNSView(_ nsView: ShortcutRecorderView, coordinator: ()) {
        nsView.endRecordingIfNeeded()
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.shortcut = shortcut
        nsView.onRecordingChange = onRecordingChange
        nsView.needsDisplay = true
    }
}

nonisolated enum ShortcutRecorderPolicy {
    enum EventResult: Equatable {
        case ignore
        case cancel
        case clear
        case capture(GlobalShortcut)
        case invalid
    }

    static let escapeKeyCode: UInt16 = 53
    static let deleteKeyCode: UInt16 = 51
    static let forwardDeleteKeyCode: UInt16 = 117

    static func handleKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> EventResult {
        switch keyCode {
        case escapeKeyCode:
            return .cancel
        case deleteKeyCode, forwardDeleteKeyCode:
            return .clear
        default:
            break
        }
        guard let recorded = GlobalShortcut.from(modifierFlags: modifierFlags, keyCode: keyCode) else {
            return .invalid
        }
        return .capture(recorded)
    }
}

nonisolated enum ShortcutRecorderLifecycle {
    static func shouldEndRecording(
        windowBecameNil: Bool,
        windowWillClose: Bool,
        windowResignedKey: Bool
    ) -> Bool {
        windowBecameNil || windowWillClose || windowResignedKey
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut: GlobalShortcut = .defaultSwitcher {
        didSet {
            guard shortcut != oldValue else { return }
            if isRecording {
                isRecording = false
                onRecordingChange?(false)
            }
            needsDisplay = true
        }
    }
    var onShortcut: ((GlobalShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var isRecording = false
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRingType = .exterior
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "shortcut.recorder.accessibility"))
        setAccessibilityHelp(String(localized: "shortcut.recorder.help"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        removeWindowObservers()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        apply(ShortcutRecorderPolicy.handleKeyDown(keyCode: event.keyCode, modifierFlags: event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow(window)
        if ShortcutRecorderLifecycle.shouldEndRecording(
            windowBecameNil: window == nil,
            windowWillClose: false,
            windowResignedKey: false
        ) {
            endRecordingIfNeeded()
        }
    }

    override func resignFirstResponder() -> Bool {
        endRecordingIfNeeded()
        return super.resignFirstResponder()
    }

    override func accessibilityPerformPress() -> Bool {
        beginRecording()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let title = displayTitle as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centeredStyle
        ]
        let titleSize = title.size(withAttributes: attributes)
        let titleOrigin = NSPoint(
            x: ((self.bounds.width - titleSize.width) / 2).rounded(.down),
            y: ((self.bounds.height - titleSize.height) / 2).rounded(.down)
        )
        title.draw(at: titleOrigin, withAttributes: attributes)
        setAccessibilityValue(shortcut.displayName)
        setAccessibilityTitle(displayTitle)
    }

    private var displayTitle: String {
        isRecording ? String(localized: "shortcut.recording") : shortcut.displayName
    }

    private var centeredStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    func endRecordingIfNeeded() {
        cancelRecording()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChange?(true)
        needsDisplay = true
    }

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChange?(false)
        needsDisplay = true
    }

    private func observeWindow(_ window: NSWindow?) {
        removeWindowObservers()
        guard let window else { return }
        let center = NotificationCenter.default
        windowObservers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                if ShortcutRecorderLifecycle.shouldEndRecording(
                    windowBecameNil: false,
                    windowWillClose: true,
                    windowResignedKey: false
                ) {
                    self?.endRecordingIfNeeded()
                }
            }
        )
        windowObservers.append(
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                if ShortcutRecorderLifecycle.shouldEndRecording(
                    windowBecameNil: false,
                    windowWillClose: false,
                    windowResignedKey: true
                ) {
                    self?.endRecordingIfNeeded()
                }
            }
        )
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private func apply(_ result: ShortcutRecorderPolicy.EventResult) {
        switch result {
        case .ignore:
            return
        case .cancel:
            cancelRecording()
        case .clear:
            finish(with: .none)
        case .capture(let recorded):
            finish(with: recorded)
        case .invalid:
            NSSound.beep()
        }
    }

    private func finish(with shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        isRecording = false
        onRecordingChange?(false)
        onShortcut?(shortcut)
        needsDisplay = true
    }
}
