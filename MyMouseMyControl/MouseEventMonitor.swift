import Foundation
import CoreGraphics
import AppKit
import Combine

// 鼠标侧键按钮定义
enum MouseButton: Int, CaseIterable, Codable, Identifiable {
    case button4 = 3  // 侧键后退（通常是 Button 4）
    case button5 = 4  // 侧键前进（通常是 Button 5）

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .button4: return "侧键 4（后退键）"
        case .button5: return "侧键 5（前进键）"
        }
    }
}

// 可配置的动作
enum MouseAction: String, CaseIterable, Codable, Identifiable {
    case copy       = "copy"
    case paste      = "paste"
    case undo       = "undo"
    case redo       = "redo"
    case cut        = "cut"
    case selectAll  = "selectAll"
    case save       = "save"
    case back       = "back"
    case forward    = "forward"
    case missionControl = "missionControl"
    case launchpad  = "launchpad"
    case switchTab  = "switchTab"
    case closeTab   = "closeTab"
    case newTab     = "newTab"
    case none       = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy:           return "复制 (⌘C)"
        case .paste:          return "粘贴 (⌘V)"
        case .undo:           return "撤销 (⌘Z)"
        case .redo:           return "重做 (⌘⇧Z)"
        case .cut:            return "剪切 (⌘X)"
        case .selectAll:      return "全选 (⌘A)"
        case .save:           return "保存 (⌘S)"
        case .back:           return "返回 (⌘[)"
        case .forward:        return "前进 (⌘])"
        case .missionControl: return "调度中心 (^↑)"
        case .launchpad:      return "启动台 (F4)"
        case .switchTab:      return "切换标签页 (⌃Tab)"
        case .closeTab:       return "关闭标签页 (⌘W)"
        case .newTab:         return "新建标签页 (⌘T)"
        case .none:           return "无动作"
        }
    }
}

@MainActor
class MouseEventMonitor: ObservableObject {
    static let shared = MouseEventMonitor()

    @Published var isMonitoring = false
    @Published var hasAccessibilityPermission = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    // 按键绑定配置，从 UserDefaults 持久化
    @Published var button4Action: MouseAction {
        didSet { saveConfig() }
    }
    @Published var button5Action: MouseAction {
        didSet { saveConfig() }
    }

    private init() {
        let saved4 = UserDefaults.standard.string(forKey: "button4Action") ?? MouseAction.back.rawValue
        let saved5 = UserDefaults.standard.string(forKey: "button5Action") ?? MouseAction.forward.rawValue
        button4Action = MouseAction(rawValue: saved4) ?? .back
        button5Action = MouseAction(rawValue: saved5) ?? .forward
        checkAccessibilityPermission()
    }

    private func saveConfig() {
        UserDefaults.standard.set(button4Action.rawValue, forKey: "button4Action")
        UserDefaults.standard.set(button5Action.rawValue, forKey: "button5Action")
    }

    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != hasAccessibilityPermission {
            hasAccessibilityPermission = trusted
            // 刚获得权限时自动开始监听
            if trusted && !isMonitoring {
                startMonitoring()
            }
        }
    }

    func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityPermission()
                // 权限获取后停止轮询
                if self?.hasAccessibilityPermission == true {
                    self?.stopPermissionPolling()
                }
            }
        }
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // 开始轮询，直到用户授权
        startPermissionPolling()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        // CGEventTapCallBack 是 C 函数指针，必须用满足条件的全局函数
        let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEventFromTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: selfPtr
        ) else {
            Unmanaged<MouseEventMonitor>.fromOpaque(selfPtr).release()
            print("Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isMonitoring = true
        NotificationCenter.default.post(name: .monitoringStatusChanged, object: nil)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isMonitoring = false
        NotificationCenter.default.post(name: .monitoringStatusChanged, object: nil)
    }

    nonisolated func handleEventFromTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .otherMouseDown {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

            // 读取配置需回到主线程，这里先拿快照
            let b4 = MouseButton.button4.rawValue
            let b5 = MouseButton.button5.rawValue

            if buttonNumber == b4 || buttonNumber == b5 {
                DispatchQueue.main.async {
                    let action = buttonNumber == b4 ? self.button4Action : self.button5Action
                    if action != .none {
                        self.performAction(action)
                    }
                }
                // 拦截原始事件，不传递给系统
                return nil
            }
        }
        return Unmanaged.passRetained(event)
    }

    private func performAction(_ action: MouseAction) {
        switch action {
        case .copy:
            sendKeyEvent(keyCode: 8, flags: .maskCommand)
        case .paste:
            sendKeyEvent(keyCode: 9, flags: .maskCommand)
        case .cut:
            sendKeyEvent(keyCode: 7, flags: .maskCommand)
        case .undo:
            sendKeyEvent(keyCode: 6, flags: .maskCommand)
        case .redo:
            sendKeyEvent(keyCode: 6, flags: [.maskCommand, .maskShift])
        case .selectAll:
            sendKeyEvent(keyCode: 0, flags: .maskCommand)
        case .save:
            sendKeyEvent(keyCode: 1, flags: .maskCommand)
        case .back:
            sendKeyEvent(keyCode: 33, flags: .maskCommand)
        case .forward:
            sendKeyEvent(keyCode: 30, flags: .maskCommand)
        case .missionControl:
            sendKeyEvent(keyCode: 126, flags: .maskControl)
        case .launchpad:
            sendKeyEvent(keyCode: 131, flags: [])
        case .switchTab:
            sendKeyEvent(keyCode: 48, flags: .maskControl)
        case .closeTab:
            sendKeyEvent(keyCode: 13, flags: .maskCommand)
        case .newTab:
            sendKeyEvent(keyCode: 17, flags: .maskCommand)
        case .none:
            break
        }
    }

    private func sendKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags   = flags
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
