//
//  PredictionEntry.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import Foundation
import SwiftData

// MARK: - 枚举定义 (支持多空与客观事实双轨制、时效与对账)

/// 观点记录类型（双轨制）：方向性预测 vs 客观数据现状观察 (PRD 4.1)
enum EntryType: String, Codable, CaseIterable, Sendable {
    /// 轨 1：方向性预测（看多 / 看空），到期自动对账判定胜负，计入胜率榜
    case prediction = "prediction"
    /// 轨 2：客观数据 / 现状观察（行业数据、链上指标、研报事实），不喊单，不污染胜率
    case factualSnapshot = "factualSnapshot"
    
    var localizedTitle: String {
        switch self {
        case .prediction:
            return "方向预测"
        case .factualSnapshot:
            return "客观数据"
        }
    }
}

/// 预测方向（仅在 entryType == .prediction 时生效）
enum PredictionDirection: String, Codable, CaseIterable, Sendable {
    case bullish = "bullish" // 看多
    case bearish = "bearish" // 看空
    
    var localizedTitle: String {
        switch self {
        case .bullish:
            return "看多"
        case .bearish:
            return "看空"
        }
    }
    
    var symbol: String {
        switch self {
        case .bullish:
            return "▲"
        case .bearish:
            return "▼"
        }
    }
}

/// 客观事实记录下，用户可选的自我衍生主观推论 (PRD 4.1 衍生推论)
enum FactualInferenceDirection: String, Codable, CaseIterable, Sendable {
    case none = "none"       // 纯客观记录，无主观推论
    case bullish = "bullish" // 基于该客观数据，推论偏向看多
    case bearish = "bearish" // 基于该客观数据，推论偏向看空
    
    var localizedTitle: String {
        switch self {
        case .none:
            return "纯客观(无推论)"
        case .bullish:
            return "衍生看多"
        case .bearish:
            return "衍生看空"
        }
    }
}

/// 预设行情分类（原生预设四大类，支持自由自定义扩展）
enum PresetMarketCategory: String, Codable, CaseIterable, Sendable {
    case aShare = "A股"
    case usStock = "美股"
    case hkStock = "港股"
    case crypto = "Crypto"
    case custom = "自定义"
}

/// 有效验证周期 (PRD 4.1 验证时效 - 支持1分钟/5分钟/1小时高频短线与长线)
enum VerificationHorizon: String, Codable, CaseIterable, Sendable {
    case min1 = "1分钟"
    case min5 = "5分钟"
    case min15 = "15分钟"
    case hour1 = "1小时"
    case hours4 = "4小时"
    case hours12 = "12小时"
    case hours24 = "24小时"
    case days3 = "3天"
    case days7 = "7天"
    case days30 = "30天"
    case longTerm = "长期 (3月+)"
    case custom = "自定义"

    /// 快捷周期的预设时间跨度（秒）
    var defaultTimeInterval: TimeInterval? {
        switch self {
        case .min1:
            return 60
        case .min5:
            return 5 * 60
        case .min15:
            return 15 * 60
        case .hour1:
            return 3600
        case .hours4:
            return 4 * 3600
        case .hours12:
            return 12 * 3600
        case .hours24:
            return 24 * 3600
        case .days3:
            return 3 * 24 * 3600
        case .days7:
            return 7 * 24 * 3600
        case .days30:
            return 30 * 24 * 3600
        case .longTerm:
            return 90 * 24 * 3600
        case .custom:
            return nil
        }
    }

    /// 根据创建时间推算预计到期时刻
    func calculatedTargetDate(from startDate: Date = Date()) -> Date {
        if let interval = defaultTimeInterval {
            return startDate.addingTimeInterval(interval)
        } else {
            return startDate.addingTimeInterval(30 * 24 * 3600)
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "1分钟": self = .min1
        case "5分钟": self = .min5
        case "15分钟": self = .min15
        case "1小时": self = .hour1
        case "4小时": self = .hours4
        case "12小时": self = .hours12
        case "24小时": self = .hours24
        case "3天": self = .days3
        case "7天": self = .days7
        case "30天": self = .days30
        case "长期 (3月+)", "长期(季度+)", "长期": self = .longTerm
        case "自定义", "自定义日期": self = .custom
        default: return nil
        }
    }
}

