import Foundation
import ServiceManagement
import Combine

@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool = false

    private init() {
        checkStatus()
    }

    func checkStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                isEnabled = enabled
            } catch {
                print("Launch at login error: \(error.localizedDescription)")
            }
        } else {
            // macOS 12 及以下使用 SMLoginItemSetEnabled
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            isEnabled = enabled
        }
    }
}
