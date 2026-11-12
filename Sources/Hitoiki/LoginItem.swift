import Foundation
import Observation
import ServiceManagement

/// Open at Login (ho-06.1 Decision 20): the app as its own login item, through Apple's login-item service.
///
/// macOS keeps the state, not user defaults, so no key is written; the switch shows what the service reports,
/// read again each time settings is shown. The service's three calls are handed in, so a test stands in for
/// them and never touches the real login items.
@MainActor
@Observable
internal final class LoginItem {
    /// What the service reports for the app.
    internal enum State: Equatable, Sendable {
        case enabled
        case notRegistered
        /// Registered, and waiting for the user to allow it in System Settings.
        case requiresApproval
        case notFound
    }

    /// The service's three calls: its state, register and unregister.
    internal struct Service {
        internal let status: @MainActor () -> State
        internal let register: @MainActor () throws -> Void
        internal let unregister: @MainActor () throws -> Void
    }

    /// The real service, for the app itself.
    internal static let system = Service(
        status: { mapped(SMAppService.mainApp.status) },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() })

    /// The line said while the service waits for the user's approval.
    internal static let approvalLine =
        "Open at Login is waiting for your approval in System Settings › General › Login Items."

    /// False in a build from source, which has no bundle identifier: the switch is off and disabled.
    internal let available: Bool
    /// What the switch shows: on while the app is registered, approved or waiting for approval.
    internal private(set) var isOn = false
    /// The line under the switch: the service's refusal, or the wait for approval; nil for none.
    internal var line: String? {
        refusal ?? (state == .requiresApproval ? Self.approvalLine : nil)
    }

    private let service: Service
    private var state: State = .notRegistered
    /// The service's reason for the last refusal, kept until the next change or the window closes.
    private var refusal: String?

    /// The login item for an app with `bundleIdentifier`, through `service`.
    internal init(bundleIdentifier: String?, service: Service) {
        available = bundleIdentifier != nil
        self.service = service
    }

    /// The service's state for `status`.
    internal static func mapped(_ status: SMAppService.Status) -> State {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        default:
            .notRegistered
        }
    }

    /// Reads the service's state again: settings is being shown, or a change has just been asked for.
    internal func read() {
        guard available else { return }
        state = service.status()
        isOn = state == .enabled || state == .requiresApproval
    }

    /// The switch moved: registers the app for on, unregisters it for off, and shows what the service then
    /// reports; a refusal is said under the switch with the service's reason.
    internal func set(_ on: Bool) {
        guard available else { return }
        refusal = nil
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            refusal = "Open at Login was refused: \(error.localizedDescription)"
        }
        read()
    }

    /// Empties the refusal's line: the settings window closed.
    internal func dismiss() {
        refusal = nil
    }
}
