//
//  NotificationManager.swift
//  AlphaTrack
//
//  系统通知统一入口
//
//  为什么必须存在这个类：
//  macOS 上的 UNUserNotificationCenter 有一个容易被忽略的默认行为 ——
//  当 App 处于前台（active）时，通知**不会**自动展示，会被系统静默丢弃。
//  只有设置了 delegate 并实现 `willPresent` 回调、显式返回展示选项，前台通知才会弹出。
//
//  AlphaTrack 是菜单栏常驻 App，发通知时往往正处于 active 状态（用户刚点过菜单或窗口打开），
//  因此「目标价到达却不弹通知」的根因就在这里。
//
//  另外 delegate 必须在**任何通知发出之前**设置，因此统一在 App init 最早期调用 `install()`。
//

import Foundation
import Combine
import AppKit
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    static let shared = NotificationManager()

    // MARK: - 可观察状态

    /// 当前系统通知授权状态，供设置界面显示
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// 最近一次发送失败的原因（UI 展示用）
    @Published private(set) var lastError: String?

    /// 已成功发出的通知条数（诊断用，确认链路真的跑通了）
    @Published private(set) var deliveredCount: Int = 0

    // MARK: - 内部

    private override init() {
        super.init()
    }

    // MARK: - 安装（App 启动时最早调用）

    /// 安装通知代理。必须在任何 `send` 调用之前执行，否则前台通知会被系统丢弃。
    func install() {
        UNUserNotificationCenter.current().delegate = self
        NSLog("[AlphaTrack][Notify] delegate 已安装")
        Task { await refreshAuthorizationStatus() }
    }

    /// 刷新当前授权状态到可观察属性
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        NSLog("[AlphaTrack][Notify] 当前授权状态：\(settings.authorizationStatus.debugLabel)")
    }

    /// 首次申请通知权限。已授权 / 已拒绝时不会重复弹窗。
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            NSLog("[AlphaTrack][Notify] 已具备通知权限")
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorizationStatus = granted ? .authorized : .denied
                NSLog("[AlphaTrack][Notify] 授权请求结果：\(granted)")
                return granted
            } catch {
                lastError = "通知权限申请失败：\(error.localizedDescription)"
                NSLog("[AlphaTrack][Notify] 授权失败：\(error.localizedDescription)")
                return false
            }
        case .denied:
            lastError = "系统通知权限被拒绝，请在「系统设置 → 通知 → AlphaTrack」中开启"
            NSLog("[AlphaTrack][Notify] 权限被拒绝")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 发送

    /// 发送系统通知（前台/后台均可展示）
    /// - Parameters:
    ///   - title: 通知标题
    ///   - body: 通知正文
    ///   - identifier: 通知标识。传入 nil 时自动生成带时间戳的唯一 ID，避免同 ID 被系统去重丢弃。
    ///   - playSound: 是否播放系统提示音
    func send(title: String, body: String, identifier: String? = nil, playSound: Bool = true) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            // 未授权时尝试申请一次；仍失败就记录原因，不再静默
            let granted = await requestAuthorizationIfNeeded()
            guard granted else {
                lastError = "无法发送通知：系统通知权限未开启"
                NSLog("[AlphaTrack][Notify] 发送失败：权限未开启")
                return
            }
            return await send(title: title, body: body, identifier: identifier, playSound: playSound)
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        content.interruptionLevel = .timeSensitive

        // 带时间戳的唯一 ID：避免同 identifier 的旧通知仍在通知中心时，新通知被系统丢弃
        let finalID = identifier ?? "alphatrack-\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970))"

        let request = UNNotificationRequest(identifier: finalID, content: content, trigger: nil)

        do {
            try await center.add(request)
            deliveredCount += 1
            lastError = nil
            NSLog("[AlphaTrack][Notify] 已发出通知：\(title)")
        } catch {
            lastError = "通知发送失败：\(error.localizedDescription)"
            NSLog("[AlphaTrack][Notify] 发送失败：\(error.localizedDescription)")
        }
    }

    /// 发送一条用于验证链路的测试通知
    func sendTestNotification() async {
        await send(
            title: "✅ AlphaTrack 通知测试",
            body: "如果你看到这条消息，说明目标价提醒的通知链路已正常。",
            playSound: true
        )
    }

    /// 打开「系统设置 → 通知」，供用户手动开启权限
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 权限文案

    var statusText: String {
        switch authorizationStatus {
        case .authorized: return "已授权"
        case .provisional: return "临时授权"
        case .notDetermined: return "尚未询问"
        case .denied: return "已被拒绝"
        @unknown default: return "未知"
        }
    }

    var statusColor: NSColor {
        switch authorizationStatus {
        case .authorized, .provisional: return .systemGreen
        case .notDetermined: return .systemOrange
        case .denied: return .systemRed
        @unknown default: return .secondaryLabelColor
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// 关键：App 处于前台时，系统询问「这条通知要不要展示」。
    /// 不实现这个方法（或不返回展示选项），前台通知会被静默丢弃。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NSLog("[AlphaTrack][Notify] 前台收到通知，强制展示：\(notification.request.content.title)")
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// 用户点击通知后的回调（预留：可跳转对应存证详情）
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let uuid = userInfo["entryUUID"] as? String {
            NSLog("[AlphaTrack][Notify] 用户点击通知，关联记录：\(uuid)")
            NotificationCenter.default.post(
                name: NSNotification.Name("AlphaTrack_OpenEntry"),
                object: nil,
                userInfo: ["entryUUID": uuid]
            )
        }
        completionHandler()
    }
}

// MARK: - 调试辅助

private extension UNAuthorizationStatus {
    var debugLabel: String {
        switch self {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        @unknown default: return "unknown"
        }
    }
}
