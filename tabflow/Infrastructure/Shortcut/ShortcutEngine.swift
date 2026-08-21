import CoreGraphics
import Foundation

enum ShortcutAction: Equatable {
    case cycle(SwitchDirection)
    case commit
    case cancel
    case deleteBackward
    case search(String)
    case moveVertical(GridVerticalDirection)
}

@MainActor
protocol ShortcutEngineDelegate: AnyObject {
    func shortcutEngine(_ engine: ShortcutEngine, received action: ShortcutAction)
    func shortcutEngineDidChangeAvailability(_ engine: ShortcutEngine, isAvailable: Bool)
}

enum ShortcutError: Error {
    case eventTapUnavailable
}

enum ModifierReleasePolicy {
    static func commitsSwitcher(confirmsOnRelease: Bool, hasSearchQuery: Bool) -> Bool {
        confirmsOnRelease && !hasSearchQuery
    }
}

nonisolated enum OnboardingShortcutProbe {
    enum Status: Equatable {
        case waiting
        case succeeded
        case unavailable
    }

    static func status(
        eventTapAvailable: Bool,
        didRecognizeShortcut: Bool
    ) -> Status {
        if !eventTapAvailable { return .unavailable }
        if didRecognizeShortcut { return .succeeded }
        return .waiting
    }

    static func canContinue(_ status: Status) -> Bool {
        status == .succeeded
    }
}

nonisolated struct ShortcutTapSnapshot: Sendable {
    var isPaused = false
    var isSwitcherVisible = false
    var confirmsOnModifierRelease = true
    var confirmsWithReturn = true
    var supportsArrowNavigation = true
    var keepsSwitcherOpenForSearchInput = false
    var isProbingShortcut = false
    var isCapturingShortcut = false
    var shortcut = GlobalShortcut.defaultSwitcher
    var optionWasDown = false

    var commitsOnModifierRelease: Bool {
        ModifierReleasePolicy.commitsSwitcher(
            confirmsOnRelease: confirmsOnModifierRelease,
            hasSearchQuery: keepsSwitcherOpenForSearchInput
        )
    }
}

nonisolated enum ShortcutTapProcessor {
    struct Outcome: Equatable {
        var passEvent: Bool
        var action: ShortcutAction?
        var probeRecognized = false
        var capturedShortcut: GlobalShortcut?
    }

    static func handle(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        characters: String?,
        snapshot: inout ShortcutTapSnapshot
    ) -> Outcome {
        guard !snapshot.isPaused else {
            return Outcome(passEvent: true, action: nil)
        }
        if snapshot.isCapturingShortcut {
            return captureShortcut(type: type, keyCode: keyCode, flags: flags)
        }

        let primaryModifiers = snapshot.shortcut.eventFlags.subtracting(.maskShift)
        let relevantModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let pressedPrimaryModifiers = flags.intersection(relevantModifiers).subtracting(.maskShift)
        let primaryModifierDown = pressedPrimaryModifiers == primaryModifiers

        if type == .flagsChanged {
            defer { snapshot.optionWasDown = primaryModifierDown }
            if snapshot.optionWasDown,
               !primaryModifierDown,
               snapshot.isSwitcherVisible,
               snapshot.commitsOnModifierRelease {
                return Outcome(passEvent: false, action: .commit)
            }
            return Outcome(passEvent: true, action: nil)
        }

        guard type == .keyDown else {
            if type == .keyUp,
               SwitcherEventTapPolicy.swallowsKeyUp(
                isSwitcherVisible: snapshot.isSwitcherVisible,
                keyCode: keyCode,
                shortcutKeyCode: snapshot.shortcut.keyCode
               ) {
                return Outcome(passEvent: false, action: nil)
            }
            return Outcome(passEvent: true, action: nil)
        }

        if snapshot.shortcut.isConfigured,
           keyCode == snapshot.shortcut.keyCode, primaryModifierDown {
            if snapshot.isProbingShortcut {
                return Outcome(passEvent: false, action: nil, probeRecognized: true)
            }
            snapshot.optionWasDown = true
            snapshot.isSwitcherVisible = true
            let direction: SwitchDirection = flags.contains(.maskShift) ? .backward : .forward
            return Outcome(passEvent: false, action: .cycle(direction))
        }

        guard snapshot.isSwitcherVisible else {
            return Outcome(passEvent: true, action: nil)
        }

        let action: ShortcutAction?
        switch keyCode {
        case 53:
            action = .cancel
        case 36 where snapshot.confirmsWithReturn, 76 where snapshot.confirmsWithReturn:
            action = .commit
        case 123 where snapshot.supportsArrowNavigation:
            action = .cycle(.backward)
        case 124 where snapshot.supportsArrowNavigation:
            action = .cycle(.forward)
        case 126 where snapshot.supportsArrowNavigation:
            action = .moveVertical(.up)
        case 125 where snapshot.supportsArrowNavigation:
            action = .moveVertical(.down)
        case 51:
            action = .deleteBackward
        default:
            if let characters, !characters.isEmpty {
                action = .search(characters)
            } else {
                action = nil
            }
        }
        return Outcome(passEvent: false, action: action)
    }

    private static func captureShortcut(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
    ) -> Outcome {
        guard type == .keyDown else {
            return Outcome(passEvent: true, action: nil)
        }
        switch keyCode {
        case 51, 53, 117:
            return Outcome(passEvent: true, action: nil)
        default:
            break
        }
        guard let captured = GlobalShortcut.from(eventFlags: flags, keyCode: keyCode) else {
            return Outcome(passEvent: true, action: nil)
        }
        return Outcome(passEvent: false, action: nil, capturedShortcut: captured)
    }
}

