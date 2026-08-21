import CoreGraphics
import Darwin
import Foundation

nonisolated enum NativeCommandTabHotKey {
    static let commandTabID: Int32 = 1
    static let commandShiftTabID: Int32 = 2

    static func matches(_ shortcut: GlobalShortcut) -> Bool {
        shortcut.isConfigured
            && shortcut.keyCode == 48
            && shortcut.eventFlags.intersection([.maskCommand, .maskAlternate, .maskControl]) == .maskCommand
    }

    static func shouldSuppress(shortcut: GlobalShortcut, isCapturing: Bool, isTapRunning: Bool) -> Bool {
        guard isTapRunning || isCapturing else { return false }
        return isCapturing || matches(shortcut)
    }

    static func setEnabled(_ enabled: Bool) {
        guard let setSymbolicHotKeyEnabled else { return }
        _ = setSymbolicHotKeyEnabled(commandTabID, enabled)
        _ = setSymbolicHotKeyEnabled(commandShiftTabID, enabled)
    }
}

private typealias SetSymbolicHotKeyEnabledFn = @convention(c) (Int32, Bool) -> Int32

private let setSymbolicHotKeyEnabled: SetSymbolicHotKeyEnabledFn? = {
    let paths = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    ]
    var handles: [UnsafeMutableRawPointer?] = [UnsafeMutableRawPointer(bitPattern: -2)]
    handles.append(contentsOf: paths.map { dlopen($0, RTLD_LAZY) })
    handles.append(dlopen(nil, RTLD_LAZY))
    for handle in handles {
        guard let handle, let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else { continue }
        return unsafeBitCast(symbol, to: SetSymbolicHotKeyEnabledFn.self)
    }
    return nil
}()
