//
//  HUDPanelController.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox

// MARK: - Carbon 系统全局快捷键调度器 (解决问题五：桌面全系统唤起)
final class CarbonHotKeyManager {
    static let shared = CarbonHotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let _ = event else { return noErr }
                DispatchQueue.main.async {
                    CarbonHotKeyManager.shared.handler?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler
        let signature: OSType = 0x414C5048 // 'ALPH'
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        _ = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

// MARK: - 自定义透明无边框 NSPanel

/// 专为 macOS 原生快捷浮窗设计的 NSPanel
/// 必须重写 canBecomeKey 与 canBecomeMain 为 true，确保无边框浮窗内的 TextField 能够获取键盘焦点 (PRD 4.1)
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - HUDPanelController 控制器

/// 全局居中极速录入浮窗控制器 (PRD 4.1 & HTML View 1)
/// 支持全局快捷键 (⌥+A) 唤起、毛玻璃透明质感、失焦/ESC退出与屏幕居中
@MainActor
final class HUDPanelController: NSObject, NSWindowDelegate {
    
    /// 全局单例
    static let shared = HUDPanelController()
    
    /// 承载的 NSPanel
    private var panel: HUDPanel?
    
    /// 本地与全局鼠标点击监听（用于点击浮窗外部自动关闭）
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    
    /// 键盘快捷键监听器
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    /// 双击修饰键检测状态 (支持双击 ⌥ 唤起)
    private var lastOptionKeyPressTime: TimeInterval = 0

    /// 当前预设的行情分类与自留状态 (解决问题二：主看板点进美股录入，HUD 自动预选美股)
    var currentPresetMarket: String? = nil
    var currentPresetIsSelf: Bool? = nil
    
    private override init() {
        super.init()
    }
    
    // MARK: - 浮窗构建与装配
    
    /// 初始化或获取 HUD 面板
    private func getOrCreatePanel() -> HUDPanel {
        if let existing = self.panel {
            return existing
        }
        
        let initialRect = NSRect(x: 0, y: 0, width: 650, height: 640)
        let newPanel = HUDPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 核心属性设置：无边框、半透明、层级浮动置顶
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.isFloatingPanel = true
        newPanel.animationBehavior = .utilityWindow
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        
        // 允许在全屏窗口及所有 Spaces 虚拟桌面之上显示
        newPanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        
        newPanel.delegate = self
        
        // 装载 SwiftUI QuickEntryView
        //
        // ⚠️ 必须显式注入共享 ModelContainer：HUD 是独立 NSPanel 挂载的游离视图层级，
        // 不在任何 WindowGroup 的 environment 继承链上。若不注入，SwiftUI 会为其
        // 自动创建一个临时容器，导致录入的存证写入另一个库——主看板的 @Query
        // 永远查不到，且 HUD 的来源胶囊也读不到历史档案。
        let rootView = QuickEntryView(onDismiss: { [weak self] in
            self?.hide()
        })
        .modelContainer(AlphaTrackApp.sharedModelContainer)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView
        
        self.panel = newPanel
        return newPanel
    }
    
    // MARK: - 显隐控制
    
    /// 显示全局浮窗并获取第一响应者焦点 (解决问题二：支持传递预设行情分类与自评状态)
    func show(presetMarket: String? = nil, isSelfJudgment: Bool? = nil) {
        let p = getOrCreatePanel()
        
        // 动态同步与主应用一致的深浅外观 (确保 TextField 与控件正确继承系统/选定外观)
        switch MBTIAnalyzer.shared.themeMode {
        case .dark:
            p.appearance = NSAppearance(named: .darkAqua)
        case .light:
            p.appearance = NSAppearance(named: .aqua)
        case .auto:
            p.appearance = nil
        }
        
        // 每次唤起时计算居中位置（偏上 15%，符合 macOS HUD 视觉黄金比例）
        centerPanel(p)
        
        // 记录并广播预设行情分类与自留状态
        self.currentPresetMarket = presetMarket
        self.currentPresetIsSelf = isSelfJudgment
        
        if presetMarket != nil || isSelfJudgment != nil {
            var userInfo: [String: Any] = [:]
            if let m = presetMarket { userInfo["market"] = m }
            if let s = isSelfJudgment { userInfo["isSelf"] = s }
            
            // 立即同步发送一次
            NotificationCenter.default.post(
                name: NSNotification.Name("AlphaTrack_PresetHUD"),
                object: nil,
                userInfo: userInfo
            )
            // 稍后异步再广播一次，确保全新创建的 NSHostingView 在挂载后也能稳定接收
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("AlphaTrack_PresetHUD"),
                    object: nil,
                    userInfo: userInfo
                )
            }
        }
        
        // 激活当前应用并置顶面板
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        
        setupOutsideClickMonitors()
    }
    
    /// 隐藏浮窗
    func hide() {
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }
    
    /// 切换显隐状态 (供快捷键调用)
    func toggle() {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// 屏幕居中定位
    private func centerPanel(_ p: NSPanel) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            p.center()
            return
        }
        
        let screenRect = screen.visibleFrame
        let panelSize = p.frame.size
        
        let x = screenRect.origin.x + (screenRect.width - panelSize.width) / 2.0
        // 纵向居中略偏上，避免视线偏低
        let y = screenRect.origin.y + (screenRect.height - panelSize.height) / 2.0 + 40.0
        
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - 快捷键注册与监听 (解决问题五：桌面系统级唤起，彻底去除长按 ⌥ 闪烁)
    
    /// 注册系统级与本地快捷键监听 (可在 App 启动时调用)
    func registerGlobalShortcuts() {
        // 1. Carbon 系统级全局热键 (⌥+A，即使处于桌面、访达或其它应用前台也能瞬间唤起)
        CarbonHotKeyManager.shared.register(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey)) {
            Task { @MainActor in
                HUDPanelController.shared.toggle()
            }
        }
        
        // 2. 本地按键监听 (前台备用以及浮窗显示时按 ESC 关闭)
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                // 浮窗显示时按 ESC 键 (53) 直接关闭
                if let p = self.panel, p.isVisible, event.keyCode == 53 {
                    self.hide()
                    return nil
                }
                
                return event
            }
        }
        // 注意：彻底移除原 flagsChanged Option 监听，避免长按 Option 键时高频触发导致 HUD 闪烁
    }
    
    // MARK: - 点击外部自动关闭
    
    private func setupOutsideClickMonitors() {
        removeOutsideClickMonitors()
        
        // 全局监控（点击其他应用窗口）
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
        
        // 本地监控（点击本应用内但不在 HUD 面板内的区域）
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let p = self.panel, p.isVisible else { return event }
            let clickLocation = event.locationInWindow
            let clickInScreen = event.window?.convertToScreen(NSRect(origin: clickLocation, size: .zero)).origin ?? NSEvent.mouseLocation
            
            if !p.frame.contains(clickInScreen) {
                self.hide()
            }
            return event
        }
    }
    
    private func removeOutsideClickMonitors() {
        if let m = globalMouseDownMonitor {
            NSEvent.removeMonitor(m)
            globalMouseDownMonitor = nil
        }
        if let m = localMouseDownMonitor {
            NSEvent.removeMonitor(m)
            localMouseDownMonitor = nil
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidResignKey(_ notification: Notification) {
        // 当浮窗失去焦点时自动隐藏，保持轻量无打扰体验
        hide()
    }
}
