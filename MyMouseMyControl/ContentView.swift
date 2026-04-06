import SwiftUI

struct ContentView: View {
    @ObservedObject private var monitor = MouseEventMonitor.shared
    @ObservedObject private var loginManager = LaunchAtLoginManager.shared
    @State private var showPermissionAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 权限状态卡片
                    permissionCard

                    // 监听开关卡片
                    monitorCard

                    // 侧键配置卡片
                    buttonConfigCard

                    // 开机自启动卡片
                    launchAtLoginCard
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            monitor.checkAccessibilityPermission()
            loginManager.checkStatus()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Image(systemName: "cursorarrow.click.2")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("鼠标侧键控制")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Permission Card
    private var permissionCard: some View {
        CardView {
            HStack(spacing: 12) {
                Image(systemName: monitor.hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundColor(monitor.hasAccessibilityPermission ? .green : .orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("辅助功能权限")
                        .font(.headline)
                    Text(monitor.hasAccessibilityPermission
                         ? "已获取权限，可以监听鼠标事件"
                         : "请在系统设置中授权后，此处将自动更新")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !monitor.hasAccessibilityPermission {
                    Button("授权") {
                        monitor.requestAccessibilityPermission()
                        openAccessibilityPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Monitor Card
    private var monitorCard: some View {
        CardView {
            HStack(spacing: 12) {
                Image(systemName: monitor.isMonitoring ? "dot.radiowaves.left.and.right" : "circle.slash")
                    .font(.title2)
                    .foregroundColor(monitor.isMonitoring ? .green : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("侧键监听")
                        .font(.headline)
                    Text(monitor.isMonitoring ? "正在监听鼠标侧键事件" : "监听已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { monitor.isMonitoring },
                    set: { newVal in
                        if newVal {
                            if monitor.hasAccessibilityPermission {
                                monitor.startMonitoring()
                            } else {
                                monitor.requestAccessibilityPermission()
                                openAccessibilityPreferences()
                            }
                        } else {
                            monitor.stopMonitoring()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .disabled(!monitor.hasAccessibilityPermission)
            }
        }
    }

    // MARK: - Button Config Card
    private var buttonConfigCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Label("侧键功能设置", systemImage: "slider.horizontal.3")
                    .font(.headline)

                Divider()

                actionPickerRow(
                    icon: "arrow.backward.circle.fill",
                    label: "侧键 4（后退键）",
                    binding: Binding(
                        get: { monitor.button4Action },
                        set: { monitor.button4Action = $0 }
                    )
                )

                Divider()
                    .padding(.leading, 32)

                actionPickerRow(
                    icon: "arrow.forward.circle.fill",
                    label: "侧键 5（前进键）",
                    binding: Binding(
                        get: { monitor.button5Action },
                        set: { monitor.button5Action = $0 }
                    )
                )
            }
        }
    }

    private func actionPickerRow(icon: String, label: String, binding: Binding<MouseAction>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 22)

            Text(label)
                .font(.subheadline)

            Spacer()

            Picker("", selection: binding) {
                ForEach(MouseAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .frame(width: 180)
            .labelsHidden()
        }
    }

    // MARK: - Launch at Login Card
    private var launchAtLoginCard: some View {
        CardView {
            HStack(spacing: 12) {
                Image(systemName: "power.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("开机自启动")
                        .font(.headline)
                    Text(loginManager.isEnabled ? "登录后自动启动应用" : "关闭后不会自动启动")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { loginManager.isEnabled },
                    set: { loginManager.setEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: - Helper
    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Card 容器组件
struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
            )
    }
}

#Preview {
    ContentView()
}
