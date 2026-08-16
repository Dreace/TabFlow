import XCTest
@testable import TabFlow

final class DiagnosticReportBuilderTests: XCTestCase {
    nonisolated func testReportContainsOnlyConfigurationAndPermissionMetadata() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.Diagnostics"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            let permissions = PermissionManager()
            let report = DiagnosticReportBuilder.make(
                settings: settings,
                permissions: permissions,
                now: Date(timeIntervalSince1970: 0)
            )

            XCTAssertTrue(report.contains("Generated: 1970-01-01T00:00:00Z"))
            XCTAssertTrue(report.contains("Accessibility permission:"))
            XCTAssertTrue(report.contains("Ignored-application count: 0"))
            XCTAssertFalse(report.contains("Window title:"))
            XCTAssertFalse(report.contains("Document path:"))
        }
    }
}
