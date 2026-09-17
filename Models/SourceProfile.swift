//
//  SourceProfile.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import Foundation
import SwiftData

// MARK: - MBTI 人格体系相关辅助定义 (PRD 4.3)

/// 投资认知 MBTI 徽章视觉风格
enum MBTIBadgeStyle: String, Codable, Sendable {
    case prophet = "badge-prophet"   // 周期布道者 (紫色/高贵)
    case sentinel = "badge-sentinel" // 价值守门人 (蓝色/稳健)
    case charger = "badge-charger"   // 动量冲锋枪 (红色/进攻)
    case selfJudge = "badge-self"    // 自我校准 (绿色/中立)
}

/// MBTI 16 种典型性格画像元数据
struct MBTIProfileInfo: Sendable {
    let code: String
    let title: String
    let summary: String
    let advice: String
    let defaultTags: [String]
    let badgeStyle: MBTIBadgeStyle
}

// MARK: - SourceProfile 模型定义

@Model
final class SourceProfile {
    // MARK: - 基础标识与元数据
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - 博主 / 机构基本资料 (PRD 4.1 & 4.3)
    /// 博主 / 机构 / 来源名称 (如 "@PlanB (S2F 模型)", "中金研报", "我自己的判断")
    var name: String = ""
    
    /// 头像 Emoji (默认 "⚡", 常用如 "🏛️", "🦁", "🧠", "📊", "🎯")
    var avatarEmoji: String = "⚡"
    
    /// 自定义头像本地沙盒相对路径 (可选)
    var avatarImagePath: String?
    
    /// 来源发布平台 (如 "Twitter/X", "微信公众号", "微博", "券商研报", "社群", "自主思考")
    var platform: String = "Twitter/X"
    
    /// 是否为当前登录用户自身的判断档案（模式一专属，用于自我认知校准）
    var isSelf: Bool = false
    
    /// 是否星标置顶（优先展示在 HUD 录入浮窗的快捷胶囊中，默认前 4–6 个）
    var isPinned: Bool = false
    
    /// 别名 / 同人马甲列表（支持合并同一个人在不同社交平台的账号）
    var aliasNames: [String] = []
    
    /// 专注领域与市场标签（如 "加密货币 / 宏观流动性", "A股消费 / 白酒", "美股半导体 / AI"）
    var domainTag: String = "多市场"
    
    /// 个人备注与研报观察
    var notes: String?
    
    /// 最近一次被选用的时间（用于快捷胶囊根据最近活跃度快速排序）
    var lastUsedAt: Date = Date()
    
    // MARK: - 历史战绩统计与缓存字段 (Credibility Ledger - PRD 4.3)
    /// 累计方向性预测总数
    var totalPredictionsCount: Int = 0
    /// 命中预测总数 (提前命中 + 到期命中)
    var winCount: Int = 0
    /// 未命中预测总数
    var lossCount: Int = 0
    /// 客观事实 / 现状观察总记录数 (不参与胜率计算)
    var totalFactsCount: Int = 0
    /// 历史预测平均偏离幅度百分比 (%)
    var averageDeviationPercent: Double = 0.0
    
    // MARK: - KOL 投资认知人格 MBTI 四维评分字段 (PRD 4.3 - 核心特色)
    /// 维度 1: 多空立场 (Directional Bias)
    /// 范围: 0.0 ~ 100.0。
    /// 分数越高越偏向 B (Bullish 多头信仰，牛市坚定看多)；分数越低越偏向 S (Skeptical 谨慎/防守做空)。
    var biasBullishScore: Double = 50.0
    
    /// 维度 2: 时间跨度 (Horizon)
    /// 范围: 0.0 ~ 100.0。
    /// 分数越高越偏向 C (Cycle 宏观大周期/长线持有)；分数越低越偏向 D (Day/Swing 敏锐短线/波段交易)。
    var horizonCycleScore: Double = 50.0
    
    /// 维度 3: 归因内核 (Analytical Driver)
    /// 范围: 0.0 ~ 100.0。
    /// 分数越高越偏向 F (Fundamental 基本面/研报/客观数据驱动)；分数越低越偏向 T (Technical 图表K线/链上量化模型)。
    var driverFundamentalScore: Double = 50.0
    
    /// 维度 4: 博弈哲学 (Payoff)
    /// 范围: 0.0 ~ 100.0。
    /// 分数越高越偏向 A (Aggressive 激进赔率/高弹性/重仓突破)；分数越低越偏向 P (Prudent 稳健胜率/确定性/严防守)。
    var payoffAggressiveScore: Double = 50.0
    
