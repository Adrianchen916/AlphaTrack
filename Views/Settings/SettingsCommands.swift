//
//  SettingsCommands.swift
//  AlphaTrack
//
//  将系统「设置…」菜单（⌘,）重定向到自定义 settings 窗口，
//  保证设置面板只有一个固定 650pt 宽的入口，避免系统 Settings 场景
//  窗口宽度与内容不一致造成的左右留白。
//

import SwiftUI

struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
