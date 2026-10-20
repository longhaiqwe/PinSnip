import XCTest
@testable import PinSnipCore

final class MockLaunchAtLoginService: LaunchAtLoginServicing, @unchecked Sendable {
    var status: LaunchAtLoginStatus = .disabled
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSystemSettingsCallCount = 0
    var shouldFailOnRegister: Error?
    var shouldFailOnUnregister: Error?

    func register() throws {
        registerCallCount += 1
        if let error = shouldFailOnRegister {
            throw error
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let error = shouldFailOnUnregister {
            throw error
        }
        status = .disabled
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

private struct MockError: Error, Equatable {}

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testInitialStatusMatchesUnderlyingService() {
        let service = MockLaunchAtLoginService()
        service.status = .disabled
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.status, .disabled)

        service.status = .enabled
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.status, .enabled)

        service.status = .requiresApproval
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.status, .requiresApproval)
    }

    func testToggleEnablesWhenDisabled() throws {
        let service = MockLaunchAtLoginService()
        service.status = .disabled
        let manager = LaunchAtLoginManager(service: service)

        let result = try manager.toggle()

        XCTAssertEqual(result, .enabled)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testToggleDisablesWhenEnabled() throws {
        let service = MockLaunchAtLoginService()
        service.status = .enabled
        let manager = LaunchAtLoginManager(service: service)

        let result = try manager.toggle()

        XCTAssertEqual(result, .disabled)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testTogglePropagatesRegisterError() {
        let service = MockLaunchAtLoginService()
        service.status = .disabled
        service.shouldFailOnRegister = MockError()
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertThrowsError(try manager.toggle()) { error in
            XCTAssertEqual(error as? MockError, MockError())
        }
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertFalse(manager.isEnabled)
    }

    func testTogglePropagatesUnregisterError() {
        let service = MockLaunchAtLoginService()
        service.status = .enabled
        service.shouldFailOnUnregister = MockError()
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertThrowsError(try manager.toggle()) { error in
            XCTAssertEqual(error as? MockError, MockError())
        }
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertTrue(manager.isEnabled)
    }

    func testOpenSystemSettingsDelegatesToService() {
        let service = MockLaunchAtLoginService()
        let manager = LaunchAtLoginManager(service: service)

        manager.openSystemSettings()

        XCTAssertEqual(service.openSystemSettingsCallCount, 1)
    }
}