nonisolated enum ShortcutTapLifecycle {
    enum MachPortTeardownStep: Equatable {
        case disableTap
        case stopRunLoop
        case removeSource
        case invalidatePort
    }

    static func invalidatesEventTapOnStop() -> Bool { true }

    static func drainsAutoreleasePoolPerEvent() -> Bool { true }

    static var machPortTeardownOrder: [MachPortTeardownStep] {
        [.disableTap, .stopRunLoop, .removeSource, .invalidatePort]
    }
}

nonisolated enum ShortcutEventTapPlacement {
    static var locations: [CGEventTapLocation] {
        [.cgSessionEventTap]
    }
}

@MainActor
final class ShortcutEngine {
    weak var delegate: ShortcutEngineDelegate?
    var isPaused = false {
        didSet {
            publishSnapshot()
            syncNativeCommandTabSuppression()
        }
    }
    var isSwitcherVisible = false { didSet { publishSnapshot() } }
    var confirmsOnModifierRelease = true { didSet { publishSnapshot() } }
    var confirmsWithReturn = true { didSet { publishSnapshot() } }
    var supportsArrowNavigation = true { didSet { publishSnapshot() } }
    var keepsSwitcherOpenForSearchInput = false { didSet { publishSnapshot() } }
    var isProbingShortcut = false { didSet { publishSnapshot() } }
    var isCapturingShortcut = false {
        didSet {
            publishSnapshot()
            syncNativeCommandTabSuppression()
        }
    }
    var onProbeRecognized: (() -> Void)?
    var onShortcutCaptured: ((GlobalShortcut) -> Void)?
    var shortcut: GlobalShortcut = .defaultSwitcher {
        didSet {
            publishSnapshot()
            syncNativeCommandTabSuppression()
        }
    }

    var commitsOnModifierRelease: Bool {
        ModifierReleasePolicy.commitsSwitcher(
            confirmsOnRelease: confirmsOnModifierRelease,
            hasSearchQuery: keepsSwitcherOpenForSearchInput
        )
    }

    private var tapContext: ShortcutTapContext?
    private var tapThread: Thread?

