//
//  NSScrollView+OverlayScroller.swift
//  AlphaTrack
//
//  App 内强制所有滚动视图使用 overlay 细圆条（原型 v4 的 hover 细条视觉），
//  不影响系统其它应用。通过 swizzle NSScrollView 的 tile 方法，
//  在每次布局时把 scrollerStyle 校正为 .overlay。
//

import AppKit
import ObjectiveC.runtime

extension NSScrollView {
    private static let swizzleOverlayScroller: Void = {
        let original = #selector(NSScrollView.tile)
        let swizzled = #selector(NSScrollView.at_overlay_tile)

        guard
            let originalMethod = class_getInstanceMethod(NSScrollView.self, original),
            let swizzledMethod = class_getInstanceMethod(NSScrollView.self, swizzled)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// App 启动时调用一次，强制 overlay 滚动条
    static func enableOverlayScrollers() {
        _ = swizzleOverlayScroller
    }

    @objc private func at_overlay_tile() {
        // 先调用原实现（交换后此处即指向原 tile）
        at_overlay_tile()

        if scrollerStyle != .overlay {
            scrollerStyle = .overlay
        }
    }
}