    /// 人格特征标签集合 (如 ["宏观牛市强", "熊市易死扛", "高赔率", "链上模型"])
    var mbtiTags: [String] = []
    
    /// Copilot 相处与抄作业指南 / 避坑指南缓存
    var copilotAdvice: String = ""
    
    // MARK: - 关联关系 (One-to-Many: 一个来源拥有多条存证记录)
    /// 关联的所有预测与事实存证记录
    @Relationship(deleteRule: .nullify, inverse: \PredictionEntry.sourceProfile)
    var predictions: [PredictionEntry]? = []
    
    // MARK: - 计算属性与战绩统计
    
    /// 历史真实命中率 (百分比，0.0 ~ 100.0；若无已结算预测则返回 0.0)
    var winRate: Double {
        let settledCount = winCount + lossCount
        guard settledCount > 0 else { return 0.0 }
        return (Double(winCount) / Double(settledCount)) * 100.0
    }
    
    /// 活跃中的预测总数
    var activePredictionsCount: Int {
        guard let list = predictions else { return 0 }
        return list.filter { $0.arbitrationStatus == .pending }.count
    }
    
    /// 多空立场反向分 (Skeptical 谨慎做空得分: 0~100)
    var biasSkepticalScore: Double {
        max(0.0, min(100.0, 100.0 - biasBullishScore))
    }
    
    /// 时间跨度反向分 (Day/Swing 短线得分: 0~100)
    var horizonDayScore: Double {
        max(0.0, min(100.0, 100.0 - horizonCycleScore))
    }
    
    /// 归因内核反向分 (Technical 技术图表得分: 0~100)
    var driverTechnicalScore: Double {
        max(0.0, min(100.0, 100.0 - driverFundamentalScore))
    }
    
    /// 博弈哲学反向分 (Prudent 稳健确定性得分: 0~100)
    var payoffPrudentScore: Double {
        max(0.0, min(100.0, 100.0 - payoffAggressiveScore))
    }
    
    // MARK: - MBTI 认知人格综合计算 (PRD 4.3 16 种性格画像映射)
    
    /// 4位 MBTI 性格字母代码 (如 "BCTA", "SCFP", "BDTA", "STFP")
    var mbtiCode: String {
        let bOrS = biasBullishScore >= 50.0 ? "B" : "S"
        let dOrC = horizonCycleScore >= 50.0 ? "C" : "D"
        let fOrT = driverFundamentalScore >= 50.0 ? "F" : "T"
        let aOrP = payoffAggressiveScore >= 50.0 ? "A" : "P"
        return "\(bOrS)\(dOrC)\(fOrT)\(aOrP)"
    }
    
    /// MBTI 完整性格画像元数据
    var mbtiProfile: MBTIProfileInfo {
        Self.lookupMBTIProfile(for: mbtiCode)
    }
    
    /// MBTI 中文性格称号 (如 "周期布道者", "价值守门人", "动量冲锋枪", "逆向排雷兵")
    var mbtiTitle: String {
        mbtiProfile.title
    }
    
    /// MBTI 徽章样式类名 (用于 SwiftUI 或 Web 原型高亮着色)
    var mbtiBadgeStyle: MBTIBadgeStyle {
        if isSelf { return .selfJudge }
        return mbtiProfile.badgeStyle
    }
    
    // MARK: - 初始化方法
    init(
        uuid: UUID = UUID(),
        name: String,
        avatarEmoji: String = "⚡",
        avatarImagePath: String? = nil,
        platform: String = "Twitter/X",
        isSelf: Bool = false,
        isPinned: Bool = false,
        aliasNames: [String] = [],
        domainTag: String = "多市场",
        notes: String? = nil,
        biasBullishScore: Double = 50.0,
        horizonCycleScore: Double = 50.0,
        driverFundamentalScore: Double = 50.0,
        payoffAggressiveScore: Double = 50.0
    ) {
        let now = Date()
        self.uuid = uuid
        self.createdAt = now
        self.updatedAt = now
        self.lastUsedAt = now
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarEmoji = avatarEmoji
        self.avatarImagePath = avatarImagePath
        self.platform = platform
        self.isSelf = isSelf
        self.isPinned = isPinned
        self.aliasNames = aliasNames
        self.domainTag = domainTag
        self.notes = notes
        self.biasBullishScore = biasBullishScore
        self.horizonCycleScore = horizonCycleScore
        self.driverFundamentalScore = driverFundamentalScore
        self.payoffAggressiveScore = payoffAggressiveScore
        
        let initialProfile = Self.lookupMBTIProfile(for: self.mbtiCode)
        self.mbtiTags = initialProfile.defaultTags
        self.copilotAdvice = initialProfile.advice
    }
    
