//
//  PriceAlertMonitor.swift
//  AlphaTrack
//
//  目标价到达提醒监控器
//
//  与 ArbitrationEngine 的分工：
//  - ArbitrationEngine：低频（30 分钟扫描 + 4 小时节流）的对账判定，负责最终 HIT / MISS
//  - PriceAlertMonitor：高频（默认 3 分钟）轮询实时价，价格触及目标价时立即提醒 + 提前结算
//
//  两者通过 `PredictionEntry.targetHitAlerted` 去重，保证同一条记录只弹一次通知。
//

import Foundation
import Combine
import SwiftData
import AppKit
@preconcurrency import UserNotifications

// MARK: - 提醒开关与轮询间隔

enum PriceAlertInterval: String, CaseIterable, Identifiable, Sendable {
    case min1 = "1 分钟"
    case min3 = "3 分钟"
    case min5 = "5 分钟"
    case min15 = "15 分钟"

    var id: String { rawValue }

    var timeInterval: TimeInterval {
        switch self {
        case .min1: return 60
        case .min3: return 3 * 60
        case .min5: return 5 * 60
        case .min15: return 15 * 60
        }
    }

    /// 界面上的风险提示（1 分钟轮询会显著增加行情接口请求量）
    var caution: String? {
        switch self {
        case .min1: return "1 分钟轮询会频繁请求行情接口，可能触发限流"
        case .min3: return nil
        case .min5: return nil
        case .min15: return "15 分钟轮询较省资源，但提醒延迟较高"
        }
    }
}

// MARK: - PriceAlertMonitor

@MainActor
final class PriceAlertMonitor: ObservableObject {

    static let shared = PriceAlertMonitor()

    // MARK: 可观察状态

    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var interval: PriceAlertInterval = .min3
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var monitoredCount: Int = 0
    @Published private(set) var lastError: String?
    /// 最近一次检查的可读摘要（供设置界面确认链路真的跑过）
    @Published private(set) var lastCheckSummary: String?

    // MARK: 内部

    private var container: ModelContainer?
    private var timer: Timer?

    private let enabledKey = "AlphaTrack.PriceAlertEnabled"
    private let intervalKey = "AlphaTrack.PriceAlertInterval"