/// 对账判定结果（方向性预测对账）
enum ArbitrationStatus: String, Codable, CaseIterable, Sendable {
    case pending = "进行中"       // 周期内，尚在对账观察中
    case hitEarly = "提前命中"     // 盘中最高价/最低价已触达目标价
    case hit = "到期命中"         // 到期日收盘市价符合预测方向
    case miss = "未命中"          // 到期日收盘市价未符合方向或未达目标
    case expired = "已失效/取消"   // 用户主动取消、标的停牌或数据源异常
    
    var isSettled: Bool {
        switch self {
        case .pending:
            return false
        case .hitEarly, .hit, .miss, .expired:
            return true
        }
    }
    
    var isWin: Bool {
        return self == .hitEarly || self == .hit
    }
}

/// 客观数据事实有效性打标（复盘验真打标 - PRD 4.2）
enum FactCheckStatus: String, Codable, CaseIterable, Sendable {
    case unverified = "待打标"      // 尚未核验
    case verifiedValid = "真实有效"  // 数据属实且被后验验证
    case falsified = "数据失真/伪造"  // 数据不实、口径误导或被官方辟谣
}

// MARK: - PredictionEntry 模型定义

@Model
final class PredictionEntry {
    // MARK: - 唯一标识与时间戳
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - 标的与市场分类 (PRD 4.1 & 4.3)
    /// 标的代码 (如 600519, NVDA, BTC/USDT, 0700.HK)
    var ticker: String = ""
    /// 标的名称 (如 贵州茅台, 英伟达, 比特币)
    var tickerName: String?
    /// 行情分类 (A股、美股、港股、Crypto，或自定义分类如“商品期货”、“外汇”)
    var marketCategory: String = "A股"
    
    // MARK: - 观点属性与多空/客观数据双轨制 (PRD 4.1)
    /// 观点类型 RawValue (EntryType: prediction / factualSnapshot)
    var entryTypeRaw: String = EntryType.prediction.rawValue
    
    /// 预测方向 RawValue (PredictionDirection: bullish / bearish，仅预测模式有效)
    var directionRaw: String? = PredictionDirection.bullish.rawValue
    
    /// 客观数据模式下的“核心事实 / 数据摘要” (如“端午回款进度约70%，批价微跌至2150元”)
    var factualSummary: String?
    
    /// 基于该客观数据，用户可选记录的自我衍生推论 RawValue (FactualInferenceDirection)
    var factualInferenceRaw: String = FactualInferenceDirection.none.rawValue
    
    // MARK: - 价格点位与对账结算
    /// 录入时刻系统锁定的实时基准价格
    var entryPrice: Double = 0.0
    
    /// 目标价位 (选填，仅预测模式生效；若为空则到期按相对基准价涨跌判定)
    var targetPrice: Double?

    /// 目标价到达提醒是否已发送过（去重：同一条记录只弹一次系统通知）
    var targetHitAlerted: Bool = false
    
    /// 结算时市价 (提前命中时的触发价，或到期日收盘价格)
    var settlementPrice: Double?
    
    /// 实际对账/结算完成时间
    var settlementDate: Date?
    
    // MARK: - 验证周期与到期时间 (PRD 4.1)
    /// 有效验证周期 RawValue (VerificationHorizon: 24小时, 7天, 30天, 长期, 自定义)
    var horizonRaw: String = VerificationHorizon.days7.rawValue
    
    /// 预计到期验证时刻 (结合交易日收盘时刻计算)
    var targetDate: Date = Date()
    
    // MARK: - 对账状态与客观数据后验回溯 (PRD 4.2)
    /// 方向性预测对账状态 RawValue (ArbitrationStatus: pending, hitEarly, hit, miss, expired)
    var arbitrationStatusRaw: String = ArbitrationStatus.pending.rawValue
    
    /// 客观数据事实有效性复盘打标 RawValue (FactCheckStatus: unverified, verifiedValid, falsified)
    var factCheckStatusRaw: String = FactCheckStatus.unverified.rawValue
    