    // MARK: - 战绩指标与 MBTI 动态推算引擎 (PRD 4.2 & 4.3)
    
    /// 根据关联的全部存证预测与客观数据记录，自动重新计算胜率战绩与四维 MBTI 评分
    func recalculateStatsAndMBTI() {
        guard let list = predictions, !list.isEmpty else {
            return
        }
        
        var totalPreds = 0
        var wins = 0
        var losses = 0
        var totalFacts = 0
        var totalDeviation = 0.0
        var deviationCount = 0
        
        // MBTI 原始权重累加器
        var bullishCount = 0
        var bearishCount = 0
        var horizonCycleSum = 0.0
        var fundamentalCount = 0
        var technicalCount = 0
        var payoffAggressiveSum = 0.0
        var payoffCount = 0
        
        for item in list {
            if item.entryType == .factualSnapshot {
                totalFacts += 1
                // 客观事实大幅提升 Fundamental (基本面/客观数据) 归因得分 (PRD 4.2)
                fundamentalCount += 3
            } else {
                totalPreds += 1
                
                // 胜负统计
                if item.arbitrationStatus.isWin {
                    wins += 1
                } else if item.arbitrationStatus == .miss {
                    losses += 1
                }
                
                // 多空立场
                if item.direction == .bullish {
                    bullishCount += 1
                } else if item.direction == .bearish {
                    bearishCount += 1
                }
                
                // 周期跨度推算 (长期加权大周期，超短线加权波段)
                switch item.horizon {
                case .min1, .min5, .min15:
                    horizonCycleSum += 2.0
                case .hour1, .hours4:
                    horizonCycleSum += 3.0
                case .hours12:
                    horizonCycleSum += 4.0
                case .hours24:
                    horizonCycleSum += 5.0
                case .days3:
                    horizonCycleSum += 15.0
                case .days7:
                    horizonCycleSum += 25.0
                case .days30:
                    horizonCycleSum += 65.0
                case .longTerm:
                    horizonCycleSum += 95.0
                case .custom:
                    horizonCycleSum += 50.0
                }
                
                // 归因：根据备注或图片附件识别
                if item.imageRelativePath != nil {
                    technicalCount += 1 // 截图图表偏向 Technical
                } else {
                    fundamentalCount += 1
                }
                
                // 赔率哲学：依据目标价相对基准价的预期涨跌幅度
                if let target = item.targetPrice, item.entryPrice > 0 {
                    let diffPercent = abs(target - item.entryPrice) / item.entryPrice * 100.0
                    totalDeviation += diffPercent
                    deviationCount += 1
                    
                    // 涨幅目标 > 25% 视为激进 A，< 10% 视为稳健 P
                    if diffPercent >= 25.0 {
                        payoffAggressiveSum += 85.0
                    } else if diffPercent <= 10.0 {
                        payoffAggressiveSum += 25.0
                    } else {
                        payoffAggressiveSum += 50.0
                    }
                    payoffCount += 1
                }
            }
        }
        
        // 更新战绩统计
        self.totalPredictionsCount = totalPreds
        self.winCount = wins
        self.lossCount = losses
        self.totalFactsCount = totalFacts
        self.averageDeviationPercent = deviationCount > 0 ? (totalDeviation / Double(deviationCount)) : 0.0
        
        // 更新 MBTI 维度 1: 多空立场 (B vs S)
        let totalDirectional = bullishCount + bearishCount
        if totalDirectional > 0 {
            self.biasBullishScore = (Double(bullishCount) / Double(totalDirectional)) * 100.0
        }
        
        // 更新 MBTI 维度 2: 周期跨度 (D vs C)
        if totalPreds > 0 {
            self.horizonCycleScore = horizonCycleSum / Double(totalPreds)
        }
        
        // 更新 MBTI 维度 3: 归因内核 (F vs T)
        let totalDriver = fundamentalCount + technicalCount
        if totalDriver > 0 {
            self.driverFundamentalScore = (Double(fundamentalCount) / Double(totalDriver)) * 100.0
        }
        
        // 更新 MBTI 维度 4: 博弈哲学 (A vs P)
        if payoffCount > 0 {
            self.payoffAggressiveScore = payoffAggressiveSum / Double(payoffCount)
        }
        
        // 刷新性格档案与相处指南
        let updatedProfile = Self.lookupMBTIProfile(for: self.mbtiCode)
        self.mbtiTags = updatedProfile.defaultTags
        self.copilotAdvice = updatedProfile.advice
        self.updatedAt = Date()
    }
    
    // MARK: - 同人马甲合并 (PRD 4.3)