    private init() {
        if let saved = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            isEnabled = saved
        }
        if let raw = UserDefaults.standard.string(forKey: intervalKey),
           let saved = PriceAlertInterval(rawValue: raw) {
            interval = saved
        }
    }

    // MARK: - 生命周期

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// 启动监控（App 启动时调用，内部立即跑首轮）
    func start() {
        guard container != nil else { return }
        restartTimer()
        Task { await checkNow() }
    }

    /// 应用设置改动（开关 / 间隔）
    func applySettings(enabled: Bool, interval: PriceAlertInterval) {
        isEnabled = enabled
        self.interval = interval
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        UserDefaults.standard.set(interval.rawValue, forKey: intervalKey)

        if enabled {
            restartTimer()
            Task { await checkNow() }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval.timeInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.checkNow() }
        }
        // 关键：显式加到 .common 模式。
        // scheduledTimer 默认只加 .default 模式，菜单栏下拉、窗口拖拽等事件追踪模式下定时器会暂停，
        // 导致「App 开着但从不检查」的假死现象。
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("[AlphaTrack][Alert] 定时器已启动，间隔 \(interval.rawValue)")
    }

    // MARK: - 核心扫描

    /// 立即检查一轮（供定时器、设置页按钮、菜单栏「立即对账」共用）
    /// - Parameter force: true 时即使对账引擎正在运行也执行（手动触发用），避免用户点了没反应
    func checkNow(force: Bool = false) async {
        guard isEnabled, let container else {
            NSLog("[AlphaTrack][Alert] 跳过：未启用或容器未配置")
            return
        }
        if !force, ArbitrationEngine.shared.isRunning {
            NSLog("[AlphaTrack][Alert] 跳过：对账引擎正在运行")
            return
        }

        let context = container.mainContext

        // 只取「未结算 + 有目标价 + 尚未提醒过」的方向性预测
        let descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { entry in
                entry.targetPrice != nil &&
                entry.targetHitAlerted == false &&
                entry.entryTypeRaw == "prediction"
            }
        )
        guard let entries = try? context.fetch(descriptor) else {
            lastError = "读取待监控记录失败"
            return
        }

        // 过滤掉已结算的（arbitrationStatusRaw 为 pending 才算进行中）
        let active = entries.filter { $0.arbitrationStatusRaw == ArbitrationStatus.pending.rawValue }
        monitoredCount = active.count
        NSLog("[AlphaTrack][Alert] 本轮监控 \(active.count) 条")

        guard !active.isEmpty else {
            lastCheckedAt = Date()
            lastCheckSummary = "无待监控记录（需要：方向性预测 + 已设目标价 + 未结算）"
            lastError = nil
            return
        }

        // 按 ticker 去重后批量拉实时价（携带市场分类，避免 A 股被误路由到美股源）
        var marketByTicker: [String: String] = [:]
        for entry in active where !entry.ticker.isEmpty && entry.ticker != "—" {
            marketByTicker[entry.ticker] = entry.marketCategory
        }
        let items = marketByTicker.map { (ticker: $0.key, preferredMarket: $0.value) }

        guard !items.isEmpty else {
            lastCheckedAt = Date()
            lastCheckSummary = "待监控记录均无有效标的（无 ticker）"
            lastError = nil
            return
        }

        let results = await MarketDataService.shared.batchFetchQuotes(for: items)

        // 取价失败的标的汇总出来，便于在设置页定位是接口问题还是逻辑问题
        let failures = results.compactMap { (ticker, res) -> String? in
            if case .failure(let err) = res { return "\(ticker): \(err.localizedDescription)" }
            return nil
        }

        var hitCount = 0
        for entry in active {
            guard case .success(let quote) = results[entry.ticker] else { continue }
            guard let target = entry.targetPrice,
                  let direction = entry.direction else { continue }

            let reached: Bool
            switch direction {
            case .bullish:
                reached = quote.price >= target
            case .bearish:
                reached = quote.price <= target
            }

            NSLog("[AlphaTrack][Alert] \(entry.ticker) 现价 \(quote.price) / 目标 \(target) · 方向 \(direction == .bullish ? "看多" : "看空") · 命中=\(reached)")

            guard reached else { continue }

            // 1) 标记已提醒（先写再结算，防止结算失败时重复弹窗）
            entry.targetHitAlerted = true

            // 2) 立即结算为提前命中，保证状态与提醒一致
            let settled = ArbitrationEngine.shared.settleEarlyHit(entryID: entry.uuid, price: quote.price)
            NSLog("[AlphaTrack][Alert] \(entry.ticker) 提前命中结算：\(settled)")

            // 3) 发系统通知（交由 NotificationManager 统一处理，前台也能弹出）
            await notifyTargetHit(entry: entry, price: quote.price, target: target)
            hitCount += 1
        }

        if hitCount > 0 {
            try? context.save()
        }

        lastCheckedAt = Date()
        if !failures.isEmpty {
            lastError = "取价失败：\(failures.joined(separator: "；"))"
        } else if lastError?.hasPrefix("取价失败") == true {
            lastError = nil
        }
        lastCheckSummary = "检查 \(items.count) 个标的，命中 \(hitCount) 条"
        NSLog("[AlphaTrack][Alert] 本轮结束：\(lastCheckSummary ?? "")")
    }

    // MARK: - 通知

    /// 发送「目标价到达」系统通知
    ///
    /// 统一走 NotificationManager：它持有 UNUserNotificationCenterDelegate，
    /// 能保证 App 处于前台时通知依然弹出（否则会被系统静默丢弃）。
    private func notifyTargetHit(entry: PredictionEntry, price: Double, target: Double) async {
        let directionText = entry.direction == .bearish ? "看空" : "看多"
        let tickerDisplay = entry.ticker == "—" ? "客观数据存证" : entry.ticker
        let entryUUID = entry.uuid.uuidString

        let content = UNMutableNotificationContent()
        content.title = "🎯 目标价已到达 · \(tickerDisplay)"
        content.body = String(
            format: "%@ 目标价 %.2f 已触及，当前 %.2f（%@ · %@）",
            tickerDisplay, target, price, directionText, entry.authorName
        )
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["entryUUID": entryUUID]

        // identifier 带时间戳：避免同 ID 的旧通知仍在通知中心时新通知被系统丢弃
        let request = UNNotificationRequest(
            identifier: "target-hit-\(entryUUID)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            NSLog("[AlphaTrack][Alert] 目标价通知已发出：\(tickerDisplay)")
        } catch {
            lastError = "通知发送失败：\(error.localizedDescription)"
            NSLog("[AlphaTrack][Alert] 通知发送失败：\(error.localizedDescription)")
        }

        // 系统提示音兜底：即使通知被系统的专注模式/勿扰静音，用户也能听到
        NSSound(named: .init("Glass"))?.play()
    }

    /// 首次启动时申请通知权限（交由 NotificationManager 统一处理）
    func requestAuthorizationIfNeeded() async {
        await NotificationManager.shared.requestAuthorizationIfNeeded()
    }
}
