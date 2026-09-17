//
//  SettingsView.swift
//  AlphaTrack
//
//  设置面板（原型 v4 5.10）：650pt 宽
//  - 头部：齿轮 + 设置 + v2.0 徽章
//  - 目标价提醒：胶囊开关 + 间隔选择 + 通知权限绿色徽章
//  - 存储位置：路径框 + 三操作按钮
//  - 数据占用：双色占用条（数据库 + 截图）与图例
//

import SwiftUI
import AppKit
@preconcurrency import UserNotifications

struct SettingsView: View {

    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var alertMonitor = PriceAlertMonitor.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var theme = MBTIAnalyzer.shared
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var showRestartAlert = false
    @State private var showResetConfirm = false
    @State private var directorySize: String = "计算中..."
    @State private var dbBytes: Int64 = 0
    @State private var shotBytes: Int64 = 0
    @State private var alertEnabled: Bool = PriceAlertMonitor.shared.isEnabled
    @State private var alertInterval: PriceAlertInterval = PriceAlertMonitor.shared.interval
    @State private var isSendingTest: Bool = false

    /// 启动时不显示主窗口，仅菜单栏运行（与 AppDelegate 共享同一 key）
    @AppStorage("AlphaTrack.launchHidden") private var launchHidden = false
    /// 仅菜单栏运行：隐藏 Dock 图标与 ⌘Tab（与 AppDelegate 共享同一 key）
    @AppStorage("AlphaTrack.dockHidden") private var dockHidden = false

