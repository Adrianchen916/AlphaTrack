//
//  AlphaTrackApp.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import SwiftUI
import SwiftData

@main
struct AlphaTrackApp: App {
    /// 启动行为委托：处理"启动时不显示主窗口，仅菜单栏运行"
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 声明为 static，供对账引擎等全局服务注入同一个容器
    /// 存储位置由 StorageManager 决定：沙盒默认位置，或用户在设置里自选的目录
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PredictionEntry.self,
            SourceProfile.self,
        ])

        // 依据 StorageManager 的当前模式构造配置：
        // - 沙盒模式：不指定 url，沿用 SwiftData 默认位置
        // - 自定义模式：显式指向用户选择目录下的 AlphaTrack.store
        let storage = StorageManager.shared
        storage.ensureDirectoriesExist()

        let modelConfiguration: ModelConfiguration
        if storage.mode == .custom {
            // 注意：带 url 的 init 不接受 isStoredInMemoryOnly，持久化由 url 隐含决定
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storage.databaseURL
            )
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // 自定义位置打开失败（外接硬盘被拔、权限丢失）时，回退到沙盒默认位置，
            // 保证 App 始终可用，不会因存储配置问题白屏崩溃
            print("[AlphaTrack] 自定义存储位置打开失败，回退默认位置：\(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    init() {
        // 必须在任何通知发出之前安装 delegate，否则 App 处于前台时通知会被系统静默丢弃
        NotificationManager.shared.install()

        // App 内强制 overlay 细圆滚动条（原型 v4 视觉），不影响其它应用
        NSScrollView.enableOverlayScrollers()

        // 动态强制设定 App 图标，彻底解决 macOS Dock 缓存未刷新及增量构建未生效的问题
        if let iconURL = Bundle.main.url(forResource: "AppIconMaster", withExtension: "png"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImg
        } else if let assetIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = assetIcon
        }

        // 对账引擎在 App 启动时即接管，无需等待主窗口打开
        ArbitrationEngine.shared.configure(container: Self.sharedModelContainer)
        ArbitrationEngine.shared.startScheduling()

        // 目标价到达提醒：独立高频轮询，与 30 分钟对账扫描互补
        PriceAlertMonitor.shared.configure(container: Self.sharedModelContainer)
        Task { @MainActor in
            await PriceAlertMonitor.shared.requestAuthorizationIfNeeded()
            PriceAlertMonitor.shared.start()
        }

        // App 启动时立即注册系统级全局快捷键 (⌥+A)，确保在桌面及其他应用前台都能即时呼出 HUD
        HUDPanelController.shared.registerGlobalShortcuts()
    }

    var body: some Scene {
        // 单例主面板，由 Window(id:) 保证全局唯一窗口，杜绝重复弹出多开
        Window("AlphaTrack", id: "main") {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
        .commands {
            SettingsCommands()
        }

        // 存证流水单例窗口
        Window("存证流水", id: "ledger") {
            EntryLedgerView()
        }
        .modelContainer(Self.sharedModelContainer)

        // 来源档案单例窗口
        Window("来源档案", id: "sources") {
            SourceProfileManagerView()
        }
        .modelContainer(Self.sharedModelContainer)

        // 设置单例窗口（存储位置、数据管理）
        Window("设置", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 650, height: 600)
        .windowResizability(.contentSize)
        .modelContainer(Self.sharedModelContainer)

        // 菜单栏微面板已迁移为原生 NSStatusItem + NSPopover
        // （见 Windows/MenubarPanelController.swift）：
        // MenuBarExtra 的面板窗口在非主窗口所在桌面无法弹出（系统级缺陷）
    }
}
