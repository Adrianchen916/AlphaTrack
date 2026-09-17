//
//  AppDelegate.swift
//  AlphaTrack
//
//  App 级生命周期委托：启动行为控制。
//  支持"启动时不显示主窗口，仅菜单栏运行"（设置在「设置 → 启动行为」）。
//
//  实现说明：
//  - 工程最低部署目标为 macOS 14，无法使用 macOS 15 的 `.defaultLaunchBehavior(.suppressed)`，
//    因此采用"启动后短轮询、主窗口一出现就 orderOut"的方式，兼容 14 起的所有版本。
//  - 隐藏后：regular 模式点 Dock 图标可唤回（applicationShouldHandleReopen）；
//    accessory 模式（仅菜单栏运行）用菜单栏「主面板」按钮或 ⌥A 唤出。
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 与设置页共享的存储 key：true = 启动时不显示主窗口，仅菜单栏运行
    static let launchHiddenKey = "AlphaTrack.launchHidden"
    /// 与设置页共享的存储 key：true = 隐藏 Dock 图标，仅在菜单栏（系统托盘）运行
    static let dockHiddenKey = "AlphaTrack.dockHidden"

    private var didAutoHide = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏微面板：原生状态图标 + Popover（任何桌面点击都能立即弹出）
        MenubarPanelController.shared.install()

        // 仅菜单栏运行：切为 accessory 应用，图标从 Dock 和 ⌘Tab 消失。
        // 附带修复：regular 应用会"占据"主窗口所在的空间（桌面），
        // 导致在其他桌面点菜单栏微面板时系统要先切换空间、看起来没反应；
        // accessory 应用不绑定任何空间，微面板在哪个桌面点都能立即弹出。
        if UserDefaults.standard.bool(forKey: Self.dockHiddenKey) {
            Self.applyDockHidden(true)
        }

        guard UserDefaults.standard.bool(forKey: Self.launchHiddenKey) else { return }

        hideMainWindowWhenVisible()
    }

    /// 主窗口由 SwiftUI 场景在启动后异步创建，出现时刻不定。
    /// 用短轮询兜住：每 0.25s 检查一次，出现即隐藏；最多 12 次（3 秒）后放弃。
    private func hideMainWindowWhenVisible() {
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            attempts += 1
            if let mainWindow = NSApp.windows.first(where: { Self.isMainWindow($0) }) {
                mainWindow.orderOut(nil)
                self.didAutoHide = true
                timer.invalidate()
            } else if attempts >= 12 {
                timer.invalidate()
            }
        }
    }

    /// 点击 Dock 图标重新唤出主窗口，保证隐藏模式下用户仍能打开主面板
    /// （仅 regular 模式有效；accessory 模式下 Dock 无图标，用菜单栏「主面板」/⌥A 唤出）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where Self.isMainWindow(window) {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        return true
    }

    /// 实时切换 Dock 图标显隐：accessory = 隐藏（仅菜单栏运行），regular = 恢复
    static func applyDockHidden(_ hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }

    /// 主窗口判定：匹配窗口标题或 SwiftUI 场景 id
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.title == "AlphaTrack" || window.identifier?.rawValue == "main"
    }
}