    /// 与主面板共用同一主题：light/dark 直接锁定，自动跟随系统外观
    private var currentColorScheme: ColorScheme {
        switch theme.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemColorScheme
        }
    }

    private var isDark: Bool { currentColorScheme == .dark }

    private var totalBytes: Int64 { dbBytes + shotBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    launchSection
                    Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                    alertSection
                    Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                    storageSection
                    Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                    dataSection
                }
            }
        }
        .frame(minWidth: 650, idealWidth: 650, maxWidth: 650,
               minHeight: 480, idealHeight: 560, maxHeight: 700)
        .background(
            VisualEffectBackground(
                material: .underWindowBackground,
                blendingMode: .behindWindow
            )
        )
        .preferredColorScheme(currentColorScheme)
        .onAppear { computeDirectorySize() }
        .alert("需要重启", isPresented: $showRestartAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("存储位置已更新。请完全退出 AlphaTrack（⌘Q）后重新打开，新的存储位置才会生效。\n\n当前数据已迁移到新位置。")
        }
        .alert("恢复默认位置", isPresented: $showResetConfirm) {
            Button("确认恢复", role: .destructive) {
                storage.resetToDefault()
                computeDirectorySize()
                showRestartAlert = true
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("数据将迁回 App 沙盒内的默认位置，恢复后需要重启 App。确认继续吗？")
        }
    }

    // MARK: - 头部（原型 .set-head）
    private var headerSection: some View {
        HStack(spacing: 9) {
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundColor(AT.text2(isDark))
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AT.text(isDark))
            Spacer()
            TagView(text: "v2.0", style: .neutral, dark: isDark)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - 目标价提醒（原型 .set-group）

    // MARK: - 启动行为

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            groupTitle("启动行为")
            groupDescription("控制在系统中的驻留方式")

            HStack(spacing: 9) {
                Text("启动时不显示主窗口")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                ATSwitch(isOn: launchHidden) {
                    launchHidden.toggle()
                }
            }
            .padding(.vertical, 2)

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("仅在菜单栏运行")
                        .font(.system(size: 12))
                        .foregroundColor(AT.text(isDark))
                    Text("隐藏 Dock 图标与 ⌘Tab，立即生效")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text3(isDark))
                }
                Spacer()
                ATSwitch(isOn: dockHidden) {
                    dockHidden.toggle()
                    AppDelegate.applyDockHidden(dockHidden)
                }
            }
            .padding(.vertical, 2)

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text3(isDark))
                Text("隐藏 Dock 后，主面板从菜单栏「主面板」按钮或 ⌥A 唤出")
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.text3(isDark))
                Spacer()
            }
        }
        .padding(16)
    }

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            groupTitle("目标价提醒")
            groupDescription("盘中触及目标价即时推送系统通知，并自动提前结算（引擎 B · PriceAlertMonitor）")

            // 启用高频监控（胶囊开关）
            HStack(spacing: 9) {
                Text("启用高频监控")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                ATSwitch(isOn: alertEnabled) {
                    alertEnabled.toggle()
                    alertMonitor.applySettings(enabled: alertEnabled, interval: alertInterval)
                }
            }
            .padding(.vertical, 2)

            // 检查间隔
            HStack(spacing: 9) {
                Text("检查间隔")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                Picker("", selection: $alertInterval) {
                    ForEach(PriceAlertInterval.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .disabled(!alertEnabled)
                .onChange(of: alertInterval) { _, newValue in
                    alertMonitor.applySettings(enabled: alertEnabled, interval: newValue)
                }

                if let caution = alertInterval.caution {
                    Text(caution)
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.warn)
                }
            }

            // 始终提示 1 分钟间隔存在接口限流风险（原型固定子文本）
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AT.warn)
                Text("1 分钟间隔存在接口限流风险")
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.warn)
                Spacer()
            }

            // 通知权限
            HStack(spacing: 9) {
                Text("系统通知权限")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                TagView(
                    text: notifications.statusText,
                    style: notifications.authorizationStatus == .authorized ? .winHi : .warn,
                    dark: isDark
                )
                ghostButton("发送测试通知", disabled: isSendingTest) {
                    isSendingTest = true
                    Task {
                        await notifications.sendTestNotification()
                        isSendingTest = false
                    }
                }
            }

            if notifications.authorizationStatus == .denied {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AT.bear(isDark))
                        .font(.system(size: 10))
                    Text("通知权限已被拒绝，提醒不会弹出。")
                        .font(.system(size: 10))
                        .foregroundColor(AT.bear(isDark))
                    Button("前往开启") {
                        notifications.openNotificationSettings()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(AT.accent)
                    .buttonStyle(PressStyle())
                }
            }

            if let err = alertMonitor.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(AT.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 监控状态行
            HStack(spacing: 9) {
                Text("监控中 \(alertMonitor.monitoredCount) 条")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                if let at = alertMonitor.lastCheckedAt {
                    Text("上次检查 \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text3(isDark))
                }
                Spacer()
                ghostButton("立即检查", disabled: !alertEnabled) {
                    Task { await alertMonitor.checkNow(force: true) }
                }
            }

            if let summary = alertMonitor.lastCheckSummary {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundColor(AT.text3(isDark))
            }
        }
        .padding(16)
        .onAppear {
            Task { await notifications.refreshAuthorizationStatus() }
        }
    }

    // MARK: - 存储位置（原型 .path-box）

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            groupTitle("存储位置")
            groupDescription("权限通过 Security-Scoped Bookmark 持久化，App 重启后依然生效")

            // 路径框（原型 .path-box）
            Text(storage.currentRootURL.path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(AT.text2(isDark))
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))

            if !storage.isCustomLocationAccessible {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AT.warn)
                        .font(.system(size: 11))
                    Text("自定义位置当前不可访问（可能外接设备未连接），已临时使用默认位置")
                        .font(.system(size: 10))
                        .foregroundColor(AT.warn)
                }
            }

            HStack(spacing: 8) {
                ghostButton("更改位置…") {
                    if storage.selectCustomLocation() {
                        computeDirectorySize()
                        showRestartAlert = true
                    }
                }
                ghostButton("在 Finder 中显示") {
                    storage.revealInFinder()
                }
                if storage.mode == .custom {
                    ghostButton("恢复默认") {
                        showResetConfirm = true
                    }
                }
                Spacer()
            }

            if let msg = storage.lastMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(AT.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("外接盘拔出时自动降级回沙盒默认位置，确保始终可启动。选择 iCloud Drive、外接硬盘或专用同步文件夹后，存证数据库与证据截图都会保存在该目录下，需重启 App 生效。")
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    // MARK: - 数据占用（原型 .usage-bar 双色条）

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            groupTitle("数据占用")
            groupDescription("后台异步统计，含 SQLite 主库与截图附件")

            // 双色占用条
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if totalBytes > 0 {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AT.accent)
                            .frame(width: geo.size.width * CGFloat(dbBytes) / CGFloat(totalBytes))
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AT.winHi(isDark))
                            .frame(width: geo.size.width * CGFloat(shotBytes) / CGFloat(totalBytes))
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AT.track(isDark))
                    }
                }
            }
            .frame(height: 9)

            // 图例
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(AT.accent).frame(width: 8, height: 8)
                    Text("数据库 \(bytesText(dbBytes))")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text2(isDark))
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(AT.winHi(isDark)).frame(width: 8, height: 8)
                    Text("截图 \(bytesText(shotBytes))")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text2(isDark))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("合计")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text2(isDark))
                    Text(directorySize)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(AT.text(isDark))
                }
            }

            infoRow("数据库", storage.databaseURL.lastPathComponent)
            infoRow("截图目录", "\(storage.attachmentsBaseURL.lastPathComponent)/Screenshots")
        }
        .padding(16)
    }

    // MARK: - 辅助组件

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(AT.text(isDark))
    }

    private func groupDescription(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(AT.text3(isDark))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AT.text2(isDark))
                .textSelection(.enabled)
            Spacer()
        }
    }

    /// 原型 ghost 按钮：灰底、8pt 圆角
    private func ghostButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(disabled ? AT.text3(isDark) : AT.text2(isDark))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(AT.seg(isDark))
                .cornerRadius(8)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }

    private func bytesText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 异步计算数据库与截图的占用空间（分色统计）
    private func computeDirectorySize() {
        let root = storage.currentRootURL
        let shots = storage.screenshotsDirectoryURL
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var dbTotal: Int64 = 0
            var shotTotal: Int64 = 0

            // 数据库三件套
            for name in ["default.store", "default.store-wal", "default.store-shm",
                         "AlphaTrack.store", "AlphaTrack.store-wal", "AlphaTrack.store-shm"] {
                let url = root.appendingPathComponent(name)
                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    dbTotal += size
                }
            }

            // 截图
            if let enumerator = fm.enumerator(
                at: shots,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        shotTotal += Int64(size)
                    }
                }
            }

            let text = ByteCountFormatter.string(fromByteCount: dbTotal + shotTotal, countStyle: .file)
            DispatchQueue.main.async {
                self.dbBytes = dbTotal
                self.shotBytes = shotTotal
                self.directorySize = text
            }
        }
    }
}

#Preview {
    SettingsView()
}
