import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

nonisolated enum WindowServerFocusPolicy {
    static let resignKeyWindowDelay: Duration = .milliseconds(40)

    static func canFocusSpecificWindow(cgWindowID: CGWindowID?) -> Bool {
        cgWindowID != nil
    }

    static func shouldActivateApplication(
        hasWindowID: Bool,
        isFrontmost: Bool,
        isHidden: Bool
    ) -> Bool {
        if hasWindowID { return isHidden }
        return WindowActivationSequence.shouldBringApplicationForward(
            isFrontmost: isFrontmost,
            isHidden: isHidden
        )
    }

    static func shouldClearWindowsBeforeFocus() -> Bool {
        false
    }

    static func shouldResignCurrentKeyWindow(
        currentFrontWindowID: CGWindowID?,
        targetWindowID: CGWindowID
    ) -> Bool {
        guard let currentFrontWindowID else { return false }
        return currentFrontWindowID != targetWindowID
    }
}

nonisolated enum WindowServerFocus {
    private static let userGenerated: UInt32 = 0x200
    private static let orderAbove: Int32 = 1

    private static let getProcessForPID: GetProcessForPIDFn? = loadSymbol(
        "GetProcessForPID",
        paths: [
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            "/System/Library/Frameworks/Carbon.framework/Carbon"
        ]
    )
    private static let setFrontProcess: SetFrontProcess? = loadSymbol(
        "_SLPSSetFrontProcessWithOptions"
    )
    private static let postEventRecord: PostEventRecord? = loadSymbol(
        "SLPSPostEventRecordTo"
    )
    private static let mainConnectionID: MainConnectionIDFn? = loadSymbol(
        "SLSMainConnectionID"
    )
    private static let orderWindow: OrderWindowFn? = loadSymbol(
        "SLSOrderWindow"
    )
    private static let windowOwner: WindowOwnerFn? = loadSymbol(
        "SLSGetWindowOwner"
    )
    private static let connectionPSN: ConnectionPSNFn? = loadSymbol(
        "SLSGetConnectionPSN"
    )

    @discardableResult
    static func focus(
        pid: pid_t,
        windowID: CGWindowID,
        currentlyFrontWindowID: CGWindowID? = nil
    ) async -> Bool {
        if WindowServerFocusPolicy.shouldResignCurrentKeyWindow(
            currentFrontWindowID: currentlyFrontWindowID,
            targetWindowID: windowID
        ), let currentlyFrontWindowID {
            _ = resignKeyWindow(pid: pid, windowID: currentlyFrontWindowID)
            try? await Task.sleep(for: WindowServerFocusPolicy.resignKeyWindowDelay)
        }
        return focusNow(pid: pid, windowID: windowID)
    }

    @discardableResult
    static func resignKeyWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard var psn = processSerialNumber(for: pid, windowID: windowID) else { return false }
        return postEvent(
            psn: &psn,
            windowID: windowID,
            opcode: 0x0D,
            fillKeyWindowMask: false,
            extra: { bytes in
                bytes[0x8A] = 0x02
            }
        )
    }

    @discardableResult
    private static func focusNow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard var psn = processSerialNumber(for: pid, windowID: windowID) else { return false }
        orderWindowAbove(windowID)
        let fronted = setFrontProcess?(&psn, windowID, userGenerated) == 0
        postKeyWindowEvents(psn: &psn, windowID: windowID)
        return fronted || postEventRecord != nil
    }

    private static func processSerialNumber(for pid: pid_t, windowID: CGWindowID) -> ProcessSerialNumber? {
        var psn = ProcessSerialNumber()
        if getProcessForPID?(pid, &psn) == noErr, psn.lowLongOfPSN != 0 || psn.highLongOfPSN != 0 {
            return psn
        }
        return connectionProcessSerialNumber(for: windowID)
    }

    private static func connectionProcessSerialNumber(for windowID: CGWindowID) -> ProcessSerialNumber? {
        guard let mainConnectionID, let windowOwner, let connectionPSN else { return nil }
        var owner: UInt32 = 0
        guard windowOwner(mainConnectionID(), windowID, &owner) == 0, owner != 0 else { return nil }
        var psn = ProcessSerialNumber()
        guard connectionPSN(owner, &psn) == 0, psn.lowLongOfPSN != 0 || psn.highLongOfPSN != 0 else {
            return nil
        }
        return psn
    }

    private static func orderWindowAbove(_ windowID: CGWindowID) {
        guard let mainConnectionID, let orderWindow else { return }
        _ = orderWindow(mainConnectionID(), windowID, orderAbove, 0)
    }

    private static func postKeyWindowEvents(psn: inout ProcessSerialNumber, windowID: CGWindowID) {
        for opcode: UInt8 in [0x01, 0x02] {
            _ = postEvent(
                psn: &psn,
                windowID: windowID,
                opcode: opcode,
                fillKeyWindowMask: true
            )
        }
    }

    @discardableResult
    private static func postEvent(
        psn: inout ProcessSerialNumber,
        windowID: CGWindowID,
        opcode: UInt8,
        fillKeyWindowMask: Bool,
        extra: ((inout [UInt8]) -> Void)? = nil
    ) -> Bool {
        guard let postEventRecord else { return false }
        var wid = windowID
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x08] = opcode
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: &wid) { source in
            for offset in 0..<4 {
                bytes[0x3C + offset] = source[offset]
            }
        }
        if fillKeyWindowMask {
            for index in 0x20..<0x30 {
                bytes[index] = 0xFF
            }
        }
        extra?(&bytes)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return postEventRecord(&psn, baseAddress) == 0
        }
    }

    private static func loadSymbol<T>(_ name: String, paths: [String] = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    ]) -> T? {
        var handles: [UnsafeMutableRawPointer?] = [UnsafeMutableRawPointer(bitPattern: -2)]
        handles.append(contentsOf: paths.map { dlopen($0, RTLD_LAZY) })
        handles.append(dlopen(nil, RTLD_LAZY))
        for handle in handles {
            guard let handle, let symbol = dlsym(handle, name) else { continue }
            return unsafeBitCast(symbol, to: T.self)
        }
        return nil
    }
}

private typealias GetProcessForPIDFn = @convention(c) (
    pid_t,
    UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

private typealias SetFrontProcess = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>,
    UInt32,
    UInt32
) -> Int32

private typealias PostEventRecord = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>,
    UnsafeRawPointer
) -> Int32

private typealias MainConnectionIDFn = @convention(c) () -> UInt32

private typealias OrderWindowFn = @convention(c) (
    UInt32,
    CGWindowID,
    Int32,
    CGWindowID
) -> Int32

private typealias WindowOwnerFn = @convention(c) (
    UInt32,
    CGWindowID,
    UnsafeMutablePointer<UInt32>
) -> Int32

private typealias ConnectionPSNFn = @convention(c) (
    UInt32,
    UnsafeMutablePointer<ProcessSerialNumber>
) -> Int32
