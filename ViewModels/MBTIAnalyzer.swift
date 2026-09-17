//
//  MBTIAnalyzer.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import Foundation
import SwiftUI
import Combine

// MARK: - 全局语言与外观模式定义 (PRD 5)

/// 界面语言支持 (中 / EN)
enum AppLanguage: String, CaseIterable, Sendable {
    case zh = "zh"
    case en = "en"
    
    var displayName: String {
        switch self {
        case .zh: return "中"
        case .en: return "EN"
        }
    }
}

/// 昼夜双模外观控制器 (PRD 5: ☀️ 白昼 / 🌙 夜间 / 🌓 自动)
enum AppThemeMode: String, CaseIterable, Sendable {
    case light = "light"
    case dark = "dark"
    case auto = "auto"
    
    var icon: String {
        switch self {
        case .light: return "☀️"
        case .dark: return "🌙"
        case .auto: return "🌓"
        }
    }
    
    var localizedName: String {
        switch self {
        case .light: return "白昼"
        case .dark: return "夜间"
        case .auto: return "自动"
        }
    }
}

// MARK: - MBTI 卡片展示视图模型

/// 4 维 MBTI 人格卡片流展示数据实体
struct MBTICardData: Identifiable, Sendable, Equatable {
    let id: UUID
    let authorName: String
    let avatarEmoji: String
    let domainTag: String
    let isSelf: Bool
    
    /// 4位人格代码 (如 BCTA, SCFP, BDTA, BCFP)
    let mbtiCode: String
    /// 中文/英文性格称号 (如 "周期布道者", "Cycle Prophet")
    let mbtiTitle: String
    /// 视觉徽章样式
    let badgeStyle: MBTIBadgeStyle
    /// 特征标签集合
    let tags: [String]
    /// 抄作业与相处指北
    let copilotAdvice: String
    
    // MARK: - 四维坐标百分比 (0.0 ~ 100.0)
    /// 维度 1: 多空立场 (Bullish vs Skeptical)
    let biasBullishPercent: Double
    var biasSkepticalPercent: Double { max(0, 100.0 - biasBullishPercent) }
    
    /// 维度 2: 时间跨度 (Day vs Cycle)
    let horizonCyclePercent: Double
    var horizonDayPercent: Double { max(0, 100.0 - horizonCyclePercent) }
    
    /// 维度 3: 归因内核 (Fundamental vs Technical)
    let driverFundamentalPercent: Double
    var driverTechnicalPercent: Double { max(0, 100.0 - driverFundamentalPercent) }
    
    /// 维度 4: 博弈哲学 (Aggressive vs Prudent)
    let payoffAggressivePercent: Double
    var payoffPrudentPercent: Double { max(0, 100.0 - payoffAggressivePercent) }
    
    // MARK: - 统计战绩
    let totalCount: Int
    let winRate: Double
    let avgDeviationPercent: Double
    let totalFacts: Int
    
    init(
        id: UUID = UUID(),
        authorName: String,
        avatarEmoji: String,
        domainTag: String,
        isSelf: Bool = false,
        mbtiCode: String,
        mbtiTitle: String,
        badgeStyle: MBTIBadgeStyle,
        tags: [String],
        copilotAdvice: String,
        biasBullishPercent: Double,
        horizonCyclePercent: Double,
        driverFundamentalPercent: Double,
        payoffAggressivePercent: Double,
        totalCount: Int,
        winRate: Double,
        avgDeviationPercent: Double,
        totalFacts: Int = 0
    ) {
        self.id = id
        self.authorName = authorName
        self.avatarEmoji = avatarEmoji
        self.domainTag = domainTag
        self.isSelf = isSelf
        self.mbtiCode = mbtiCode
        self.mbtiTitle = mbtiTitle
        self.badgeStyle = badgeStyle
        self.tags = tags
        self.copilotAdvice = copilotAdvice
        self.biasBullishPercent = biasBullishPercent
        self.horizonCyclePercent = horizonCyclePercent
        self.driverFundamentalPercent = driverFundamentalPercent
        self.payoffAggressivePercent = payoffAggressivePercent
        self.totalCount = totalCount
        self.winRate = winRate
        self.avgDeviationPercent = avgDeviationPercent
        self.totalFacts = totalFacts
    }
}

/// 看板顶部核心统计指标
struct DashboardMetrics: Sendable {
    let totalRecords: Int
    /// 以下胜率均为「已结算样本」统计值；无已结算样本时为 nil，界面显示 "--"
    let longTermWinRate: Double?
    let selfWinRate: Double?
    let kolAvgWinRate: Double?

    init(totalRecords: Int, longTermWinRate: Double?, selfWinRate: Double?, kolAvgWinRate: Double?) {
        self.totalRecords = totalRecords
        self.longTermWinRate = longTermWinRate
        self.selfWinRate = selfWinRate
        self.kolAvgWinRate = kolAvgWinRate
    }
}

// MARK: - MBTIAnalyzer 业务逻辑处理器

/// MBTI 认知人格计算引擎与看板状态管理
@MainActor
final class MBTIAnalyzer: ObservableObject {
    
    /// 全局单例
    static let shared = MBTIAnalyzer()
    