    /// 将另一个档案（同一个人的小号/马甲）合并进本档案：
    /// 迁移其全部存证，并把其名称与别名并入本档案的别名表，最后重算战绩与 MBTI。
    /// 调用方负责删除被合并的档案。
    func absorb(_ other: SourceProfile) {
        guard other !== self else { return }

        if let list = other.predictions {
            for entry in list {
                entry.sourceProfile = self
            }
        }

        var merged = aliasNames
        for candidate in ([other.name] + other.aliasNames) {
            let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean != name, !merged.contains(clean) else { continue }
            merged.append(clean)
        }
        aliasNames = merged

        updatedAt = Date()
        recalculateStatsAndMBTI()
    }

    // MARK: - 16 种 MBTI 认知人格数据库映射

    static func lookupMBTIProfile(for code: String) -> MBTIProfileInfo {
        switch code.uppercased() {
        // --- B 系列 (多头信仰) ---
        case "BCTA":
            return MBTIProfileInfo(
                code: "BCTA",
                title: "周期布道者",
                summary: "牛市信仰极强，宏观大周期嗅觉敏锐，高弹性进攻；但在熊市拐点易盲目乐观死扛。",
                advice: "牛市可重点参考其大方向定力；熊市警惕其‘永远在底背离’的执念，须严格执行独立移动止损。",
                defaultTags: ["牛市信仰强", "宏观大周期", "高弹性赔率", "链上/模型派"],
                badgeStyle: .prophet
            )
        case "BCTP":
            return MBTIProfileInfo(
                code: "BCTP",
                title: "趋势长跑者",
                summary: "宏观多头格局，深信复利与周期演进，崇尚系统化稳健持有。",
                advice: "非常适合作为长线定投底仓的定心丸，不宜用其判断短期交易买卖点。",
                defaultTags: ["趋势长跑", "稳健防守", "宏观叙事", "大周期"],
                badgeStyle: .prophet
            )
        case "BCFA":
            return MBTIProfileInfo(
                code: "BCFA",
                title: "宏观拓荒者",
                summary: "立足产业基本面与大变革，敢于在无人问津处重仓押注未来超级赛道。",
                advice: "观点极具启发性与赔率空间，但左侧潜伏期极长，需要做好 1-2 年的时间成本准备。",
                defaultTags: ["产业先锋", "基本面重仓", "长期高赔率", "耐心潜伏"],
                badgeStyle: .prophet
            )
        case "BCFP":
            return MBTIProfileInfo(
                code: "BCFP",
                title: "周期白马骑士",
                summary: "重度依赖深度行业研报与估值模型，专注核心白马资产的大周期波段。",
                advice: "观点逻辑扎实、确定性高；但在流动性泡沫极端扩张时往往过早清仓‘恐高’。",
                defaultTags: ["深度研报", "白马龙头", "确定性优先", "左侧定投"],
                badgeStyle: .sentinel
            )
        case "BDTA":
            return MBTIProfileInfo(
                code: "BDTA",
                title: "动量冲锋枪",
                summary: "短线图表突破狂人，顺风牛市声量极大，追涨情绪龙头；震荡市易频繁打脸。",
                advice: "适合行情主升浪时跟随做短线右侧突破；震荡与阴跌市中务必直接过滤其喊单，避免反复割肉。",
                defaultTags: ["突破追涨", "情绪冲锋", "高频短线", "K线右侧"],
                badgeStyle: .charger
            )
        case "BDTP":
            return MBTIProfileInfo(
                code: "BDTP",
                title: "均线巡航舰",
                summary: "尊重右侧技术形态与胜率优先，执行严苛的短线止损纪律，不赚最后一个铜板。",
                advice: "胜率较高且回撤小，可重点学习其止盈止损点位设置，但莫期望其带来百倍爆发收益。",
                defaultTags: ["均线战法", "严控回撤", "波段胜率", "纪律严明"],
                badgeStyle: .charger
            )
        case "BDFA":
            return MBTIProfileInfo(
                code: "BDFA",
                title: "事件突击手",
                summary: "专注博弈短期财报超预期、监管事件落地或重磅利好催化剂。",
                advice: "事件落地即兑现，切忌把其短线催化剂逻辑误当作长期信仰持有。",
                defaultTags: ["财报博弈", "事件驱动", "短线爆发", "催化剂"],
                badgeStyle: .charger
            )
        case "BDFP":
            return MBTIProfileInfo(
                code: "BDFP",
                title: "财报套利者",
                summary: "精细测算短线估值与财报差，善于捕捉确定性高的短期事件性折价机会。",
                advice: "确定性极高但收益空间有限，适合大资金稳健打新或事件对冲。",
                defaultTags: ["估值折价", "确定性套利", "低波动", "基本面波段"],
                badgeStyle: .sentinel
            )
            
        // --- S 系列 (谨慎空头/防守) ---
        case "SCTA":
            return MBTIProfileInfo(
                code: "SCTA",
                title: "周期顶峰狙击手",
                summary: "宏观空头预言家，擅长利用宏观流动性枯竭与高位顶部形态狙击泡沫资产。",
                advice: "其牛市警告常过早出现，但一旦右侧破位，其指出的崩塌目标价极其精准。",
                defaultTags: ["泡沫狙击", "宏观顶部", "反转做空", "大周期对冲"],
                badgeStyle: .prophet
            )
        case "SCTP":
            return MBTIProfileInfo(
                code: "SCTP",
                title: "宏观对冲家",
                summary: "永远保有危机意识，专注于利用衍生品与避险标的构建大周期非对称保护。",
                advice: "是黑天鹅频发时期的救命稻草，适合用于指导宏观防守与现金储备管理。",
                defaultTags: ["危机预警", "非对称对冲", "避险资产", "稳健守成"],
                badgeStyle: .sentinel
            )
        case "SCFA":
            return MBTIProfileInfo(
                code: "SCFA",
                title: "泡沫刺客",
                summary: "善于深度拆解公司财报瑕疵、造假陷阱与商业模式伪命题，敢于发表毁灭性长空报告。",
                advice: "可作为核心持仓标的‘反向体检清单’；若其列出的硬伤无法被证伪，应迅速降低仓位。",
                defaultTags: ["深度做空", "财务排雷", "商业拆解", "犀利批判"],
                badgeStyle: .sentinel
            )
        case "SCFP":
            return MBTIProfileInfo(
                code: "SCFP",
                title: "价值守门人",
                summary: "资深头部券商策略/百亿私募风格，防守极佳，熊市冰点胜率极高，但牛市易过早清仓恐高。",
                advice: "熊市寻底时是最好的灯塔；当市场进入疯牛亢奋期时，对其‘估值已透支’的警告可保持适度钝感。",
                defaultTags: ["防守大师", "冰点胜率高", "估值严苛", "恐高止盈"],
                badgeStyle: .sentinel
            )
        case "SDTA":
            return MBTIProfileInfo(
                code: "SDTA",
                title: "顶背离猎手",
                summary: "专注敏锐捕捉 K 线顶部背离与超买情绪竭尽点，打法狠辣、快进快出。",
                advice: "切忌在强势主升浪中轻信其‘见顶回落’判断，容易被逼空轧空造成惨烈亏损。",
                defaultTags: ["顶背离", "超买做空", "短线猎手", "逆向博弈"],
                badgeStyle: .charger
            )
        case "SDTP":
            return MBTIProfileInfo(
                code: "SDTP",
                title: "铁底卫士",
                summary: "极度厌恶风险的战术家，震荡市严守止损点，专注在破位时防守止损。",
                advice: "防守纪律可参考性极高，但其往往因过分谨慎而错过启动初期的暴涨主升段。",
                defaultTags: ["严格止损", "破位防守", "低容忍度", "战术保守"],
                badgeStyle: .sentinel
            )
        case "SDFA":
            return MBTIProfileInfo(
                code: "SDFA",
                title: "瑕疵猎鹰",
                summary: "第一时间捕捉盘面突发暴雷新闻与研报下调评级，做空速度极快。",
                advice: "适合作为个股利空突发预警；但由于其属于快速博弈，切勿追随在低位追空。",
                defaultTags: ["暴雷预警", "突发利空", "快速反应", "弱势做空"],
                badgeStyle: .charger
            )
        case "SDFP":
            return MBTIProfileInfo(
                code: "SDFP",
                title: "均值回归者",
                summary: "深信万物皆有周期与均值引力，专注在短线估值与情绪极端过热时做反向收敛。",
                advice: "在宽幅震荡市中如鱼得水，但在趋势性单边暴涨行情中容易过早开空受挫。",
                defaultTags: ["均值引力", "逆向收敛", "震荡套利", "情绪平抑"],
                badgeStyle: .sentinel
            )
            
        default:
            return MBTIProfileInfo(
                code: code.uppercased(),
                title: "多维观察家",
                summary: "风格均衡多变，在不同市场周期具备灵活的适应性。",
                advice: "建议结合单笔存证的具体行业与逻辑进行独立评估。",
                defaultTags: ["动态适应", "多维观察", "客观理性"],
                badgeStyle: .sentinel
            )
        }
    }
}