    func start() throws {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        let context = ShortcutTapContext()
        context.publish { [self] snapshot in
            snapshot.isPaused = isPaused
            snapshot.isSwitcherVisible = isSwitcherVisible
            snapshot.confirmsOnModifierRelease = confirmsOnModifierRelease
            snapshot.confirmsWithReturn = confirmsWithReturn
            snapshot.supportsArrowNavigation = supportsArrowNavigation
            snapshot.keepsSwitcherOpenForSearchInput = keepsSwitcherOpenForSearchInput
            snapshot.isProbingShortcut = isProbingShortcut
            snapshot.isCapturingShortcut = isCapturingShortcut
            snapshot.shortcut = shortcut
            snapshot.optionWasDown = false
        }
        context.deliver = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.shortcutEngine(self, received: action)
            }
        }
        context.probe = { [weak self] in
            Task { @MainActor in
                self?.onProbeRecognized?()
            }
        }
        context.capture = { [weak self] shortcut in
            Task { @MainActor in
                self?.onShortcutCaptured?(shortcut)
            }
        }
        context.availability = { [weak self] isAvailable in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: isAvailable)
            }
        }

        let userInfo = Unmanaged.passUnretained(context).toOpaque()
        if NativeCommandTabHotKey.shouldSuppress(
            shortcut: shortcut,
            isCapturing: isCapturingShortcut,
            isTapRunning: true
        ) {
            NativeCommandTabHotKey.setEnabled(false)
        }
        guard let tap = createEventTap(mask: mask, userInfo: userInfo) else {
            NativeCommandTabHotKey.setEnabled(true)
            delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: false)
            throw ShortcutError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let threadFinished = DispatchSemaphore(value: 0)
        context.eventTap = tap
        context.source = source
        context.threadFinished = threadFinished
        tapContext = context

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            if context.isCancelled {
                threadFinished.signal()
                return
            }
            let runLoop = CFRunLoopGetCurrent()
            context.runLoop = runLoop
            if context.isCancelled {
                threadFinished.signal()
                return
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
            threadFinished.signal()
        }
        thread.name = "com.dreace.tabflow.event-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        if ready.wait(timeout: .now() + 2) == .timedOut {
            stop()
            delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: false)
            throw ShortcutError.eventTapUnavailable
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        syncNativeCommandTabSuppression()
        delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: true)
    }

    func stop() {
        guard let context = tapContext else {
            NativeCommandTabHotKey.setEnabled(true)
            return
        }
        context.deliver = nil
        context.probe = nil
        context.capture = nil
        context.availability = nil
        context.isCancelled = true
        if let eventTap = context.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoop = context.runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        _ = context.threadFinished?.wait(timeout: .now() + 1)
        if let source = context.source, let runLoop = context.runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let eventTap = context.eventTap {
            CFMachPortInvalidate(eventTap)
        }
        tapContext = nil
        tapThread = nil
        NativeCommandTabHotKey.setEnabled(true)
    }

    private func createEventTap(
        mask: CGEventMask,
        userInfo: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        for location in ShortcutEventTapPlacement.locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: shortcutEventCallback,
                userInfo: userInfo
            ) {
                return tap
            }
        }
        return nil
    }

    private func syncNativeCommandTabSuppression() {
        NativeCommandTabHotKey.setEnabled(
            !NativeCommandTabHotKey.shouldSuppress(
                shortcut: shortcut,
                isCapturing: isCapturingShortcut,
                isTapRunning: tapContext != nil
            )
        )
    }

    private func publishSnapshot() {
        tapContext?.publish { [self] snapshot in
            snapshot.isPaused = isPaused
            snapshot.isSwitcherVisible = isSwitcherVisible
            snapshot.confirmsOnModifierRelease = confirmsOnModifierRelease
            snapshot.confirmsWithReturn = confirmsWithReturn
            snapshot.supportsArrowNavigation = supportsArrowNavigation
            snapshot.keepsSwitcherOpenForSearchInput = keepsSwitcherOpenForSearchInput
            snapshot.isProbingShortcut = isProbingShortcut
            snapshot.isCapturingShortcut = isCapturingShortcut
            snapshot.shortcut = shortcut
        }
    }
}

private final class ShortcutTapContext: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = ShortcutTapSnapshot()
    var eventTap: CFMachPort?
    var source: CFRunLoopSource?
    var runLoop: CFRunLoop?
    var threadFinished: DispatchSemaphore?
    var isCancelled = false
    var deliver: (@Sendable (ShortcutAction) -> Void)?
    var probe: (@Sendable () -> Void)?
    var capture: (@Sendable (GlobalShortcut) -> Void)?
    var availability: (@Sendable (Bool) -> Void)?

    func publish(_ update: (inout ShortcutTapSnapshot) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&snapshot)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                availability?(true)
            } else {
                availability?(false)
            }
            return Unmanaged.passUnretained(event)
        }

        var current = ShortcutTapSnapshot()
        lock.lock()
        current = snapshot
        lock.unlock()
        let originalVisible = current.isSwitcherVisible

        let outcome = ShortcutTapProcessor.handle(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            characters: event.keyboardCharacters,
            snapshot: &current
        )

        lock.lock()
        snapshot.optionWasDown = current.optionWasDown
        if current.isSwitcherVisible != originalVisible {
            snapshot.isSwitcherVisible = current.isSwitcherVisible
        }
        lock.unlock()

        if outcome.probeRecognized {
            probe?()
        }
        if let capturedShortcut = outcome.capturedShortcut {
            capture?(capturedShortcut)
        }
        if let action = outcome.action {
            deliver?(action)
        }
        return outcome.passEvent ? Unmanaged.passUnretained(event) : nil
    }
}

private let shortcutEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    autoreleasepool { () -> Unmanaged<CGEvent>? in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<ShortcutTapContext>.fromOpaque(userInfo).takeUnretainedValue()
        return context.handle(type: type, event: event)
    }
}

private extension CGEvent {
    var keyboardCharacters: String? {
        var length = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var buffer = Array<UniChar>(repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}
