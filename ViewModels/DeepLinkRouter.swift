//
//  DeepLinkRouter.swift
//  AlphaTrack
//
//  PRD 4.4：Apple 提醒事项 / 日历中写入的 `alphatrack://entry/{uuid}` 深链，
//  由本路由统一解析，并把目标存证投递给主窗口展示复盘详情。
//

import Foundation
import Combine
import SwiftUI

/// 全局深链路由。App 被 URL 唤起或前台接收 URL 时统一走这里。
@MainActor
final class DeepLinkRouter: ObservableObject {

    static let shared = DeepLinkRouter()

    /// URL Scheme，与 Info.plist 的 CFBundleURLSchemes 保持一致
    static let scheme = "alphatrack"

    /// 待打开的存证 UUID（由 onOpenURL 写入，主窗口消费后清空）
    @Published var pendingEntryUUID: UUID?

    /// 是否请求唤起快速录入浮窗
    @Published var requestQuickEntry: Bool = false

    /// 最近一次无法解析的 URL（便于排障展示）
    @Published private(set) var lastRejectedURL: String?

    private init() {}

    // MARK: - 解析入口

    /// 解析 URL。返回 true 表示本 App 已消费该 URL。
    /// - 支持格式：
    ///   - `alphatrack://entry/{uuid}`  打开指定存证复盘详情
    ///   - `alphatrack://new`           唤起快速录入浮窗
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme else {
            return false
        }

        let host = (url.host ?? "").lowercased()
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "entry":
            guard let raw = segments.first, let uuid = UUID(uuidString: raw) else {
                lastRejectedURL = url.absoluteString
                return false
            }
            pendingEntryUUID = uuid
            return true

        case "new", "quick", "quickentry":
            requestQuickEntry = true
            return true

        default:
            lastRejectedURL = url.absoluteString
            return false
        }
    }

    /// 消费并清空待打开条目
    func consumePendingEntryUUID() -> UUID? {
        defer { pendingEntryUUID = nil }
        return pendingEntryUUID
    }

    /// 消费并清空快速录入请求
    func consumeQuickEntryRequest() -> Bool {
        defer { requestQuickEntry = false }
        return requestQuickEntry
    }
}