    /// 客观数据公布后 7天 / 30天 标的真实市场反应涨跌幅 (百分比，如 +5.6 表示 +5.6%)
    var marketReactionPercent: Double?
    
    /// 客观数据公布后的真实市场波动率百分比 (可选)
    var marketReactionVolatility: Double?
    
    /// 客观数据的市场后验反应是否已完成计算 (避免重复请求行情接口)
    var isReactionAnalyzed: Bool = false

    /// 结算通知是否已发送过（幂等闸门）
    ///
    /// 作用：把「同一条记录只弹一次结算通知」的保证，从依赖上游的状态判断
    /// 下沉到通知出口自身。即使将来新增代码路径（批量重算、数据修复等）再次
    /// 调用 notifySettlement，只要这里已置位就不再重复弹窗。
    ///
    /// 注意：SwiftData 轻量迁移——新增带默认值的 Bool 属性由框架自动处理，
    /// 已有记录读出为 false，不影响存量数据。
    var settlementNotified: Bool = false

    /// 上一次自动对账扫描时间 (对未到期记录做扫描节流，避免高频打行情接口)
    var lastScanAt: Date?
    
    // MARK: - 证据截图 / 图表附件沙盒路径 (PRD 4.1)
    /// 本地安全存储至 App 数据沙盒中的相对路径 (如 "Screenshots/{UUID}.png")
    /// 采用相对路径存储，避免 macOS 容器路径变动或 iCloud 备份恢复后绝对路径失效
    var imageRelativePath: String?
    
    // MARK: - 观点来源与 KOL 归属 (PRD 4.1 & 4.3)
    /// 是否为“我自己的前瞻判断”（单选模式一，免填外部来源）
    var isSelfJudgment: Bool = false
    
    /// 发言人 / 博主 / 券商机构名称快照 (冗余存储，便于脱机或列表快速渲染)
    var authorName: String = "我自己的判断"
    
    /// 关联的 KOL / 来源档案 (一对多关联)
    var sourceProfile: SourceProfile?
    
    // MARK: - Apple 原生生态协同联动 (PRD 4.4)
    /// 是否同步至 Apple 提醒事项 (EventKit)
    var syncToReminders: Bool = false
    /// Apple 提醒事项条目唯一 ID
    var remindersIdentifier: String?
    /// 是否写入系统日历日程
    var syncToCalendar: Bool = false
    /// Apple 日历日程唯一 ID
    var calendarEventIdentifier: String?
    
    // MARK: - 详细备注与研报逻辑
    var notes: String?
    
    // MARK: - 类型安全的计算属性 (Convenience Getters / Setters)
    
    /// 观点类型强类型访问
    var entryType: EntryType {
        get { EntryType(rawValue: entryTypeRaw) ?? .prediction }
        set { entryTypeRaw = newValue.rawValue }
    }
    
    /// 预测方向强类型访问
    var direction: PredictionDirection? {
        get {
            guard let raw = directionRaw else { return nil }
            return PredictionDirection(rawValue: raw)
        }
        set { directionRaw = newValue?.rawValue }
    }
    
    /// 客观数据衍生推论强类型访问
    var factualInference: FactualInferenceDirection {
        get { FactualInferenceDirection(rawValue: factualInferenceRaw) ?? .none }
        set { factualInferenceRaw = newValue.rawValue }
    }
    
    /// 验证周期强类型访问
    var horizon: VerificationHorizon {
        get { VerificationHorizon(rawValue: horizonRaw) ?? .days7 }
        set { horizonRaw = newValue.rawValue }
    }
    
    /// 对账状态强类型访问
    var arbitrationStatus: ArbitrationStatus {
        get { ArbitrationStatus(rawValue: arbitrationStatusRaw) ?? .pending }
        set { arbitrationStatusRaw = newValue.rawValue }
    }
    
    /// 客观事实打标强类型访问
    var factCheckStatus: FactCheckStatus {
        get { FactCheckStatus(rawValue: factCheckStatusRaw) ?? .unverified }
        set { factCheckStatusRaw = newValue.rawValue }
    }
    
    /// 完整沙盒图片 URL
    var fullImageURL: URL? {
        guard let path = imageRelativePath, !path.isEmpty else { return nil }
        return Self.documentsDirectory.appendingPathComponent(path)
    }
    