    /// 界面语言 (持久化自动记忆)
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "AlphaTrack_Language")
        }
    }
    
    /// 昼夜外观主题 (持久化自动记忆)
    @Published var themeMode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "AlphaTrack_ThemeMode")
        }
    }
    
    /// 选中的左侧边栏过滤类型
    @Published var selectedFilter: SidebarFilter = .allAssets
    
    /// 看板视图子 Tab (认知人格 MBTI 矩阵 vs 详细战绩列表)
    @Published var selectedSubTab: DashboardSubTab = .mbtiMatrix
    
    enum DashboardSubTab: String, CaseIterable, Sendable {
        case mbtiMatrix = "mbti"
        case ledgerTable = "table"
    }
    
    enum SidebarFilter: Hashable, Sendable {
        case allAssets          // 全部资产概览 (存证流水)
        case activeOnly         // 活跃进行中 (存证流水)
        case settledOnly        // 已结算对账 (存证流水)
        case market(String)     // 指定行情分类 (A股、美股、港股、Crypto、自定义)
        case myCalibration      // 我的认知校准
        case kolLeaderboard     // KOL 战绩红黑榜
        case mbtiRadar          // 认知人格 (MBTI)
        case sourceManager      // 来源档案管理 (整合进主面板)
    }
    
    init() {
        let savedLang = UserDefaults.standard.string(forKey: "AlphaTrack_Language") ?? AppLanguage.zh.rawValue
        self.language = AppLanguage(rawValue: savedLang) ?? .zh
        
        let savedTheme = UserDefaults.standard.string(forKey: "AlphaTrack_ThemeMode") ?? AppThemeMode.auto.rawValue
        self.themeMode = AppThemeMode(rawValue: savedTheme) ?? .auto
    }
    
    // MARK: - 核心计算方法 (PRD 4.3 MBTI 算法)
    
    /// 根据 SwiftData 持久化的 SourceProfile 档案与存证预测记录，计算 MBTI 卡片流数据
    /// 注意：此方法在 View 渲染时调用，严禁调用修改 SwiftData 实体的变异方法（如 profile.recalculateStatsAndMBTI()），
    /// 否则会触发 SwiftData 上下文变更广播，导致 SwiftUI 陷入无限重绘循环与主线程严重卡顿。
    func analyzeProfiles(
        profiles: [SourceProfile],
        entries: [PredictionEntry],
        marketFilter: String? = nil
    ) -> [MBTICardData] {
        var cardResults: [MBTICardData] = []
        
        // 1. 如果用户已录入或保存了 SourceProfile，使用真实数据计算
        for profile in profiles {
            // 如果指定了市场过滤，检查关联记录是否包含该市场
            if let targetMarket = marketFilter, targetMarket != "全部" {
                let hasMarket = profile.predictions?.contains { $0.marketCategory == targetMarket } ?? false
                if !hasMarket && !profile.domainTag.contains(targetMarket) {
                    continue
                }
            }
            
            let card = MBTICardData(
                id: profile.uuid,
                authorName: profile.name,
                avatarEmoji: profile.avatarEmoji,
                domainTag: profile.domainTag,
                isSelf: profile.isSelf,
                mbtiCode: profile.mbtiCode.isEmpty ? "SCFP" : profile.mbtiCode,
                mbtiTitle: profile.mbtiTitle.isEmpty ? "价值守门人" : profile.mbtiTitle,
                badgeStyle: profile.mbtiBadgeStyle,
                tags: profile.mbtiTags.isEmpty ? ["#稳健复盘"] : profile.mbtiTags,
                copilotAdvice: profile.copilotAdvice.isEmpty ? "建议参考基本面逻辑" : profile.copilotAdvice,
                biasBullishPercent: profile.biasBullishScore,
                horizonCyclePercent: profile.horizonCycleScore,
                driverFundamentalPercent: profile.driverFundamentalScore,
                payoffAggressivePercent: profile.payoffAggressiveScore,
                totalCount: profile.totalPredictionsCount + profile.totalFactsCount,
                winRate: profile.winRate,
                avgDeviationPercent: profile.averageDeviationPercent,
                totalFacts: profile.totalFactsCount
            )
            cardResults.append(card)
        }
        
        // 无档案时返回空数组，由界面展示空态引导，不再注入原型演示数据
        return cardResults
    }
    
    /// 计算看板顶部四大核心指标 (PRD 4.3 核心指标卡)
    func calculateDashboardMetrics(entries: [PredictionEntry], profiles: [SourceProfile]) -> DashboardMetrics {
        let total = entries.count

        // 长期 (>30天 或 longTerm) 胜率
        let longTermEntries = entries.filter { $0.horizon == .longTerm || $0.horizon == .days30 }
        let longTermSettled = longTermEntries.filter { $0.arbitrationStatus.isSettled }
        let longTermWins = longTermSettled.filter { $0.arbitrationStatus.isWin }.count
        let longRate: Double? = longTermSettled.isEmpty
            ? nil
            : (Double(longTermWins) / Double(longTermSettled.count) * 100.0)

        // 个人胜率
        let selfEntries = entries.filter { $0.isSelfJudgment }
        let selfSettled = selfEntries.filter { $0.arbitrationStatus.isSettled }
        let selfWins = selfSettled.filter { $0.arbitrationStatus.isWin }.count
        let selfRate: Double? = selfSettled.isEmpty
            ? nil
            : (Double(selfWins) / Double(selfSettled.count) * 100.0)

        // KOL 平均胜率
        let kolEntries = entries.filter { !$0.isSelfJudgment }
        let kolSettled = kolEntries.filter { $0.arbitrationStatus.isSettled }
        let kolWins = kolSettled.filter { $0.arbitrationStatus.isWin }.count
        let kolRate: Double? = kolSettled.isEmpty
            ? nil
            : (Double(kolWins) / Double(kolSettled.count) * 100.0)

        return DashboardMetrics(
            totalRecords: total,
            longTermWinRate: longRate,
            selfWinRate: selfRate,
            kolAvgWinRate: kolRate
        )
    }
    
}
