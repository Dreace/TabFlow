import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.shortcut = shortcut
        button.onChange = { newValue in
            shortcut = newValue
        }
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.shortcut = shortcut
        nsView.updateTitle()
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: GlobalShortcut = .defaultSwitcher
    var onChange: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        setButtonType(.momentaryPushIn)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            window?.makeFirstResponder(self)
        }
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            return
        }
        guard let recorded = GlobalShortcut.from(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = recorded
        isRecording = false
        onChange?(recorded)
        updateTitle()
    }

    func updateTitle() {
        title = isRecording ? String(localized: "shortcut.recording") : shortcut.displayName
        setAccessibilityLabel(String(localized: "shortcut.recorder.accessibility"))
        setAccessibilityValue(shortcut.displayName)
    }
}