    /// 沙盒 Documents 目录
    /// 已改为跟随 StorageManager：用户设置自选目录后指向该目录，否则仍是沙盒 Documents
    static var documentsDirectory: URL {
        MainActor.assumeIsolated {
            StorageManager.shared.attachmentsBaseURL
        }
    }
    
    /// 是否已对账结算完毕
    var isSettled: Bool {
        arbitrationStatus.isSettled
    }
    
    /// 预测是否命中 (未结算返回 nil)
    var isHit: Bool? {
        switch arbitrationStatus {
        case .pending, .expired:
            return nil
        case .hitEarly, .hit:
            return true
        case .miss:
            return false
        }
    }
    
    /// 距离到期还剩的时间间隔 (秒，已逾期返回负数)
    var timeRemaining: TimeInterval {
        targetDate.timeIntervalSince(Date())
    }
    
    /// 是否已到期
    var isExpired: Bool {
        timeRemaining <= 0
    }
    
    // MARK: - 初始化方法
    init(
        uuid: UUID = UUID(),
        ticker: String,
        tickerName: String? = nil,
        marketCategory: String = "A股",
        entryType: EntryType = .prediction,
        direction: PredictionDirection? = .bullish,
        factualSummary: String? = nil,
        factualInference: FactualInferenceDirection = .none,
        entryPrice: Double = 0.0,
        targetPrice: Double? = nil,
        horizon: VerificationHorizon = .days7,
        targetDate: Date? = nil,
        imageRelativePath: String? = nil,
        isSelfJudgment: Bool = false,
        authorName: String = "我自己的判断",
        sourceProfile: SourceProfile? = nil,
        syncToReminders: Bool = false,
        syncToCalendar: Bool = false,
        notes: String? = nil
    ) {
        let now = Date()
        self.uuid = uuid
        self.createdAt = now
        self.updatedAt = now
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.tickerName = tickerName
        self.marketCategory = marketCategory
        self.entryTypeRaw = entryType.rawValue
        self.directionRaw = (entryType == .prediction) ? (direction?.rawValue ?? PredictionDirection.bullish.rawValue) : nil
        self.factualSummary = factualSummary
        self.factualInferenceRaw = factualInference.rawValue
        self.entryPrice = entryPrice
        self.targetPrice = (entryType == .prediction) ? targetPrice : nil
        self.horizonRaw = horizon.rawValue
        self.targetDate = targetDate ?? horizon.calculatedTargetDate(from: now)
        self.arbitrationStatusRaw = ArbitrationStatus.pending.rawValue
        self.factCheckStatusRaw = FactCheckStatus.unverified.rawValue
        self.imageRelativePath = imageRelativePath
        self.isSelfJudgment = isSelfJudgment
        self.authorName = isSelfJudgment ? "我自己的判断" : authorName
        self.sourceProfile = isSelfJudgment ? nil : sourceProfile
        self.syncToReminders = syncToReminders
        self.syncToCalendar = syncToCalendar
        self.notes = notes
    }
}

// MARK: - 排序辅助（主面板"活跃进行中"与菜单栏微面板共用）

extension PredictionEntry {
    /// 内置行情分类顺序，与主面板侧栏一致（自定义分类追加在后面）
    static let builtinMarketOrder = ["A股", "美股", "港股", "Crypto"]

    /// 按行情分类顺序排序：一级 = 侧栏分类顺序（A股→美股→港股→Crypto→自定义…），
    /// 二级 = 同分类内按创建时间倒序（最新录入在前）。
    /// 主面板"活跃进行中"与菜单栏微面板都用它，保证两处顺序一致。
    static func sortedByMarketCategory(
        _ entries: [PredictionEntry],
        customCategories: [String] = []
    ) -> [PredictionEntry] {
        let order = builtinMarketOrder + customCategories
        return entries.sorted { a, b in
            let ia = order.firstIndex(of: a.marketCategory) ?? order.count
            let ib = order.firstIndex(of: b.marketCategory) ?? order.count
            if ia != ib { return ia < ib }
            return a.createdAt > b.createdAt
        }
    }
}
