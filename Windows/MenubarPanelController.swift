//
//  MenubarPanelController.swift
//  AlphaTrack
//
//  菜单栏微面板控制器：原生 NSStatusItem + NSPopover 实现。
//
//  为什么不用 SwiftUI 的 MenuBarExtra(.window)：
//  MenuBarExtra 的面板窗口由系统托管、无法设置 Space（桌面）归属，
//  存在已知缺陷——在非主窗口所在桌面点击时图标高亮但面板不渲染。
//  NSPopover 锚定在状态图标上，任何桌面点击都会立即在当前桌面弹出
//  （Raycast 等专业菜单栏应用的通用机制）。
//
//  注意：NSPopover 内的 SwiftUI 视图不属于任何 Scene，
//  @Environment(\.openWindow) 不可用，因此打开主面板/设置走本控制器的
//  AppKit 通道（见 openMainPanel / openSettings）。
//

import AppKit
import SwiftData
import SwiftUI

/// 微面板即将弹出：MenuBarView 监听它以重新拉取实时行情
extension Notification.Name {
    static let menubarPanelWillShow = Notification.Name("MenuBarPanel.willShow")
}

@MainActor
final class MenubarPanelController: NSObject, NSPopoverDelegate {

    static let shared = MenubarPanelController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    private override init() {
        super.init()
        popover.behavior = .transient            // 点击面板外自动关闭
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .modelContainer(AlphaTrackApp.sharedModelContainer)
        )
    }

    /// 在系统菜单栏安装状态图标（AppDelegate 启动时调用一次）
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis",
                                 accessibilityDescription: "AlphaTrack") {
                img.isTemplate = true            // 跟随菜单栏深浅色
                button.image = img
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    // MARK: - 点击切换显示

    @objc private func statusItemClicked() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        // 跟随微面板自身的深浅色主题，避免 Popover 外框/箭头颜色不符
        popover.appearance = NSAppearance(named: isDarkTheme ? .darkAqua : .aqua)
        // 先激活 App：仅菜单栏模式下状态栏点击不会自动激活，
        // 未激活时 Popover 可能被系统立即收起
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 让面板窗口可出现在任何桌面（Space），并避免被其他窗口盖住
        if let w = popover.contentViewController?.view.window {
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            w.level = .floating
            w.hidesOnDeactivate = false
            w.makeKey()
        }
        // 通知面板刷新现价：内容视图是启动时创建的单例，SwiftUI .task 只在
        // 首次弹出时执行，之后新增的标的将拿不到实时价——每次弹出都要重新拉取
        NotificationCenter.default.post(name: .menubarPanelWillShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        // transient 关闭后让状态图标退出可能的残留高亮
        statusItem?.button?.highlight(false)
    }

    // MARK: - 供 MenuBarView 底部按钮调用（跨上下文打开窗口）

    /// 关闭微面板（打开其它窗口前先收起，避免残留）
    func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// 打开主面板：主窗口在启动时必已创建（隐藏启动也只 orderOut 不销毁），
    /// 直接 AppKit 查找并前置；声明 moveToActiveSpace 让它回到当前桌面，
    /// 避免在别的桌面点击时被开到主窗口原来所在的桌面
    func openMainPanel() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { Self.isMainWindow($0) }) {
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            if win.isMiniaturized { win.deminiaturize(nil) }
            win.makeKeyAndOrderFront(nil)
        }
    }

    /// 打开设置：
    /// 1) 窗口已存在 → 直接前置（同样声明 moveToActiveSpace）
    /// 2) 窗口尚未创建（SwiftUI 场景懒创建）→ 走 WindowRouter 用真正的 openWindow 打开
    /// 3) 路由未注册成功 → 退回合成 ⌘, 键击
    func openSettings() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)

        if let win = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "settings" || $0.title == "设置"
        }) {
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            win.makeKeyAndOrderFront(nil)
            return
        }

        if WindowRouter.shared.open(id: "settings") { return }
        Self.triggerSettingsMenuItem()
    }

    // MARK: - 私有工具

    private var isDarkTheme: Bool {
        switch MBTIAnalyzer.shared.themeMode {
        case .light: return false
        case .dark: return true
        case .auto:
            let name = NSApp.effectiveAppearance.name
            return name == NSAppearance.Name.darkAqua
                || name == NSAppearance.Name.vibrantDark
                || name == NSAppearance.Name.accessibilityHighContrastDarkAqua
                || name == NSAppearance.Name.accessibilityHighContrastVibrantDark
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.title == "AlphaTrack" || window.identifier?.rawValue == "main"
    }

    /// 合成 ⌘, 键击：菜单栏菜单项会响应按键等价物，
    /// 从而在合法的 Commands 环境里执行 openWindow(id: "settings")
    private static func triggerSettingsMenuItem() {
        let mods: NSEvent.ModifierFlags = [.command]
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil,
            characters: ",", charactersIgnoringModifiers: ",",
            isARepeat: false, keyCode: 43 /* kVK_ANSI_Comma */
        ) {
            NSApp.performKeyEquivalent(with: event)
        }
    }
}
