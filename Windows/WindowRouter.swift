//
//  WindowRouter.swift
//  AlphaTrack
//
//  用途：让 AppKit 侧（如菜单栏微面板）也能打开 SwiftUI 的窗口场景。
//
//  背景：SwiftUI 的 `Window(id:)` 场景是懒创建的，只有 `openWindow` 才能创建并打开；
//  而 `openWindow` 只在 Scene 环境内可用（NSPopover / 纯 AppKit 代码里取不到）。
//  此前用"合成 ⌘, 键击触发菜单项"做兜底，但仅菜单栏（accessory）模式下
//  应用菜单栏不显示，键击派发会落空，导致设置窗口打不开。
//
//  做法：在主窗口（ContentView，启动时必定创建）里捕获一次 openWindow 动作，
//  存到本路由，AppKit 侧即可复用它来打开任意窗口 id。
//

import SwiftUI

@MainActor
final class WindowRouter {

    static let shared = WindowRouter()

    private var openAction: ((String) -> Void)?

    private init() {}

    /// 由场景内视图注册（见 installWindowRouter）
    func register(_ action: @escaping (String) -> Void) {
        openAction = action
    }

    /// 打开指定 id 的窗口；未注册成功时返回 false，调用方需自行兜底
    @discardableResult
    func open(id: String) -> Bool {
        guard let action = openAction else { return false }
        action(id)
        return true
    }
}

private struct WindowRouterInstaller: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            WindowRouter.shared.register { id in openWindow(id: id) }
        }
    }
}

extension View {
    /// 挂在主窗口等常驻场景上，捕获 openWindow 动作供 AppKit 侧复用
    func installWindowRouter() -> some View {
        modifier(WindowRouterInstaller())
    }
}
