import SwiftUI
import AppKit

@main
struct MyMouseMyControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 保留 Settings 窗口，通过菜单栏图标打开
        Settings {
            ContentView()
                .frame(width: 420, height: 520)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let monitor = MouseEventMonitor.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标，作为菜单栏应用运行
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        // 检查权限，有权限直接开始监听，没有则轮询等待授权
        monitor.checkAccessibilityPermission()
        if monitor.hasAccessibilityPermission {
            monitor.startMonitoring()
        } else {
            monitor.startPermissionPolling()
        }

        // 启动时自动打开设置窗口
        openSettings()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "MyMouseMyControl")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "状态：未监听", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // 监听监听状态变化
        NotificationCenter.default.addObserver(forName: .monitoringStatusChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusMenuItem()
        }
    }

    private func updateStatusMenuItem() {
        if let menu = statusItem?.menu,
           let statusItem = menu.items.first {
            let isMonitoring = MouseEventMonitor.shared.isMonitoring
            statusItem.title = isMonitoring ? "状态：监听中 ●" : "状态：未监听 ○"

            if let button = self.statusItem?.button {
                if isMonitoring {
                    button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "MyMouseMyControl")
                } else {
                    button.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "MyMouseMyControl")
                }
                button.image?.isTemplate = true
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "鼠标侧键控制 - 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettings()
        }
        return true
    }
}

extension Notification.Name {
    static let monitoringStatusChanged = Notification.Name("monitoringStatusChanged")
}
