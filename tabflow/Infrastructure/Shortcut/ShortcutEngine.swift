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
        case conflict
        case unavailable
    }

    static func status(
        hasSystemConflict: Bool,
        eventTapAvailable: Bool,
        didRecognizeShortcut: Bool
    ) -> Status {
        if hasSystemConflict { return .conflict }
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

        if keyCode == snapshot.shortcut.keyCode, primaryModifierDown {
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
}

nonisolated enum ShortcutTapLifecycle {
    static func invalidatesEventTapOnStop() -> Bool { true }

    static func drainsAutoreleasePoolPerEvent() -> Bool { true }
}

@MainActor
final class ShortcutEngine {
    weak var delegate: ShortcutEngineDelegate?
    var isPaused = false { didSet { publishSnapshot() } }
    var isSwitcherVisible = false { didSet { publishSnapshot() } }
    var confirmsOnModifierRelease = true { didSet { publishSnapshot() } }
    var confirmsWithReturn = true { didSet { publishSnapshot() } }
    var supportsArrowNavigation = true { didSet { publishSnapshot() } }
    var keepsSwitcherOpenForSearchInput = false { didSet { publishSnapshot() } }
    var isProbingShortcut = false { didSet { publishSnapshot() } }
    var onProbeRecognized: (() -> Void)?
    var shortcut: GlobalShortcut = .defaultSwitcher { didSet { publishSnapshot() } }

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
        context.availability = { [weak self] isAvailable in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: isAvailable)
            }
        }

        let userInfo = Unmanaged.passUnretained(context).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: shortcutEventCallback,
            userInfo: userInfo
        ) else {
            delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: false)
            throw ShortcutError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        context.eventTap = tap
        context.source = source
        tapContext = context

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            context.runLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
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
        delegate?.shortcutEngineDidChangeAvailability(self, isAvailable: true)
    }

    func stop() {
        guard let context = tapContext else { return }
        context.deliver = nil
        context.probe = nil
        context.availability = nil
        if let eventTap = context.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let source = context.source, let runLoop = context.runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        tapContext = nil
        tapThread = nil
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
    var deliver: (@Sendable (ShortcutAction) -> Void)?
    var probe: (@Sendable () -> Void)?
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
