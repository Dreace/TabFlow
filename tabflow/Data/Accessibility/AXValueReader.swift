import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

nonisolated enum AXReadError: Error, CustomStringConvertible {
    case failure(attribute: String, code: AXError)
    case unexpectedType(attribute: String)

    var description: String {
        switch self {
        case let .failure(attribute, code):
            "failure(attribute: \(attribute), code: \(code.diagnosticName))"
        case let .unexpectedType(attribute):
            "unexpectedType(attribute: \(attribute))"
        }
    }

    var windowListFailureKind: AXWindowListFailureKind? {
        guard case let .failure(_, code) = self else { return nil }
        return AXWindowListFailureKind(code: code)
    }
}

nonisolated enum AXWindowListFailureKind: Equatable {
    case transient
    case unsupported
    case fatal

    init(code: AXError) {
        switch code {
        case .cannotComplete:
            self = .transient
        case .noValue, .attributeUnsupported, .notImplemented, .invalidUIElement:
            self = .unsupported
        default:
            self = .fatal
        }
    }
}

nonisolated enum AXScanLimits {
    static let messagingTimeout: Float = 0.15
    static let activationTimeout: Float = 2.5
}

nonisolated enum AXWindowEnumeration {
    static func shouldUseChildWindows(attributeWindowCount: Int?) -> Bool {
        (attributeWindowCount ?? 0) == 0
    }
}

nonisolated enum AXActivationRetry {
    static let attempts = 4
    static let delay: Duration = .milliseconds(300)

    static func shouldRetry(windowsFound: Int, attempt: Int) -> Bool {
        windowsFound == 0 && attempt < attempts
    }
}

nonisolated enum AXWindowIdentity {
    private typealias GetWindowFn = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private static let getWindow: GetWindowFn? = loadSymbol()

    static func cgWindowID(from element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var windowID: CGWindowID = 0
        guard getWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    private static func loadSymbol() -> GetWindowFn? {
        let paths = [
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/Carbon.framework/Carbon"
        ]
        var handles: [UnsafeMutableRawPointer?] = [UnsafeMutableRawPointer(bitPattern: -2)]
        handles.append(contentsOf: paths.map { dlopen($0, RTLD_LAZY) })
        handles.append(dlopen(nil, RTLD_LAZY))
        for handle in handles {
            guard let handle, let symbol = dlsym(handle, "_AXUIElementGetWindow") else { continue }
            return unsafeBitCast(symbol, to: GetWindowFn.self)
        }
        return nil
    }
}

nonisolated enum AXValueReader {
    static func value(_ attribute: CFString, from element: AXUIElement) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            throw AXReadError.failure(attribute: attribute as String, code: result)
        }
        return value
    }

    static func string(_ attribute: CFString, from element: AXUIElement) throws -> String {
        guard let value = try value(attribute, from: element) as? String else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        return value
    }

    static func bool(_ attribute: CFString, from element: AXUIElement) throws -> Bool {
        guard let value = try value(attribute, from: element) as? Bool else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        return value
    }

    static func point(_ attribute: CFString, from element: AXUIElement) throws -> CGPoint {
        let raw = try value(attribute, from: element)
        guard CFGetTypeID(raw) == AXValueGetTypeID() else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        // The Core Foundation type ID check above guarantees this bridge.
        let axValue = raw as! AXValue
        guard AXValueGetType(axValue) == .cgPoint
        else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        return point
    }

    static func size(_ attribute: CFString, from element: AXUIElement) throws -> CGSize {
        let raw = try value(attribute, from: element)
        guard CFGetTypeID(raw) == AXValueGetTypeID() else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        // The Core Foundation type ID check above guarantees this bridge.
        let axValue = raw as! AXValue
        guard AXValueGetType(axValue) == .cgSize
        else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        return size
    }

    static func windows(from application: AXUIElement) throws -> [AXUIElement] {
        let attributeResult: Result<[AXUIElement], Error> = Result { try copyWindowList(from: application) }
        if case let .success(windows) = attributeResult,
           !AXWindowEnumeration.shouldUseChildWindows(attributeWindowCount: windows.count) {
            return windows
        }
        let childWindows = children(of: application).filter { element in
            (try? string(kAXRoleAttribute as CFString, from: element)) == kAXWindowRole
        }
        if !childWindows.isEmpty {
            return childWindows
        }
        switch attributeResult {
        case let .success(windows):
            return windows
        case let .failure(error):
            throw error
        }
    }

    static func windowAttributes(from element: AXUIElement) -> AXWindowAttributes {
        let names: [CFString] = [
            kAXRoleAttribute as CFString,
            kAXSubroleAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXModalAttribute as CFString,
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
            kAXMinimizedAttribute as CFString,
            kAXFocusedAttribute as CFString,
            "AXFullScreen" as CFString
        ]
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
        guard result == .success, let values else {
            return AXWindowAttributes()
        }
        let items = values as [AnyObject]
        return AXWindowAttributes(
            role: stringValue(items, at: 0),
            subrole: stringValue(items, at: 1),
            title: stringValue(items, at: 2)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isModal: boolValue(items, at: 3) ?? false,
            position: pointValue(items, at: 4) ?? .zero,
            size: sizeValue(items, at: 5) ?? .zero,
            isMinimized: boolValue(items, at: 6) ?? false,
            isFocused: boolValue(items, at: 7) ?? false,
            isFullScreen: boolValue(items, at: 8) ?? false
        )
    }

    static func element(_ attribute: CFString, from element: AXUIElement) throws -> AXUIElement {
        let raw = try value(attribute, from: element)
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw AXReadError.unexpectedType(attribute: attribute as String)
        }
        // The Core Foundation type ID check above guarantees this bridge.
        return raw as! AXUIElement
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        (try? value(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement]) ?? []
    }

    static func set(_ value: CFTypeRef, attribute: CFString, on element: AXUIElement) throws {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if OwnProcessWindowActivation.applies(to: pid), !Thread.isMainThread {
            throw AXReadError.failure(attribute: attribute as String, code: .illegalArgument)
        }
        let result = AXUIElementSetAttributeValue(element, attribute, value)
        guard result == .success else {
            throw AXReadError.failure(attribute: attribute as String, code: result)
        }
    }

    private static func copyWindowList(from application: AXUIElement) throws -> [AXUIElement] {
        guard let windows = try value(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] else {
            throw AXReadError.unexpectedType(attribute: kAXWindowsAttribute)
        }
        return windows
    }

    private static func stringValue(_ items: [AnyObject], at index: Int) -> String? {
        guard items.indices.contains(index) else { return nil }
        return items[index] as? String
    }

    private static func boolValue(_ items: [AnyObject], at index: Int) -> Bool? {
        guard items.indices.contains(index) else { return nil }
        return items[index] as? Bool
    }

    private static func pointValue(_ items: [AnyObject], at index: Int) -> CGPoint? {
        guard items.indices.contains(index), CFGetTypeID(items[index]) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = items[index] as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ items: [AnyObject], at index: Int) -> CGSize? {
        guard items.indices.contains(index), CFGetTypeID(items[index]) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = items[index] as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

nonisolated struct AXWindowAttributes {
    var role: String?
    var subrole: String?
    var title: String = ""
    var isModal = false
    var position = CGPoint.zero
    var size = CGSize.zero
    var isMinimized = false
    var isFocused = false
    var isFullScreen = false
}

extension AXError {
    nonisolated var diagnosticName: String {
        switch self {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        default: "code(\(rawValue))"
        }
    }
}
