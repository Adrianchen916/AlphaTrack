//
//  ArbitrationEngine.swift
//  AlphaTrack
//
//  PRD 4.2 自动对账引擎 (Arbitration Engine)
//
//  职责：
//  - 扫描全部「进行中」存证，到期自动判定 HIT / MISS
//  - 设定目标价的记录，按周期内逐日盘中高低点检测「提前命中」
//  - 客观数据记录，到期自动计算市场后验反应（涨跌幅 + 年化波动率）
//  - 结算后自动重算 KOL 战绩与 MBTI 人格，并发系统通知
//
//  设计约束：macOS App 未运行时无法执行代码，因此采用
//  「启动全量扫描 + 运行中定时扫描 + 菜单栏常驻宿主」三合一策略。
//  取数失败一律保持「进行中」等下次重试，绝不自动失效。
//

import Foundation
import Combine
import SwiftData
@preconcurrency import UserNotifications

// MARK: - 对账结论

/// 单条记录在本次扫描中的处理结论
enum ArbitrationOutcome {
    /// 被节流跳过（未到期且距上次扫描不足节流窗口）
    case skipped
    /// 未到期，尚无结论
    case pending
    /// 方向性预测已判定胜负
    case settled(ArbitrationStatus)
    /// 客观数据的市场后验反应已计算完成
    case reactionAnalyzed
    /// 取数失败，保持进行中等下次重试
    case failed(String)
}

/// 一次对账扫描的汇总报告
struct ArbitrationRunReport {
    var scanned: Int = 0
    var settled: Int = 0
    var earlyHits: Int = 0
    var reactions: Int = 0
    var failed: Int = 0
    var failures: [String] = []

    var summary: String {
        guard scanned > 0 else { return "无待对账记录" }
        var parts: [String] = ["扫描 \(scanned) 条"]
        if settled > 0 { parts.append("结算 \(settled) 条") }
        if earlyHits > 0 { parts.append("提前命中 \(earlyHits) 条") }
        if reactions > 0 { parts.append("后验分析 \(reactions) 条") }
        if failed > 0 { parts.append("取数失败 \(failed) 条") }
        return parts.joined(separator: " · ")
    }
}

enum ArbitrationError: LocalizedError {
    case notConfigured
    case invalidPrice
    case entryNotFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:  return "对账引擎尚未初始化"
        case .invalidPrice:   return "结算价格必须大于 0"
        case .entryNotFound:  return "未找到对应的存证记录"
        }
    }
}

// MARK: - 自动对账引擎

@MainActor
final class ArbitrationEngine: ObservableObject {

    static let shared = ArbitrationEngine()

    // MARK: 可观察状态（供菜单栏 / 看板展示）

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastReport: ArbitrationRunReport?
    @Published private(set) var lastError: String?

    // MARK: 调度参数

    /// 定时扫描间隔：30 分钟
    private let scanInterval: TimeInterval = 30 * 60
    /// 未到期记录的「提前命中」复扫节流窗口：4 小时（避免高频打行情接口）
    private let earlyScanThrottle: TimeInterval = 4 * 3600

    private var container: ModelContainer?
    private var context: ModelContext?
    private var timer: Timer?

    private init() {}

    // MARK: - 生命周期

