//
//  VisualEffectBackground.swift
//  AlphaTrack
//
//  macOS 原生毛玻璃（NSVisualEffectView）包装：让主面板、设置面板获得原型
//  那种「桌面渐变 + 半透磨砂」的玻璃质感。
//
//  .behindWindow：用于窗口背景，叠加系统壁纸/窗口后面的内容做模糊
//  .withinWindow：用于侧栏/卡片内，模糊同窗口内部下层内容
//

import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}
