import Foundation
import ServiceManagement
import Testing

@testable import Hitoiki

/// Stands in for the login-item service: holds a state, counts each call, and refuses when told to.
///
/// The real login items are never touched.
@MainActor
internal final class LoginServiceStandIn {
    /// What the service reports.
    internal var state: LoginItem.State = .notRegistered
    /// The error the next register or unregister throws; nil lets it through.
    internal var refusal: NSError?
    /// What a register that goes through leaves: enabled, or waiting for the user's approval.
    internal var registeredState: LoginItem.State = .enabled
    internal private(set) var reads = 0
    internal private(set) var registers = 0
    internal private(set) var unregisters = 0

    /// No call has reached the service.
    internal var untouched: Bool { reads == 0 && registers == 0 && unregisters == 0 }

    /// The three calls, for a `LoginItem`.
    internal var service: LoginItem.Service {
        LoginItem.Service(
            status: { self.status() },
            register: { try self.register() },
            unregister: { try self.unregister() })
    }

    private func status() -> LoginItem.State {
        reads += 1
        return state
    }

    private func register() throws {
        registers += 1
        if let refusal { throw refusal }
        state = registeredState
    }

    private func unregister() throws {
        unregisters += 1
        if let refusal { throw refusal }
        state = .notRegistered
    }
}

/// An error carrying `reason` as its description, as the service gives one.
private func serviceError(_ reason: String) -> NSError {
    NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
}

@Suite("Open at Login")
@MainActor
internal struct LoginItemTests {
    @Test("On registers and off unregisters; the switch shows what the service then reports")
    internal func onAndOff() {
        let stand = LoginServiceStandIn()
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        #expect(item.available)
        #expect(!item.isOn)
        item.read()
        #expect(!item.isOn)
        #expect(item.line == nil)

        item.set(true)
        #expect(stand.registers == 1 && stand.unregisters == 0)
        #expect(item.isOn)
        #expect(item.line == nil)

        item.set(false)
        #expect(stand.registers == 1 && stand.unregisters == 1)
        #expect(!item.isOn)
        #expect(item.line == nil)
    }

    @Test("The state read back is the service's, whatever changed it: on when enabled or waiting, off otherwise")
    internal func readBack() {
        let stand = LoginServiceStandIn()
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        // Changed in System Settings › General › Login Items, as the next read finds it.
        for (state, on) in [
            (LoginItem.State.enabled, true), (.notRegistered, false), (.requiresApproval, true), (.notFound, false),
        ] {
            stand.state = state
            item.read()
            #expect(item.isOn == on)
        }
        #expect(stand.reads == 4)
        #expect(stand.registers == 0 && stand.unregisters == 0)
    }

    @Test("Waiting for the user's approval says so in the line, and only while it waits")
    internal func approval() {
        let stand = LoginServiceStandIn()
        stand.registeredState = .requiresApproval
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        item.set(true)
        #expect(item.isOn)
        #expect(item.line?.contains("approval") == true)
        #expect(item.line?.contains("System Settings") == true)
        stand.state = .enabled
        item.read()
        #expect(item.line == nil)
    }

    @Test("A refusal gives one line with the system's reason, until the next change or the window closes")
    internal func refused() {
        let stand = LoginServiceStandIn()
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        stand.refusal = serviceError("Operation not permitted")
        item.set(true)
        #expect(stand.registers == 1)
        // The switch shows the service's state, which the refusal left off.
        #expect(!item.isOn)
        #expect(item.line?.contains("Operation not permitted") == true)
        #expect(item.line?.components(separatedBy: "\n").count == 1)
        // A read, as when settings is shown again before it closes, keeps the line.
        item.read()
        #expect(item.line?.contains("Operation not permitted") == true)

        // The next change: the line goes.
        stand.refusal = nil
        item.set(true)
        #expect(item.isOn)
        #expect(item.line == nil)

        // Refused again, then the window closes: the line goes.
        stand.refusal = serviceError("Not allowed")
        item.set(false)
        #expect(item.line?.contains("Not allowed") == true)
        #expect(item.isOn)
        item.dismiss()
        #expect(item.line == nil)
    }

    @Test("A build with no bundle identifier: off, disabled, and nothing reaches the service")
    internal func noBundleIdentifier() {
        let stand = LoginServiceStandIn()
        stand.state = .enabled
        let item = LoginItem(bundleIdentifier: nil, service: stand.service)
        #expect(!item.available)
        item.read()
        item.set(true)
        item.set(false)
        #expect(stand.untouched)
        #expect(!item.isOn)
        #expect(item.line == nil)
    }

    @Test("The service's four states map to the switch's")
    internal func mapping() {
        #expect(LoginItem.mapped(.enabled) == .enabled)
        #expect(LoginItem.mapped(.notRegistered) == .notRegistered)
        #expect(LoginItem.mapped(.requiresApproval) == .requiresApproval)
        #expect(LoginItem.mapped(.notFound) == .notFound)
    }

    @Test("Turning it on and off writes no key: macOS keeps the state")
    internal func noKey() {
        let before = appDomainKeys()
        let stand = LoginServiceStandIn()
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        item.set(true)
        item.read()
        item.set(false)
        #expect(appDomainKeys() == before)
    }
}