    /// 注入 SwiftData 容器。
    ///
    /// 直接使用容器的 `mainContext`，而不是新建独立 ModelContext：
    /// SwiftData 的跨上下文合并在 macOS 14 上不可靠（ModelContext 没有 refresh/merge API），
    /// 独立上下文结算后 UI 的 @Query 会拿到过期对象。共享 mainContext 可让
    /// 结算结果立即反映到看板、菜单栏与复盘详情，无需额外的刷新机制。
    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        self.context = container.mainContext
    }

    /// 启动定时对账（App 启动时调用一次，内部立即跑首轮）
    func startScheduling() {
        guard container != nil else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.runArbitration() }
        }
        Task { await runArbitration() }
    }

    func stopScheduling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 主流程

    func runArbitration() async {
        guard !isRunning else { return }
        guard let context else { return }

        isRunning = true
        defer { isRunning = false }

        let pendingRaw = ArbitrationStatus.pending.rawValue
        let descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { $0.arbitrationStatusRaw == pendingRaw }
        )

        let entries: [PredictionEntry]
        do {
            entries = try context.fetch(descriptor)
        } catch {
            lastError = "读取待对账记录失败：\(error.localizedDescription)"
            return
        }

        var report = ArbitrationRunReport()
        report.scanned = entries.count

        // 客观数据记录不走 arbitrationStatus 结算，需单独纳入扫描
        //
        // ⚠️ 必须同时过滤 entryTypeRaw：isReactionAnalyzed 对方向性预测记录永远是 false，
        // 若只按它过滤，会把「已结算的 HIT / MISS / 提前命中」预测记录一并拉进扫描队列，
        // 导致每轮扫描都重新结算并重复弹系统通知（打开 App 时尤为明显）。
        let factualRaw = EntryType.factualSnapshot.rawValue
        let factualPredicate = #Predicate<PredictionEntry> { entry in
            entry.isReactionAnalyzed == false && entry.entryTypeRaw == factualRaw
        }
        let factualDescriptor = FetchDescriptor<PredictionEntry>(predicate: factualPredicate)
        let factualEntries = (try? context.fetch(factualDescriptor)) ?? []

        // 合并去重：方向性预测（pending）+ 未分析后验反应的客观数据
        var merged: [PredictionEntry] = entries
        let pendingIDs = Set(entries.map { $0.uuid })
        for item in factualEntries where !pendingIDs.contains(item.uuid) {
            merged.append(item)
        }

        for entry in merged {
            let outcome = await process(entry)
            switch outcome {
            case .skipped:
                continue
            case .pending:
                break
            case .settled(let status):
                report.settled += 1
                if status == .hitEarly { report.earlyHits += 1 }
                notifySettlement(entry)
            case .reactionAnalyzed:
                report.reactions += 1
            case .failed(let reason):
                report.failed += 1
                if report.failures.count < 5 {
                    let tickerDisplay = entry.ticker == "—" ? "客观数据" : entry.ticker
                    report.failures.append("\(tickerDisplay)：\(reason)")
                }
            }
        }

        refreshAllProfiles()

        do {
            try context.save()
            lastError = report.failures.isEmpty ? nil : report.failures.joined(separator: "；")
        } catch {
            lastError = "对账结果保存失败：\(error.localizedDescription)"
        }

        lastReport = report
        lastRunAt = Date()
    }

    // MARK: - 单条记录处理

    private func process(_ entry: PredictionEntry) async -> ArbitrationOutcome {
        let now = Date()
        let closing = EventKitService.shared.calculateMarketClosingTime(
            for: entry.targetDate,
            marketCategory: entry.marketCategory
        )

        switch entry.entryType {
        case .prediction:
            return await processPrediction(entry, now: now, closing: closing)
        case .factualSnapshot:
            return await processFactual(entry, now: now, closing: closing)
        }
    }

    /// 方向性预测对账：先查「提前命中」，再查「到期收盘判定」
    private func processPrediction(_ entry: PredictionEntry, now: Date, closing: Date) async -> ArbitrationOutcome {
        // 防御性：若 prediction 记录 ticker 为占位符"—"，按"无标的"处理为跳过
        if entry.ticker == "—" || entry.ticker.isEmpty {
            return .skipped
        }

        // 防御性：已结算（HIT / MISS / 提前命中 / 已失效）的记录不再重复处理。
        // 正常路径只会取 pending，但历史上曾因补充扫描误纳入已结算记录，
        // 导致每轮扫描重新结算并重复弹窗。此处作为第二道保险。
        guard entry.arbitrationStatus == .pending else {
            return .skipped
        }

        // ---- 阶段一：提前命中检测（仅对设定了目标价的记录）----
        if let target = entry.targetPrice, let direction = entry.direction {
            let throttled = entry.lastScanAt.map { now.timeIntervalSince($0) < earlyScanThrottle } ?? false
            if !throttled {
                let scanEnd = min(now, entry.targetDate)
                do {
                    let candles = try await MarketDataService.shared.fetchDailyRange(
                        for: entry.ticker,
                        from: entry.createdAt,
                        to: scanEnd,
                        preferredMarket: entry.marketCategory
                    )
                    entry.lastScanAt = now

                    for candle in candles {
                        let reached: Bool
                        switch direction {
                        case .bullish:
                            reached = (candle.highPrice ?? candle.closePrice) >= target
                        case .bearish:
                            reached = (candle.lowPrice ?? candle.closePrice) <= target
                        }
                        if reached {
                            entry.arbitrationStatus = .hitEarly
                            entry.settlementPrice = target
                            entry.settlementDate = candle.date
                            entry.updatedAt = Date()
                            return .settled(.hitEarly)
                        }
                    }
                } catch {
                    // 取数失败不直接判死：若尚未到期则保持进行中，下次扫描重试
                    if now < closing {
                        return .failed(error.localizedDescription)
                    }
                }
            }
        }

        // ---- 阶段二：到期收盘价判定 ----
        guard now >= closing else { return .pending }

        guard entry.entryPrice > 0 else {
            return .failed("缺少入场基准价，无法自动判定")
        }

        do {
            let quote = try await MarketDataService.shared.fetchHistoricalClose(
                for: entry.ticker,
                on: entry.targetDate,
                preferredMarket: entry.marketCategory
            )
            let direction = entry.direction ?? .bullish
            let won: Bool
            if entry.targetPrice != nil {
                // 设定了目标价但周期内始终未触及 → 判定未命中
                won = false
            } else {
                won = direction == .bullish
                    ? (quote.closePrice > entry.entryPrice)
                    : (quote.closePrice < entry.entryPrice)
            }

            entry.arbitrationStatus = won ? .hit : .miss
            entry.settlementPrice = quote.closePrice
            entry.settlementDate = quote.date
            entry.lastScanAt = now
            entry.updatedAt = Date()
            return .settled(won ? .hit : .miss)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 客观数据后验反应（PRD 4.2）：不产生 HIT / MISS，只计算真实市场反应
    private func processFactual(_ entry: PredictionEntry, now: Date, closing: Date) async -> ArbitrationOutcome {
        // 防御性：后验反应已计算过则直接跳过，避免同一条客观数据被重复分析
        guard !entry.isReactionAnalyzed else {
            return .skipped
        }

        // 跳过无 ticker 的纯事实记录：没有标的无法计算市场反应，留待用户手动打标
        if entry.ticker == "—" || entry.ticker.isEmpty {
            entry.isReactionAnalyzed = true
            entry.lastScanAt = now
            entry.updatedAt = Date()
            return .skipped
        }

        guard now >= closing else { return .pending }

        do {
            let candles = try await MarketDataService.shared.fetchDailyRange(
                for: entry.ticker,
                from: entry.createdAt,
                to: now,
                preferredMarket: entry.marketCategory
            )
            guard !candles.isEmpty else {
                return .failed("区间内无有效交易日数据")
            }

            // 基准价优先取录入时锁定的市价，缺失时退回区间首个交易日收盘价
            let basePrice = entry.entryPrice > 0 ? entry.entryPrice : (candles.first?.closePrice ?? 0)
            guard basePrice > 0 else {
                return .failed("缺少基准价格，无法计算市场反应")
            }

            let lastClose = candles.last?.closePrice ?? basePrice
            entry.marketReactionPercent = (lastClose - basePrice) / basePrice * 100.0
            entry.marketReactionVolatility = annualizedVolatility(candles)
            entry.isReactionAnalyzed = true
            entry.lastScanAt = now
            entry.updatedAt = Date()
            return .reactionAnalyzed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - 提前命中结算（供 PriceAlertMonitor 调用）

    /// 目标价到达时立即结算为「提前命中」。
    ///
    /// 与 `processPrediction` 的阶段一逻辑保持一致，但由价格监控器主动触发，
    /// 避免受 4 小时节流窗口限制导致「价格已到、状态仍显示进行中」的割裂。
    /// - Parameters:
    ///   - entryID: 存证记录 UUID
    ///   - price: 触发时的市价
    /// - Returns: 结算成功返回 true；记录不存在、已结算或无目标价时返回 false
    @discardableResult
    func settleEarlyHit(entryID: UUID, price: Double) -> Bool {
        guard let context else { return false }

        var descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { $0.uuid == entryID }
        )
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first else { return false }

        // 已结算 / 无目标价 / 非方向性预测：不重复结算
        guard entry.arbitrationStatus == .pending,
              entry.entryType == .prediction,
              entry.targetPrice != nil else { return false }

        entry.arbitrationStatus = .hitEarly
        entry.settlementPrice = price
        entry.settlementDate = Date()
        entry.lastScanAt = Date()
        entry.updatedAt = Date()

        refreshAllProfiles()
        try? context.save()
        return true
    }

    // MARK: - 手动结算（自定义分类 / 停牌 / 行情接口不可用）

    /// 手动填入结算价完成对账。用于「自定义」行情分类或长期停牌标的。
    /// - 方向性预测：按结算价与方向判定胜负（设定过目标价则按目标是否达成判定）
    /// - 客观数据：按结算价计算市场后验反应涨跌幅
    @discardableResult
    func manuallySettle(entryID: UUID, price: Double, date: Date = Date()) throws -> ArbitrationStatus? {
        guard let context else { throw ArbitrationError.notConfigured }
        guard price > 0 else { throw ArbitrationError.invalidPrice }

        var descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { $0.uuid == entryID }
        )
        descriptor.fetchLimit = 1
        guard let entry = try context.fetch(descriptor).first else {
            throw ArbitrationError.entryNotFound
        }

        if entry.entryType == .factualSnapshot {
            // 无 ticker 事实存证：缺少基准价无法计算市场反应
            if entry.ticker == "—" || entry.ticker.isEmpty {
                entry.settlementPrice = price
                entry.settlementDate = date
                entry.lastScanAt = date
                entry.updatedAt = Date()
                try context.save()
                return nil
            }
            let base = entry.entryPrice > 0 ? entry.entryPrice : price
            entry.marketReactionPercent = (price - base) / base * 100.0
            entry.isReactionAnalyzed = true
        } else {
            guard entry.entryPrice > 0 else { throw ArbitrationError.invalidPrice }
            let direction = entry.direction ?? .bullish
            let won: Bool
            if let target = entry.targetPrice {
                won = direction == .bullish ? (price >= target) : (price <= target)
            } else {
                won = direction == .bullish ? (price > entry.entryPrice) : (price < entry.entryPrice)
            }
            entry.arbitrationStatus = won ? .hit : .miss
        }

        entry.settlementPrice = price
        entry.settlementDate = date
        entry.lastScanAt = date
        entry.updatedAt = Date()

        refreshAllProfiles()
        try context.save()
        return entry.entryType == .prediction ? entry.arbitrationStatus : nil
    }

    // MARK: - 内部计算

    /// 年化波动率（%）：区间内日收益率标准差 × √252 × 100
    private func annualizedVolatility(_ candles: [HistoricalQuote]) -> Double? {
        guard candles.count >= 3 else { return nil }

        var returns: [Double] = []
        for i in 1..<candles.count {
            let prev = candles[i - 1].closePrice
            let cur = candles[i].closePrice
            guard prev > 0 else { continue }
            returns.append((cur - prev) / prev)
        }
        guard returns.count >= 2 else { return nil }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(returns.count - 1)
        return sqrt(variance) * sqrt(252.0) * 100.0
    }

    /// 重算全部来源的战绩与 MBTI 人格（条目量级小，全量重算最稳妥）
    private func refreshAllProfiles() {
        guard let context else { return }
        guard let profiles = try? context.fetch(FetchDescriptor<SourceProfile>()) else { return }
        for profile in profiles {
            profile.recalculateStatsAndMBTI()
        }
    }

    // MARK: - 系统通知（PRD 场景 C - 现代化并发适配）

    private func notifySettlement(_ entry: PredictionEntry) {
        // 幂等闸门：同一条记录的结算通知只发一次。
        // 置位放在同步代码里（Task 之外），确保能被本轮 runArbitration 末尾的
        // context.save() 持久化；即使通知发送失败也不重试，避免重复弹窗。
        guard !entry.settlementNotified else {
            NSLog("[AlphaTrack][Arbitrate] 结算通知已发过，跳过：\(entry.ticker)")
            return
        }
        entry.settlementNotified = true

        let isWin = entry.arbitrationStatus.isWin
        let statusText = entry.arbitrationStatus.rawValue
        let directionText = entry.direction?.localizedTitle ?? ""
        let priceText = entry.settlementPrice.map { String(format: "%.2f", $0) } ?? "--"
        let author = entry.authorName
        // 无 ticker 时使用"客观数据"作为标的显示文案
        let ticker = entry.ticker == "—" ? "客观数据" : entry.ticker
        let entryUUID = entry.uuid.uuidString

        Task { @MainActor in
            // 交由 NotificationManager 统一发送：它持有 delegate，保证前台也能弹出
            let content = UNMutableNotificationContent()
            content.title = "AlphaTrack 对账完成 · \(statusText)"
            content.body = "\(author) 关于 \(ticker) 的\(directionText)判断已结算，结算价 \(priceText)。"
            content.sound = isWin ? .default : nil
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["entryUUID": entryUUID]

            // identifier 用「稳定 ID（按存证 UUID）」而非时间戳：
            // 同一条记录的结算通知只保留一条，后到的替换先到的，
            // 避免历史记录在通知中心逐条堆叠（曾导致"重复提醒"的观感）。
            let request = UNNotificationRequest(
                identifier: "settle-\(entryUUID)",
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                NSLog("[AlphaTrack][Arbitrate] 结算通知已发出：\(ticker)")
            } catch {
                NSLog("[AlphaTrack][Arbitrate] 结算通知失败：\(error.localizedDescription)")
            }
        }
    }
}
