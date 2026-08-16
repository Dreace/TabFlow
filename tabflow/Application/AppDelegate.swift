import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var coordinator = AppCoordinator()
    private var didStartCoordinator = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        didStartCoordinator = true
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didStartCoordinator else { return }
        coordinator.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.reopen()
        return true
    }
}
