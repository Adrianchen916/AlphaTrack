//
//  DashboardView.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//  UI 依据 AlphaTrack_Prototype_v4.html 完全对齐：
//  1. 顶部标题栏：紧凑控制组（语言 / 昼夜 / 设置）+ 蓝色「极速存证」
//  2. 左侧边栏：浅灰选中态 + 彩色市场圆点 + 计数（230pt）
//  3. 概览大屏：4 指标卡 + 双轨校准对比 + 市场分布柱图 + 多空/周期分布
//  4. 活跃进行中：搜索 + 筛选胶囊 + 双列存证卡片（涨红跌绿进度条）
//  5. 已结算对账：ledger 表格（HIT / ⚡提前命中 / MISS / 📝客观数据）
//  6. 我的预测校准：双卡 + 各市场独立胜率 + 个人流水与复盘
//  7. KOL 红黑榜 + 认知人格卡片流（axis-mini 四维 + 避坑指南）
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var analyzer = MBTIAnalyzer.shared

    // MARK: - SwiftData 实体查询
    @Query(sort: \PredictionEntry.createdAt, order: .reverse)
    private var allEntries: [PredictionEntry]

    @Query(sort: \SourceProfile.lastUsedAt, order: .reverse)
    private var allProfiles: [SourceProfile]

    // MARK: - 本地状态
    @AppStorage("AlphaTrack.customMarketCategories")
    private var customCategoriesRaw: String = "黄金与大宗商品"

    private var customCategories: [String] {
        get {
            customCategoriesRaw
                .split(separator: "|", omittingEmptySubsequences: true)
                .map(String.init)
        }
        nonmutating set {
            customCategoriesRaw = newValue.joined(separator: "|")
        }
    }
    @State private var showAddCategorySheet: Bool = false
    @State private var newCategoryName: String = ""

    /// MBTI 算法解析说明弹窗
    @State private var showAlgoInfoAlert: Bool = false

    /// 流水工作台状态
    @State private var ledgerSearchText: String = ""
    @State private var marketPillFilter: String = "全部"
    @State private var detailEntry: PredictionEntry?

    /// 活跃卡片的实时价格（现价 + 涨跌幅）
    @State private var livePrices: [String: Double] = [:]

    /// 单条存证删除状态
    @State private var entryToDelete: PredictionEntry? = nil
    @State private var showDeleteEntryAlert: Bool = false

    struct DashboardStats {
        let total: Int
        let active: Int
        let settled: Int
        let factualCount: Int
        let targetAlertCount: Int
        let overallWinRate: Double?
        let avgDeviation: Double?
        let markets: [String: Int]
        let marketWinRates: [String: Double?]
        let horizonCounts: [String: Int]
        let longTermWinRate: Double?
        let selfWinRate: Double?
        let selfLongTermWinRate: Double?
        let selfTotal: Int
        let selfSettled: Int
        let kolWinRate: Double?
        let bullishCount: Int
        let bearishCount: Int
    }

    /// 单次循环全景统计指标与分类数量缓存
    private var dashboardStats: DashboardStats {
        var active = 0
        var settled = 0
        var totalWins = 0
        var factualCount = 0
        var targetAlertCount = 0
        var totalDeviationSum = 0.0
        var deviationCount = 0
        var markets: [String: Int] = [:]
        var marketSettled: [String: Int] = [:]
        var marketWins: [String: Int] = [:]
        var horizonCounts: [String: Int] = [:]
        var selfTotal = 0
        var selfSettled = 0
        var selfWins = 0
        var selfLongSettled = 0
        var selfLongWins = 0
        var kolSettled = 0
        var kolWins = 0
        var allLongSettled = 0
        var allLongWins = 0
        var bullish = 0
        var bearish = 0

        for entry in allEntries {
            let isSettled = entry.arbitrationStatus.isSettled
            let isWin = entry.arbitrationStatus.isWin
            let isLong = entry.horizon == .longTerm || entry.horizon == .days30

            if entry.entryType == .factualSnapshot {
                factualCount += 1
            }

            if entry.targetPrice != nil && !isSettled {
                targetAlertCount += 1
            }

            if let target = entry.targetPrice, entry.entryPrice > 0 {
                let diff = abs(target - entry.entryPrice) / entry.entryPrice * 100.0
                totalDeviationSum += diff
                deviationCount += 1
            }

            horizonCounts[entry.horizon.rawValue, default: 0] += 1

            if isSettled {
                settled += 1
                if isWin { totalWins += 1 }
                marketSettled[entry.marketCategory, default: 0] += 1
                if isWin {
                    marketWins[entry.marketCategory, default: 0] += 1
                }
                if isLong {
                    allLongSettled += 1
                    if isWin { allLongWins += 1 }
                }
            } else {
                active += 1
            }

            if entry.direction == .bullish {
                bullish += 1
            } else if entry.direction == .bearish {
                bearish += 1
            }

            markets[entry.marketCategory, default: 0] += 1

            if entry.isSelfJudgment {
                selfTotal += 1
                if isSettled {
                    selfSettled += 1
                    if isWin { selfWins += 1 }
                    if isLong {
                        selfLongSettled += 1
                        if isWin { selfLongWins += 1 }
                    }
                }
            } else {
                if isSettled {
                    kolSettled += 1
                    if isWin { kolWins += 1 }
                }
            }
        }

        let overallRate: Double? = settled > 0 ? (Double(totalWins) / Double(settled) * 100.0) : nil
        let avgDev: Double? = deviationCount > 0 ? (totalDeviationSum / Double(deviationCount)) : nil
        let longRate: Double? = allLongSettled > 0 ? (Double(allLongWins) / Double(allLongSettled) * 100.0) : nil
        let selfRate: Double? = selfSettled > 0 ? (Double(selfWins) / Double(selfSettled) * 100.0) : nil
        let selfLongRate: Double? = selfLongSettled > 0 ? (Double(selfLongWins) / Double(selfLongSettled) * 100.0) : nil
        let kolRate: Double? = kolSettled > 0 ? (Double(kolWins) / Double(kolSettled) * 100.0) : nil

        var marketRates: [String: Double?] = [:]
        for (m, _) in markets {
            let mSettled = marketSettled[m, default: 0]
            if mSettled > 0 {
                marketRates[m] = Double(marketWins[m, default: 0]) / Double(mSettled) * 100.0
            } else {
                marketRates[m] = nil
            }
        }

        return DashboardStats(
            total: allEntries.count,
            active: active,
            settled: settled,
            factualCount: factualCount,
            targetAlertCount: targetAlertCount,
            overallWinRate: overallRate,
            avgDeviation: avgDev,
            markets: markets,
            marketWinRates: marketRates,
            horizonCounts: horizonCounts,
            longTermWinRate: longRate,
            selfWinRate: selfRate,
            selfLongTermWinRate: selfLongRate,
            selfTotal: selfTotal,
            selfSettled: selfSettled,
            kolWinRate: kolRate,
            bullishCount: bullish,
            bearishCount: bearish
        )
    }

    init() {}

    // MARK: - 当前生效的主题色彩

    private var currentColorScheme: ColorScheme {
        switch analyzer.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemColorScheme
        }
    }

    private var isDark: Bool {
        currentColorScheme == .dark
    }

    private var isZh: Bool {
        analyzer.language == .zh
    }

    private var windowBackgroundView: some View {
        VisualEffectBackground(
            material: isDark ? .underWindowBackground : .underWindowBackground,
            blendingMode: .behindWindow
        )
        .ignoresSafeArea()
    }

    private var currentFilteredCards: [MBTICardData] {
        let marketFilterName: String?
        if case .market(let name) = analyzer.selectedFilter {
            marketFilterName = name
        } else {
            marketFilterName = nil
        }
        return analyzer.analyzeProfiles(profiles: allProfiles, entries: allEntries, marketFilter: marketFilterName)
    }

    private func winRateColor(_ rate: Double?) -> Color {
        AT.winRateColor(rate, isDark)
    }

    private func bandText(_ rate: Double?) -> String {
        guard let r = rate else { return isZh ? "无样本" : "No data" }
        if r >= 60.0 { return isZh ? "翡翠绿区间" : "Green band" }
        if r >= 40.0 { return isZh ? "琥珀黄区间" : "Amber band" }
        return isZh ? "警戒红区间" : "Red band"
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value)
    }

    // MARK: - 主结构

    var body: some View {
        VStack(spacing: 0) {
            topToolbarHeader

            Rectangle().fill(AT.sep(isDark)).frame(height: 1)

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 230)

                Rectangle().fill(AT.sep(isDark)).frame(width: 1)

                mainContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(windowBackgroundView)
        .preferredColorScheme(currentColorScheme)
        .sheet(isPresented: $showAddCategorySheet) {
            addCategorySheet
        }
        .alert(isZh ? "AlphaTrack 投资性格 MBTI 算法" : "AlphaTrack Cognitive MBTI Algorithm", isPresented: $showAlgoInfoAlert) {
            Button(isZh ? "确定" : "OK", role: .cancel) {}
        } message: {
            Text(isZh
                 ? "根据 KOL/用户历史言论的多空比例（多头信仰 B vs 谨慎做空 S）、平均预测周期（短线 D vs 宏观长周期 C）、归因内核（基本面研报 F vs 技术链上模型 T）及目标价偏离幅度（激进赔率 A vs 稳健胜率 P）四维加权自动推导 16 种典型投资人格。"
                 : "Automatically calculates 16 financial personalities based on historical bullish/skeptical ratios (B/S), forecast horizon (D/C), fundamental vs technical drivers (F/T), and payoff aggressiveness (A/P).")
        }
        .alert("⚠️ 谨慎删除存证提示", isPresented: $showDeleteEntryAlert) {
            Button("确认彻底删除", role: .destructive) {
                if let target = entryToDelete {
                    modelContext.delete(target)
                    try? modelContext.save()
                    entryToDelete = nil
                }
            }
            Button("取消", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            if let target = entryToDelete {
                Text("确认永久删除此条「\(target.ticker) - \(target.authorName)」的存证判断吗？\n\n删除后将不可撤销与恢复！请谨慎确认。")
            } else {
                Text("确认删除该存证记录吗？")
            }
        }
    }

    // MARK: - 1. 顶部标题栏（原型 .titlebar / .tb-group / .btn-new）

    private var topToolbarHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AT.accent)
                    .font(.system(size: 13, weight: .semibold))
                Text(isZh ? "认知对账与胜率雷达" : "Cognitive Ledger & Alpha Radar")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(AT.text(isDark))
            }

            Spacer()

            HStack(spacing: 8) {
                // 紧凑控制组（原型 .tb-group）— 暗色用更深一档底色提高对比
                HStack(spacing: 2) {
                    // 语言切换：单按钮 中 / EN
                    toolbarIconButton(
                        title: isZh ? "中" : "EN",
                        minWidth: 34
                    ) {
                        analyzer.language = isZh ? .en : .zh
                    }

                    // 昼夜切换：单按钮（右键 / 长按可切「自动」）
                    toolbarIconButton(
                        systemImage: analyzer.themeMode == .light ? "moon.fill" : (analyzer.themeMode == .dark ? "sun.max.fill" : "circle.lefthalf.filled"),
                        minWidth: 28
                    ) {
                        let current = currentColorScheme
                        analyzer.themeMode = (current == .dark) ? .light : .dark
                    }
                    .contextMenu {
                        Button(isZh ? "🌓 跟随系统（自动）" : "🌓 Auto") {
                            analyzer.themeMode = .auto
                        }
                    }

                    // 设置入口
                    toolbarIconButton(systemImage: "gearshape.fill", minWidth: 28) {
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .padding(2)
                .background(isDark ? Color.white.opacity(0.12) : AT.seg(isDark))
                .cornerRadius(8)

                // 极速存证（原型 .btn-new）
                Button(action: {
                    switch analyzer.selectedFilter {
                    case .market(let cat):
                        HUDPanelController.shared.show(presetMarket: cat)
                    case .myCalibration:
                        HUDPanelController.shared.show(isSelfJudgment: true)
                    default:
                        HUDPanelController.shared.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(isZh ? "极速存证" : "Quick Entry")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(AT.accent)
                    .cornerRadius(7)
                }
                .buttonStyle(PressStyle())
            }
        }
        // 与下方内容区（.padding(.horizontal, 22)）保持一致的右边距，
        // 让「极速存证」按钮右边缘与「录入此分类」按钮、存证卡片右边缘对齐
        .padding(.horizontal, 22)
        .frame(height: 52)
    }

    /// 原型 .tb-btn：24pt 高、6pt 圆角的紧凑图标/文字按钮
    private func toolbarIconButton(
        title: String = "",
        systemImage: String = "",
        minWidth: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if !title.isEmpty {
                    Text(title).font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(isDark ? .white.opacity(0.92) : AT.text2(isDark))
            .frame(minWidth: minWidth, minHeight: 24)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - 极速响应按钮样式

    struct InstantSidebarButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.75 : 1.0)
        }
    }

    // MARK: - 2. 左侧边栏（原型 .sidebar / .nav-item / .nav-dot）

    private var sidebarView: some View {
        let stats = dashboardStats
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 状态视图
                    navLabel(isZh ? "状态视图" : "VIEWS")

                    navItem(
                        icon: "📊",
                        title: isZh ? "全部资产概览" : "Overview",
                        badge: "\(stats.total)",
                        isSelected: analyzer.selectedFilter == .allAssets
                    ) {
                        analyzer.selectedFilter = .allAssets
                    }

                    navItem(
                        icon: "⏳",
                        title: isZh ? "活跃进行中" : "Active",
                        badge: "\(stats.active)",
                        isSelected: analyzer.selectedFilter == .activeOnly
                    ) {
                        analyzer.selectedFilter = .activeOnly
                    }

                    navItem(
                        icon: "✅",
                        title: isZh ? "已结算对账" : "Settled",
                        badge: "\(stats.settled)",
                        isSelected: analyzer.selectedFilter == .settledOnly
                    ) {
                        analyzer.selectedFilter = .settledOnly
                    }

                    // 行情分类
                    navLabel(isZh ? "行情分类" : "MARKETS")

                    ForEach(builtinMarketNames, id: \.self) { name in
                        marketNavRow(
                            name: name,
                            displayName: marketDisplayName(name),
                            count: stats.markets[name, default: 0]
                        )
                    }

                    ForEach(customCategories.filter { !builtinMarketNames.contains($0) }, id: \.self) { cat in
                        marketNavRow(
                            name: cat,
                            displayName: cat,
                            count: stats.markets[cat, default: 0],
                            isCustom: true
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                customCategories = customCategories.filter { $0 != cat }
                            } label: {
                                Label(isZh ? "删除该分类" : "Delete Category", systemImage: "trash")
                            }
                        }
                    }

                    Button(action: { showAddCategorySheet = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(isZh ? "新增行情分类…" : "Add market…")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AT.text3(isDark))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(InstantSidebarButtonStyle())
                    .padding(.top, 1)

                    // 分析与档案
                    navLabel(isZh ? "分析与档案" : "ANALYSIS")

                    navItem(
                        icon: "👤",
                        title: isZh ? "我的预测校准" : "My Calibration",
                        badge: "\(stats.selfTotal)",
                        isSelected: analyzer.selectedFilter == .myCalibration
                    ) {
                        analyzer.selectedFilter = .myCalibration
                    }

                    navItem(
                        icon: "🏆",
                        title: isZh ? "KOL 战绩红黑榜" : "KOL Ledger",
                        isSelected: analyzer.selectedFilter == .kolLeaderboard
                    ) {
                        analyzer.selectedFilter = .kolLeaderboard
                    }

                    navItem(
                        icon: "🧠",
                        title: isZh ? "认知人格 (MBTI)" : "Cognitive MBTI",
                        isSelected: analyzer.selectedFilter == .mbtiRadar
                    ) {
                        analyzer.selectedFilter = .mbtiRadar
                    }

                    navItem(
                        icon: "👥",
                        title: isZh ? "来源档案管理" : "Source Profiles",
                        badge: "\(allProfiles.count)",
                        isSelected: analyzer.selectedFilter == .sourceManager
                    ) {
                        analyzer.selectedFilter = .sourceManager
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }

            // 边栏底部数据源状态
            VStack(alignment: .leading, spacing: 2) {
                Text(isZh ? "A股行情: 腾讯/新浪实盘接口" : "A-Shares: Tencent/Sina Feed")
                Text(isZh ? "美股/Crypto: Yahoo & Binance" : "US/Crypto: Yahoo & Binance")
            }
            .font(.system(size: 10))
            .foregroundColor(AT.text3(isDark))
            .padding(12)
        }
        .background(
            isDark
                ? Color.white.opacity(0.04)
                : Color.white.opacity(0.45)
        )
    }

    private var builtinMarketNames: [String] {
        ["A股", "美股", "港股", "Crypto"]
    }

    private func marketDisplayName(_ name: String) -> String {
        guard isZh else {
            switch name {
            case "A股": return "A-Share"
            case "美股": return "US"
            case "港股": return "HK"
            default: return name
            }
        }
        switch name {
        case "A股": return "A股"
        case "美股": return "美股"
        case "港股": return "港股"
        default: return name
        }
    }

    /// 原型 .nav-label：11px semibold 三级文字
    private func navLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AT.text3(isDark))
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 原型 .nav-item：28pt 高、浅灰选中态（active-bg + 加粗），非蓝色填充
    private func navItem(
        icon: String,
        title: String,
        badge: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                if let b = badge {
                    Text(b)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AT.text3(isDark))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AT.activeBg(isDark) : Color.clear)
            .contentShape(Rectangle())
            .cornerRadius(6)
        }
        .buttonStyle(InstantSidebarButtonStyle())
    }

    /// 原型行情分类行：彩色圆点 + 名称 + 计数
    private func marketNavRow(
        name: String,
        displayName: String,
        count: Int,
        isCustom: Bool = false
    ) -> some View {
        let isSelected = analyzer.selectedFilter == .market(name)
        return Button(action: {
            analyzer.selectedFilter = .market(name)
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AT.marketDot(name))
                    .frame(width: 7, height: 7)
                Text(displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AT.text3(isDark))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AT.activeBg(isDark) : Color.clear)
            .contentShape(Rectangle())
            .cornerRadius(6)
        }
        .buttonStyle(InstantSidebarButtonStyle())
    }

    // MARK: - 3. 右侧主内容区

    private var mainContentView: some View {
        Group {
            switch analyzer.selectedFilter {
            case .allAssets:
                allAssetsExecutiveDashboard
            case .myCalibration:
                myCalibrationView
            case .activeOnly:
                activeWorkbench(title: isZh ? "活跃进行中" : "Active Entries",
                                subtitle: isZh ? "全部市场 · 待对账工作台" : "All markets · open workbench",
                                // 按行情分类顺序排（与侧栏一致），同分类内最新录入在前
                                entries: PredictionEntry.sortedByMarketCategory(
                                    allEntries.filter { !$0.arbitrationStatus.isSettled },
                                    customCategories: customCategories),
                                showQuickAdd: false)
            case .settledOnly:
                settledLedgerView()
            case .market(let name):
                activeWorkbench(title: isZh ? "\(name)市场" : "\(name) Market",
                                subtitle: isZh ? "进行中的存证 · 已按分类过滤" : "Open entries · filtered by market",
                                entries: PredictionEntry.sortedByMarketCategory(
                                    allEntries.filter { !$0.arbitrationStatus.isSettled && $0.marketCategory == name },
                                    customCategories: customCategories),
                                showQuickAdd: true,
                                presetMarket: name)
            case .sourceManager:
                SourceProfileManagerView()
            case .mbtiRadar, .kolLeaderboard:
                kolLedgerAndPersonasView
            }
        }
        .sheet(item: $detailEntry) { entry in
            EntryDetailView(entry: entry)
        }
    }

    // MARK: - 3.1 全部资产概览（原型 viewOverview）

    private var allAssetsExecutiveDashboard: some View {
        let stats = dashboardStats
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                PageHead(
                    title: isZh ? "全部资产概览" : "Executive Dashboard",
                    subtitle: isZh ? "全景决策大屏 · 双轨校准对比" : "Panoramic view · dual-track calibration",
                    dark: isDark
                )

                metricsSummaryRow

                SectionHead(
                    title: isZh ? "双轨预测校准对比" : "Dual-Track Calibration",
                    hint: isZh ? "我 vs 外部 KOL" : "You vs. external KOLs",
                    dark: isDark
                )

                HStack(alignment: .top, spacing: 10) {
                    selfCalibrationSummaryCard(stats: stats)
                    kolCalibrationSummaryCard(stats: stats)
                }

                SectionHead(
                    title: isZh ? "行情市场分布与胜率" : "Market Distribution & Win Rate",
                    hint: isZh ? "柱高 = 存证数量 · 标注 = 独立胜率" : "bar height = entries · label = win rate",
                    dark: isDark
                )

                marketDistributionCard(stats: stats)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    // 3.1.1 四大指标卡（原型 .metric：26px 数值）
    private var metricsSummaryRow: some View {
        let stats = dashboardStats
        return HStack(spacing: 10) {
            metricCard(
                title: isZh ? "累计存证总数" : "Total Entries",
                value: "\(stats.total)",
                unit: "",
                subtext: isZh ? "含客观事实 \(stats.factualCount) 条" : "incl. \(stats.factualCount) factual"
            )

            metricCard(
                title: isZh ? "活跃跟踪中" : "Active",
                value: "\(stats.active)",
                unit: "",
                subtext: isZh ? "\(stats.targetAlertCount) 条目标价高频监控中" : "\(stats.targetAlertCount) on target watch"
            )

            metricCard(
                title: isZh ? "综合已结算胜率" : "Settled Win Rate",
                value: percentText(stats.overallWinRate),
                unit: "",
                subtext: isZh ? "样本 \(stats.settled) 条 · \(bandText(stats.overallWinRate))" : "\(stats.settled) samples · \(bandText(stats.overallWinRate))",
                valueColor: winRateColor(stats.overallWinRate)
            )

            metricCard(
                title: isZh ? "平均目标偏离度" : "Avg Deviation",
                value: stats.avgDeviation != nil ? String(format: "+%.1f%%", stats.avgDeviation!) : "--",
                unit: "",
                subtext: isZh ? "衡量预测激进程度" : "how aggressive targets are"
            )
        }
    }

    private func metricCard(title: String, value: String, unit: String, subtext: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AT.text2(isDark))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(valueColor ?? AT.text(isDark))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AT.text2(isDark))
                }
            }

            Text(subtext)
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .shadow(color: isDark ? Color.clear : Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // 3.1.2 我个人的预测校准卡（原型 .calib）
    private func selfCalibrationSummaryCard(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("🧠")
                    .font(.system(size: 16))
                Text(isZh ? "我个人的预测校准" : "My Calibration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                Button(action: { analyzer.selectedFilter = .myCalibration }) {
                    Text(isZh ? "直达流水 ›" : "My ledger ›")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.accent)
                }
                .buttonStyle(InstantSidebarButtonStyle())
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(percentText(stats.selfWinRate))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(AT.winHi(isDark))
                Text(isZh ? "个人综合胜率" : "personal win rate")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 7) {
                if let selfRate = stats.selfWinRate, let kolRate = stats.kolWinRate {
                    calibRow(
                        label: isZh ? "长期优势" : "Long edge",
                        value: String(format: "%+.1f pt", selfRate - kolRate),
                        valueColor: (selfRate - kolRate) >= 0 ? AT.rise(isDark) : AT.fall(isDark),
                        note: isZh ? "长期 (3月+) 胜率高于短期" : "long-horizon calls beat short-term"
                    )
                } else {
                    calibRow(
                        label: isZh ? "长期优势" : "Long edge",
                        value: percentText(stats.selfLongTermWinRate),
                        valueColor: AT.winRateColor(stats.selfLongTermWinRate, isDark),
                        note: isZh ? "长期 (3月+) 综合胜率" : "long-horizon win rate"
                    )
                }

                calibRowChips(
                    label: isZh ? "擅长赛道" : "Best at",
                    chips: [TagView(text: isZh ? "A股消费" : "A-Consumer", style: .neutral, dark: isDark),
                            TagView(text: isZh ? "美股科技" : "US Tech", style: .neutral, dark: isDark)]
                )

                calibRowChips(
                    label: isZh ? "自我人格" : "My persona",
                    chips: selfPersonaChips
                )
            }
            .padding(.top, 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .shadow(color: isDark ? Color.clear : Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    /// 「我自己的判断」对应的人格徽章（从档案实时计算，无档案时隐藏）
    private var selfPersonaChips: [TagView] {
        let cards = analyzer.analyzeProfiles(profiles: allProfiles, entries: allEntries)
        if let mine = cards.first(where: { $0.isSelf }) {
            return [
                TagView(text: mine.mbtiCode, style: .fact, dark: isDark),
                TagView(text: mine.mbtiTitle, style: .neutral, dark: isDark)
            ]
        }
        return [TagView(text: isZh ? "待积累样本" : "n/a", style: .neutral, dark: isDark)]
    }

    // 3.1.3 外部 KOL 校准卡（原型 .calib）
    private func kolCalibrationSummaryCard(stats: DashboardStats) -> some View {
        let totalDir = stats.bullishCount + stats.bearishCount
        let bullPct: Int = totalDir > 0 ? Int(round(Double(stats.bullishCount) / Double(totalDir) * 100)) : 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("🏆")
                    .font(.system(size: 16))
                Text(isZh ? "外部博主与大V校准" : "External KOLs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AT.text(isDark))
                Spacer()
                Button(action: {
                    analyzer.selectedFilter = .kolLeaderboard
                }) {
                    Text(isZh ? "查看红黑榜 ›" : "Ledger ›")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.accent)
                }
                .buttonStyle(InstantSidebarButtonStyle())
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(percentText(stats.kolWinRate))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(AT.winMid(isDark))
                Text(isZh ? "外部平均胜率" : "external average")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
            }
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 7) {
                calibRow(
                    label: isZh ? "多头偏差" : "Bullish bias",
                    value: "\(bullPct)% → --",
                    valueColor: AT.fall(isDark),
                    note: isZh ? "喊多占比 vs 实际上涨占比" : "calls vs. reality"
                )

                if let selfRate = stats.selfWinRate, let kolRate = stats.kolWinRate {
                    calibRow(
                        label: isZh ? "噪音滤网" : "Noise filter",
                        value: String(format: "%.1f pt", kolRate - selfRate),
                        valueColor: AT.rise(isDark),
                        note: isZh ? "跟随外部的胜率折损" : "following vs. deciding yourself"
                    )
                } else {
                    calibRow(
                        label: isZh ? "噪音滤网" : "Noise filter",
                        value: "--",
                        valueColor: AT.text3(isDark),
                        note: isZh ? "跟随外部 vs 独立判断的胜率差" : "following vs. deciding yourself"
                    )
                }

                calibRowChips(
                    label: isZh ? "最需警惕" : "Watch out",
                    chips: watchOutChips
                )
            }
            .padding(.top, 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .shadow(color: isDark ? Color.clear : Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    /// 胜率最低的外部 KOL 人格警示徽章
    private var watchOutChips: [TagView] {
        let cards = analyzer.analyzeProfiles(profiles: allProfiles, entries: allEntries)
            .filter { !$0.isSelf }
        if let worst = cards.min(by: { $0.winRate < $1.winRate }), worst.totalCount > 0 {
            return [
                TagView(text: worst.mbtiCode, style: .bear, dark: isDark),
                TagView(text: worst.mbtiTitle, style: .neutral, dark: isDark)
            ]
        }
        return [TagView(text: isZh ? "暂无样本" : "n/a", style: .neutral, dark: isDark)]
    }

    private func calibRow(label: String, value: String, valueColor: Color, note: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(AT.text3(isDark))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(valueColor)
            Text(note)
                .font(.system(size: 11.5))
                .foregroundColor(AT.text2(isDark))
                .lineLimit(1)
        }
    }

    private func calibRowChips(label: String, chips: [TagView]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(AT.text3(isDark))
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    chip
                }
            }
        }
    }

    // 3.1.4 市场分布柱图（原型 .chart / .bars）
    private func marketDistributionCard(stats: DashboardStats) -> some View {
        let marketsList: [(name: String, displayName: String)] =
            builtinMarketNames.map { ($0, marketDisplayName($0)) }
            + customCategories.filter { !builtinMarketNames.contains($0) }.map { ($0, $0) }

        let maxCount = max(1, marketsList.map { stats.markets[$0.name, default: 0] }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(marketsList, id: \.name) { item in
                    let count = stats.markets[item.name, default: 0]
                    let winRate = stats.marketWinRates[item.name] ?? nil
                    let barHeight = max(6.0, CGFloat(count) / CGFloat(maxCount) * 100.0)
                    // 有胜率样本 → 三档胜率色（绿/琥珀/红）；
                    // 无样本（未结算，标注"--"）→ 用市场分类色（与侧栏圆点一致），
                    // 避免柱子退化为灰色"没有颜色"的观感
                    let colColor = winRate != nil
                        ? winRateColor(winRate!)
                        : AT.marketDot(item.name)

                    Button(action: {
                        analyzer.selectedFilter = .market(item.name)
                    }) {
                        VStack(spacing: 6) {
                            if let wr = winRate {
                                Text(String(format: "%.1f%%", wr))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(winRateColor(wr))
                            } else {
                                Text("--")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AT.text3(isDark))
                            }

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(AT.track(isDark))
                                    .frame(width: 34, height: 100)

                                RoundedRectangle(cornerRadius: 5)
                                    .fill(colColor.opacity(0.85))
                                    .frame(width: 34, height: barHeight)
                            }

                            Text(item.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AT.text(isDark))

                            Text(isZh ? "\(count) 条" : "\(count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AT.text3(isDark))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InstantSidebarButtonStyle())
                }
            }
            .padding(.vertical, 6)

            Rectangle().fill(AT.sep(isDark)).frame(height: 1)

            HStack(spacing: 14) {
                legendSwatch(AT.winHi(isDark), isZh ? "≥60% 翡翠绿" : "≥60% green")
                legendSwatch(AT.winMid(isDark), isZh ? "40–60% 琥珀黄" : "40–60% amber")
                legendSwatch(AT.winLo(isDark), isZh ? "<40% 警戒红" : "<40% red")
                Spacer()
                Text(isZh ? "柱高 = 存证数量 · 点击柱子直达分类流水" : "bar = entries · click to view ledger")
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.text3(isDark))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .shadow(color: isDark ? Color.clear : Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(AT.text2(isDark))
        }
    }

    // 3.1.5 多空博弈与周期分布（原型 .split-bar / .dist）
    private func sentimentAndHorizonCard(stats: DashboardStats) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 左：多空博弈
            VStack(alignment: .leading, spacing: 10) {
                Text(isZh ? "⚖️ 多空博弈立场" : "⚖️ Directional Bias")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AT.text(isDark))

                let totalDir = stats.bullishCount + stats.bearishCount
                let bullPct: Int = totalDir > 0 ? Int(round(Double(stats.bullishCount) / Double(totalDir) * 100)) : 50
                let bearPct = max(0, 100 - bullPct)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if bullPct > 0 {
                            ZStack {
                                Rectangle().fill(AT.bull(isDark))
                                Text("\(bullPct)%")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: geo.size.width * CGFloat(bullPct) / 100.0)
                        }
                        if bearPct > 0 {
                            ZStack {
                                Rectangle().fill(AT.bear(isDark))
                                Text("\(bearPct)%")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: geo.size.width * CGFloat(bearPct) / 100.0)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .frame(height: 26)

                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(AT.bull(isDark)).frame(width: 8, height: 8)
                        Text(isZh ? "看多 Bullish (\(stats.bullishCount))" : "Bullish (\(stats.bullishCount))")
                            .font(.system(size: 11))
                            .foregroundColor(AT.text2(isDark))
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(AT.bear(isDark)).frame(width: 8, height: 8)
                        Text(isZh ? "看空 Bearish (\(stats.bearishCount))" : "Bearish (\(stats.bearishCount))")
                            .font(.system(size: 11))
                            .foregroundColor(AT.text2(isDark))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AT.cardBg(isDark))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))

            // 右：验证周期分布
            VStack(alignment: .leading, spacing: 8) {
                Text(isZh ? "⏱️ 验证周期分布" : "⏱️ Horizon Distribution")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AT.text(isDark))

                let horizonKeys: [(key: String, label: String)] = [
                    ("24小时", isZh ? "24 小时" : "24 Hours"),
                    ("7天", isZh ? "7 天" : "7 Days"),
                    ("30天", isZh ? "30 天" : "30 Days"),
                    ("长期 (3月+)", isZh ? "长期" : "Long Term")
                ]

                let totalH = stats.total > 0 ? stats.total : 1

                VStack(spacing: 8) {
                    ForEach(horizonKeys, id: \.key) { item in
                        let count = stats.horizonCounts[item.key, default: 0]
                        let pct = Int(round(Double(count) / Double(totalH) * 100))

                        HStack(spacing: 9) {
                            Text(item.label)
                                .font(.system(size: 11.5))
                                .foregroundColor(AT.text3(isDark))
                                .frame(width: 56, alignment: .leading)

                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AT.track(isDark))
                                        .frame(height: 7)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AT.accent)
                                        .frame(width: max(0, g.size.width * CGFloat(pct) / 100.0), height: 7)
                                }
                            }
                            .frame(height: 7)

                            Text("\(pct)%")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(AT.text2(isDark))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AT.cardBg(isDark))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        }
    }

    // MARK: - 3.2 活跃进行中工作台（原型 viewActive：双列存证卡片）

    private func activeWorkbench(
        title: String,
        subtitle: String,
        entries: [PredictionEntry],
        showQuickAdd: Bool,
        presetMarket: String? = nil
    ) -> some View {
        let keyword = ledgerSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = keyword.isEmpty ? entries : entries.filter { entry in
            entry.ticker.lowercased().contains(keyword)
                || entry.authorName.lowercased().contains(keyword)
                || (entry.tickerName ?? "").lowercased().contains(keyword)
                || (entry.notes ?? "").lowercased().contains(keyword)
                || (entry.factualSummary ?? "").lowercased().contains(keyword)
        }

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // 标题行只放标题与副标，右侧按钮移到下一行（搜索行）末尾右对齐
                PageHead(title: title, subtitle: subtitle, dark: isDark)

                // 搜索 + 市场筛选胶囊（原型 .input + .pill）
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(AT.text3(isDark))
                        TextField(isZh ? "搜索代码 / 名称 / 博主 / 摘要" : "Search ticker, name, source, summary", text: $ledgerSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !ledgerSearchText.isEmpty {
                            Button(action: { ledgerSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(AT.text3(isDark))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .frame(maxWidth: 280)
                    .background(AT.control(isDark))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))

                    HStack(spacing: 5) {
                        ForEach(["全部"] + builtinMarketNames, id: \.self) { f in
                            filterPill(f)
                        }
                    }

                    // Spacer 把「录入此分类」推到行尾，与面板右边缘对齐
                    Spacer()

                    if showQuickAdd {
                        Button(action: {
                            if let market = presetMarket {
                                HUDPanelController.shared.show(presetMarket: market)
                            } else {
                                HUDPanelController.shared.show()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                Text(isZh ? "录入此分类" : "New Entry")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(AT.accent)
                            .cornerRadius(7)
                        }
                        .buttonStyle(PressStyle())
                    }
                }

                if filtered.isEmpty {
                    emptyStateHint(
                        icon: "tray",
                        title: isZh ? "当前筛选下暂无存证记录" : "No entries match current filter",
                        subtitle: isZh ? "按 ⌥A 快速录入第一条存证" : "Press ⌥A to log your first forecast."
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { entry in
                            entryCard(entry)
                                .contentShape(Rectangle())
                                .onTapGesture { detailEntry = entry }
                                .contextMenu {
                                    Button { detailEntry = entry } label: {
                                        Label("查看 / 修改存证详情", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                        showDeleteEntryAlert = true
                                    } label: {
                                        Label("删除此条存证", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
        .task { await refreshDashboardLivePrices() }
    }

    private func filterPill(_ f: String) -> some View {
        Button(action: {
            if f == "全部" {
                analyzer.selectedFilter = .activeOnly
                marketPillFilter = f
            } else {
                analyzer.selectedFilter = .market(f)
                marketPillFilter = f
            }
        }) {
            Text(f)
                .font(.system(size: 11, weight: marketPillFilter == f ? .semibold : .medium))
                .foregroundColor(marketPillFilter == f ? .white : AT.text2(isDark))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(marketPillFilter == f ? AT.accent : AT.control(isDark))
                .overlay(
                    Capsule().stroke(marketPillFilter == f ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    /// 活跃卡片现价批量刷新（与菜单栏同源的行情服务）
    private func refreshDashboardLivePrices() async {
        let active = allEntries.filter { !$0.arbitrationStatus.isSettled }
        let tickers = Array(Set(active.map { $0.ticker })).prefix(12)
        guard !tickers.isEmpty else { return }

        let items = active.prefix(24).map { (ticker: $0.ticker, preferredMarket: Optional($0.marketCategory)) }
        let results = await MarketDataService.shared.batchFetchQuotes(for: Array(items))
        var map: [String: Double] = [:]
        for (ticker, result) in results {
            if case .success(let quote) = result {
                map[ticker] = quote.price
            }
        }
        livePrices = map
    }

    // 3.2.1 单张存证卡片（原型 .entry）
    private func entryCard(_ entry: PredictionEntry) -> some View {
        let now = livePrices[entry.ticker]
        let chgPct: Double? = {
            guard let now, entry.entryPrice > 0 else { return nil }
            return (now - entry.entryPrice) / entry.entryPrice * 100.0
        }()
        let progress: Double = cardProgress(entry, now: now)
        let currency = currencySymbol(for: entry.marketCategory)

        return VStack(alignment: .leading, spacing: 0) {
            // 顶部：代码 + 名称 + 来源
            HStack(spacing: 8) {
                Text(entry.ticker == "—" ? (isZh ? "客观数据" : "Fact") : entry.ticker)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(AT.text(isDark))
                if let name = entry.tickerName, !name.isEmpty, entry.ticker != "—" {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(AT.text3(isDark))
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.authorName)
                    .font(.system(size: 11))
                    .foregroundColor(AT.text2(isDark))
                    .lineLimit(1)
            }

            // 标签行
            HStack(spacing: 6) {
                if entry.entryType == .factualSnapshot {
                    TagView(text: isZh ? "客观数据" : "Neutral Fact", style: .fact, dark: isDark)
                    if entry.factualInference == .bullish {
                        TagView(text: isZh ? "衍生 ▲" : "Infer ▲", style: .bull, dark: isDark)
                    } else if entry.factualInference == .bearish {
                        TagView(text: isZh ? "衍生 ▼" : "Infer ▼", style: .bear, dark: isDark)
                    }
                } else if let dir = entry.direction {
                    TagView(text: dir == .bullish ? (isZh ? "▲ 看多" : "▲ Bull") : (isZh ? "▼ 看空" : "▼ Bear"),
                            style: dir == .bullish ? .bull : .bear, dark: isDark)
                }
                TagView(text: entry.marketCategory, style: .neutral, dark: isDark)
                if entry.targetPrice != nil {
                    TagView(text: isZh ? "目标价监控中" : "On watch", style: .warn, dark: isDark)
                }
            }
            .padding(.top, 8)

            // 事实摘要框（原型 .entry-fact）
            if let fact = entry.factualSummary, !fact.isEmpty {
                Text(fact)
                    .font(.system(size: 12))
                    .foregroundColor(AT.text2(isDark))
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AT.seg(isDark))
                    .cornerRadius(6)
                    .padding(.top, 9)
                    .lineLimit(3)
            }

            // 价格组（原型 .entry-nums）
            // 各列等宽占位（.frame(maxWidth: .infinity)），让基准价/现价/目标价/周期
            // 在卡片宽度内均匀分散开，不再紧贴在一起；周期在最后一格右对齐
            HStack(alignment: .bottom, spacing: 0) {
                priceStack(
                    label: isZh ? "基准价" : "Entry",
                    value: entry.entryPrice > 0 ? "\(currency)\(String(format: "%.2f", entry.entryPrice))" : "—"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                priceStack(
                    label: isZh ? "现价" : "Now",
                    value: now != nil ? "\(currency)\(String(format: "%.2f", now!))" : "--",
                    chg: chgPct,
                    // 现价数字按行情着色：涨绿跌红（与旁边涨跌幅同义）；
                    // 无实时价时保持主色
                    valueColor: chgPct.map { AT.riseFall($0, isDark) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if let target = entry.targetPrice {
                    // 目标价用立场色（与菜单栏微面板一致）：看多绿/看空红；
                    // 无方向的纯事实记录保持主色
                    let stanceColor: Color = {
                        switch entry.direction {
                        case .bullish: return AT.bull(isDark)
                        case .bearish: return AT.bear(isDark)
                        case nil: return AT.text(isDark)
                        }
                    }()
                    priceStack(
                        label: isZh ? "目标价" : "Target",
                        value: "\(currency)\(String(format: "%.2f", target))",
                        valueColor: stanceColor
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                priceStack(label: isZh ? "周期" : "Horizon", value: horizonShort(entry.horizon))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 10)

            // 进度条（原型 .progress：涨红跌绿）
            VStack(spacing: 4) {
                HStack {
                    Text(cardProgressLabel(entry, progress: progress))
                        .font(.system(size: 10))
                        // 颜色跟随行情色（涨红跌绿，与旁边涨跌幅同义），
                        // 不新增"对错色"；正/负由数字符号表达
                        .foregroundColor(progressLabelColor(entry, chgPct: chgPct))
                    Spacer()
                    Text(dueDateText(entry))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AT.text3(isDark))
                }
                if entry.targetPrice != nil, chgPct != nil {
                    // ---- B2 目标达成轨 ----
                    // 布局：轨道全长 = 反向区(左 1/4，容纳 -100%~0) + 主轨(右 3/4，基准→目标)
                    // 规则恒定：基准在 1/4 处，目标在最右端，向右 = 靠近目标（与多空无关）。
                    // 现价点位置即完成度；点落在基准左侧 = 走反了。零解码、无颜色编码。
                    GeometryReader { g in
                        let w = g.size.width
                        let overflowW: CGFloat = w / 4
                        let trackW: CGFloat = w - overflowW
                        let p = max(-1, min(1, progress))
                        let x = p >= 0 ? overflowW + CGFloat(p) * trackW
                                       : overflowW + CGFloat(p) * overflowW
                        let trackH: CGFloat = 4
                        let dot: CGFloat = 9

                        ZStack(alignment: .leading) {
                            // 反向区（走反了的区域，更浅）
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AT.track(isDark).opacity(0.55))
                                .frame(width: overflowW, height: trackH)

                            // 主轨道：基准 → 目标
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AT.track(isDark))
                                .frame(width: trackW, height: trackH)
                                .offset(x: overflowW)

                            // 已走过的路径
                            if p >= 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AT.text(isDark))
                                    .frame(width: max(0, CGFloat(p) * trackW), height: trackH)
                                    .offset(x: overflowW)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AT.text3(isDark))
                                    .frame(width: max(0, CGFloat(-p) * overflowW), height: trackH)
                                    .offset(x: x)
                            }

                            // 基准刻度（0% 位）
                            Rectangle()
                                .fill(AT.text3(isDark).opacity(0.5))
                                .frame(width: 1, height: 9)
                                .offset(x: overflowW)

                            // 现价点
                            Circle()
                                .fill(AT.text(isDark))
                                .frame(width: dot, height: dot)
                                .overlay(Circle().stroke(AT.cardBg(isDark), lineWidth: 1.5))
                                .offset(x: max(0, min(w - dot, x - dot / 2)))
                        }
                    }
                    .frame(height: 12)

                    // 端点标签（对齐轨道的基准位与目标位）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Text(isZh ? "基准" : "Entry")
                                .font(.system(size: 9.5))
                                .foregroundColor(AT.text3(isDark))
                                .position(x: geo.size.width / 4, y: 7)
                            Text(isZh ? "目标" : "Target")
                                .font(.system(size: 9.5))
                                .foregroundColor(AT.text3(isDark))
                                .position(x: geo.size.width - 14, y: 7)
                        }
                    }
                    .frame(height: 14)
                } else {
                    // 时间消耗模式（无目标价或无实时价）：accent 从左往右
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AT.track(isDark))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AT.accent)
                                .frame(width: max(0, g.size.width * CGFloat(progress)), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.top, 11)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .shadow(color: isDark ? Color.clear : Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func priceStack(label: String, value: String, chg: Double? = nil, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AT.text3(isDark))
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                // 数字过长时（6 位以上如 $78756.67）允许自动缩字号而非截断。
                // 注意：不加 .allowsTightening——它会压缩字符间距让数字"看起来变瘦变小"，
                // 之前目标价视觉发小就是这个原因。
                // 关键：.fixedSize(horizontal: false, vertical: true) 让文字只占满水平方向并触发缩放，
                // 配合 .minimumScaleFactor(0.5) 允许缩到 50% 仍然完整显示，
                // 而不是 lineLimit(1) 默认的截断成 "$78..."。
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(valueColor ?? AT.text(isDark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                if let c = chg {
                    Text(String(format: "%+.2f%%", c))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.riseFall(c, isDark))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 卡片进度：有目标价按价格完成度，否则按时间消耗
    private func cardProgress(_ entry: PredictionEntry, now: Double?) -> Double {
        if let target = entry.targetPrice, entry.entryPrice > 0 {
            guard let now else { return timeProgress(entry) }
            let span = target - entry.entryPrice
            guard abs(span) > 0.0001 else { return 1 }
            // 带方向的完成度：公式 (现价-基准)/(目标-基准) 天然带符号
            // —— 价格朝目标走为正，反向走为负（猜错方向）。
            // 正向 100% 封顶，反向 -100% 封底
            return min(1, max(-1, (now - entry.entryPrice) / span))
        }
        return timeProgress(entry)
    }

    private func timeProgress(_ entry: PredictionEntry) -> Double {
        let total = entry.targetDate.timeIntervalSince(entry.createdAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, 1.0 - entry.timeRemaining / total))
    }

    private func cardProgressLabel(_ entry: PredictionEntry, progress: Double) -> String {
        let pct = Int(round(progress * 100))
        if entry.targetPrice != nil, livePrices[entry.ticker] != nil {
            return isZh ? "价格完成度 \(pct)%" : "price progress \(pct)%"
        }
        return isZh ? "时间消耗 \(pct)%" : "time elapsed \(pct)%"
    }

    /// 完成度数字颜色：价格模式用主文字色（黑白，与双向进度条一致，
    /// 对错由 +/- 符号表达）；时间消耗模式保持次要灰
    private func progressLabelColor(_ entry: PredictionEntry, chgPct: Double?) -> Color {
        if entry.targetPrice != nil, chgPct != nil {
            return AT.text(isDark)
        }
        return AT.text3(isDark)
    }

    private func dueDateText(_ entry: PredictionEntry) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: entry.targetDate)
    }

    private func horizonShort(_ h: VerificationHorizon) -> String {
        switch h {
        case .longTerm: return isZh ? "长期" : "Long"
        case .custom: return isZh ? "自定义" : "Custom"
        default: return h.rawValue
        }
    }

    private func currencySymbol(for market: String) -> String {
        switch market {
        case "A股": return "¥"
        case "港股": return "HK$"
        case "美股", "Crypto": return "$"
        default: return ""
        }
    }

    /// 剩余时间文本（卡片 meta 行）
    private func countdownText(for entry: PredictionEntry) -> String {
        if entry.arbitrationStatus.isSettled {
            return isZh ? "已结算" : "Settled"
        }
        let remaining = entry.timeRemaining
        guard remaining > 0 else {
            return isZh ? "已到期待对账" : "Due"
        }
        let total = Int(remaining)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        if days > 0 {
            return isZh ? "剩余 \(days) 天" : "\(days) d left"
        }
        let mins = (total % 3600) / 60
        if hours > 0 {
            return isZh ? "剩余 \(hours) 时 \(mins) 分" : "\(hours) h \(mins) m left"
        }
        return isZh ? "剩余 \(mins) 分钟" : "\(mins) min left"
    }

    // MARK: - 3.3 已结算对账（原型 viewSettled：ledger 表格）

    /// 已结算视图：全部已结算记录的 ledger 表
    private func settledLedgerView(filter: ((PredictionEntry) -> Bool)? = nil) -> some View {
        let settled = allEntries.filter { $0.arbitrationStatus.isSettled && (filter?($0) ?? true) }
        let title = filter == nil ? (isZh ? "已结算对账" : "Settled Ledger") : (isZh ? "已结算 · 个人复盘" : "Settled personal")
        let sub = filter == nil
            ? (isZh ? "包含提前命中与客观数据后验反应" : "includes early hits and post-data reactions")
            : (isZh ? "仅「我自己的判断」" : "「my own call」only")

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(title: title, subtitle: sub, dark: isDark)

                if settled.isEmpty {
                    emptyStateHint(
                        icon: "tray",
                        title: isZh ? "暂无已结算记录" : "No settled records yet",
                        subtitle: isZh ? "存证到期并完成对账后，这里会自动生成复盘流水" : "Once entries settle, the ledger fills in automatically."
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    settledLedgerTable(settled)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
    }

    /// 已结算 ledger 表（原型 .ledger）
    private func settledLedgerTable(_ entries: [PredictionEntry]) -> some View {
        VStack(spacing: 0) {
            // 表头
            settledLedgerHeader

            ForEach(entries) { entry in
                settledLedgerRow(entry)
                Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            }
        }
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var settledLedgerHeader: some View {
        HStack(spacing: 10) {
            Text(isZh ? "标的 / 来源" : "Ticker / Source")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(isZh ? "基准价" : "Entry")
                .frame(width: 92, alignment: .leading)
            Text(isZh ? "结算价" : "Settled")
                .frame(width: 108, alignment: .leading)
            Text(isZh ? "判定" : "Verdict")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(AT.text3(isDark))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AT.seg(isDark))
    }

    private func settledLedgerRow(_ entry: PredictionEntry) -> some View {
        let chgPct: Double? = {
            guard let settle = entry.settlementPrice, entry.entryPrice > 0 else { return nil }
            return (settle - entry.entryPrice) / entry.entryPrice * 100.0
        }()

        return HStack(spacing: 10) {
            // 标的与来源
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.ticker == "—" ? (isZh ? "客观数据" : "Fact") : entry.ticker)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(AT.text(isDark))
                    if let name = entry.tickerName, !name.isEmpty, entry.ticker != "—" {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AT.text3(isDark))
                    }
                }
                Text(settledNote(entry))
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.entryPrice > 0 ? String(format: "%.2f", entry.entryPrice) : "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AT.text2(isDark))
                .frame(width: 92, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(entry.settlementPrice != nil ? String(format: "%.2f", entry.settlementPrice!) : "--")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(AT.text(isDark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                if let c = chgPct {
                    Text(String(format: "%+.1f%%", c))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AT.riseFall(c, isDark))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 108, alignment: .leading)

            // 判定 tag 组
            HStack(spacing: 5) {
                verdictTags(entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { detailEntry = entry }
        .contextMenu {
            Button { detailEntry = entry } label: {
                Label("查看 / 修改存证详情", systemImage: "pencil")
            }
            Button(role: .destructive) {
                entryToDelete = entry
                showDeleteEntryAlert = true
            } label: {
                Label("删除此条存证", systemImage: "trash")
            }
        }
    }

    private func settledNote(_ entry: PredictionEntry) -> String {
        var parts: [String] = [entry.authorName]
        if let date = entry.settlementDate {
            let f = DateFormatter()
            f.dateFormat = "MM/dd HH:mm"
            parts.append(isZh ? "结算于 \(f.string(from: date))" : "settled \(f.string(from: date))")
        } else {
            parts.append(entry.horizon.rawValue)
        }
        return parts.joined(separator: " · ")
    }

    /// 判定徽章组：HIT / ⚡提前命中 / MISS / 📝客观数据 (+ 波动率 + 真实有效)
    @ViewBuilder
    private func verdictTags(_ entry: PredictionEntry) -> some View {
        if entry.entryType == .factualSnapshot {
            TagView(text: isZh ? "📝 客观数据" : "📝 Factual", style: .fact, dark: isDark)
            if let vol = entry.marketReactionVolatility {
                TagView(text: isZh ? "年化波动 \(String(format: "%.1f", vol))%" : "Ann. vol \(String(format: "%.1f", vol))%", style: .neutral, dark: isDark)
            }
            if entry.factCheckStatus == .verifiedValid {
                TagView(text: isZh ? "✓ 真实有效" : "✓ Verified", style: .winHi, dark: isDark)
            } else if entry.factCheckStatus == .falsified {
                TagView(text: isZh ? "✕ 数据失真" : "✕ Falsified", style: .bear, dark: isDark)
            }
        } else {
            switch entry.arbitrationStatus {
            case .hit:
                TagView(text: isZh ? "HIT 命中" : "HIT", style: .rise, dark: isDark)
            case .hitEarly:
                TagView(text: isZh ? "⚡ 提前命中" : "⚡ Early", style: .bull, dark: isDark)
            case .miss:
                TagView(text: isZh ? "MISS 未中" : "MISS", style: .fall, dark: isDark)
            case .expired:
                TagView(text: isZh ? "已失效" : "Expired", style: .neutral, dark: isDark)
            case .pending:
                TagView(text: isZh ? "进行中" : "Active", style: .warn, dark: isDark)
            }
        }
    }

    // MARK: - 3.4 我的预测校准（原型 viewCalib）

    private var myCalibrationView: some View {
        let stats = dashboardStats
        let mineActive = allEntries.filter { $0.isSelfJudgment && !$0.arbitrationStatus.isSettled }

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    title: isZh ? "我的预测校准" : "My Calibration",
                    subtitle: isZh ? "个人专属战绩与复盘流水 · 独立于外部博主" : "personal ledger, isolated from external KOLs",
                    dark: isDark
                )

                // 双卡：个人综合 + 各市场独立胜率（原型 .split-row）
                HStack(alignment: .top, spacing: 10) {
                    // 左卡
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(percentText(stats.selfWinRate))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(AT.winHi(isDark))
                            Text(isZh ? "个人综合胜率 · 样本 \(stats.selfSettled)" : "personal win rate · \(stats.selfSettled) samples")
                                .font(.system(size: 11))
                                .foregroundColor(AT.text3(isDark))
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            calibRow(
                                label: isZh ? "长期优势" : "Long edge",
                                value: percentText(stats.selfLongTermWinRate),
                                valueColor: AT.winRateColor(stats.selfLongTermWinRate, isDark),
                                note: isZh ? "长期 (3月+) 胜率" : "long-horizon win rate"
                            )
                            calibRow(
                                label: isZh ? "平均偏离" : "Avg deviation",
                                value: stats.avgDeviation != nil ? String(format: "+%.1f%%", stats.avgDeviation!) : "--",
                                valueColor: AT.text(isDark),
                                note: isZh ? "目标价激进程度" : "how aggressive your targets are"
                            )
                            calibRowChips(
                                label: isZh ? "认知人格" : "Persona",
                                chips: selfPersonaChips
                            )
                        }
                        .padding(.top, 11)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AT.cardBg(isDark))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))

                    // 右卡：各市场独立胜率（原型 .dist）
                    VStack(alignment: .leading, spacing: 8) {
                        let marketRows: [(String, Double?, Int)] = {
                            var rows: [(String, Double?, Int)] = []
                            for name in builtinMarketNames + customCategories {
                                let mine = allEntries.filter { $0.isSelfJudgment && $0.marketCategory == name }
                                let settled = mine.filter { $0.arbitrationStatus.isSettled }
                                let wins = settled.filter { $0.arbitrationStatus.isWin }.count
                                if !mine.isEmpty {
                                    rows.append((name, settled.isEmpty ? nil : Double(wins) / Double(settled.count) * 100.0, mine.count))
                                }
                            }
                            return rows
                        }()

                        if marketRows.isEmpty {
                            Text(isZh ? "暂无个人存证样本" : "No personal samples yet")
                                .font(.system(size: 11.5))
                                .foregroundColor(AT.text3(isDark))
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                        } else {
                            ForEach(marketRows, id: \.0) { row in
                                HStack(spacing: 9) {
                                    Text(row.0)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(AT.text3(isDark))
                                        .frame(width: 56, alignment: .leading)
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(AT.track(isDark))
                                                .frame(height: 7)
                                            if let rate = row.1 {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(AT.winRateColor(rate, isDark))
                                                    .frame(width: max(0, g.size.width * CGFloat(rate) / 100.0), height: 7)
                                            }
                                        }
                                    }
                                    .frame(height: 7)
                                    Text(row.1 != nil ? String(format: "%.0f%%", row.1!) : "—")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(AT.text2(isDark))
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }

                            Text(isZh ? "各市场独立胜率 · 括号为个人样本数" : "win rate per market · samples in brackets")
                                .font(.system(size: 10.5))
                                .foregroundColor(AT.text3(isDark))
                                .padding(.top, 2)
                            Text(marketRows.map { "\($0.0)(\($0.2))" }.joined(separator: " · "))
                                .font(.system(size: 10.5))
                                .foregroundColor(AT.text2(isDark))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AT.cardBg(isDark))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
                }

                // 进行中 · 个人存证
                SectionHead(
                    title: isZh ? "进行中 · 个人存证" : "Open personal entries",
                    hint: isZh ? "仅显示「我自己的判断」" : "「my own call」only",
                    dark: isDark
                )

                if mineActive.isEmpty {
                    emptyStateHint(
                        icon: "tray",
                        title: isZh ? "暂无进行中的个人存证" : "No open personal entries",
                        subtitle: isZh ? "按 ⌥A 录入你的第一条判断" : "Press ⌥A to log your first forecast."
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(mineActive) { entry in
                            entryCard(entry)
                                .contentShape(Rectangle())
                                .onTapGesture { detailEntry = entry }
                        }
                    }
                }

                // 已结算 · 个人复盘
                SectionHead(title: isZh ? "已结算 · 个人复盘" : "Settled personal", dark: isDark)
                let mineSettled = allEntries.filter { $0.isSelfJudgment && $0.arbitrationStatus.isSettled }
                if mineSettled.isEmpty {
                    Text(isZh ? "暂无已结算的个人记录" : "No settled personal records yet")
                        .font(.system(size: 11.5))
                        .foregroundColor(AT.text3(isDark))
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    settledLedgerTable(mineSettled)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
        .task { await refreshDashboardLivePrices() }
    }

    // MARK: - 3.5 KOL 红黑榜 + 认知人格卡片流（原型 viewMBTI）

    private var kolLedgerAndPersonasView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    title: isZh ? "KOL 战绩红黑榜与认知人格" : "KOL Ledger & Cognitive MBTI",
                    subtitle: isZh ? "四维加权算法 · 16 种投资人格建模" : "4-axis weighted model · 16 personas",
                    dark: isDark
                )

                kolLedgerTable

                SectionHead(
                    title: isZh ? "认知人格卡片流" : "Cognitive Personas",
                    hint: isZh ? "徽章 · 称号 · 四维百分比 · 避坑指南" : "badge · title · 4 axes · advice",
                    dark: isDark
                )

                if showAlgoLink {
                    Button(action: { showAlgoInfoAlert = true }) {
                        Text(isZh ? "算法解析 ℹ️" : "Algorithm ℹ️")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AT.accent)
                    }
                    .buttonStyle(.plain)
                }

                if currentFilteredCards.isEmpty {
                    emptyStateHint(
                        icon: "person.2.badge.gearshape",
                        title: isZh ? "暂无来源画像" : "No source profiles yet",
                        subtitle: isZh
                            ? "按 ⌥A 录入第一条观点存证，系统会自动生成该来源的认知 MBTI 画像"
                            : "Press ⌥A to log your first forecast and the cognitive MBTI profile will be generated automatically."
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(currentFilteredCards) { card in
                            personaCard(data: card)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
    }

    private var showAlgoLink: Bool {
        analyzer.selectedFilter == .mbtiRadar
    }

    // 3.5.1 KOL 红黑榜表（原型 .ledger：来源 | 胜率 | 条 | 样本 | 人格）
    private var kolLedgerTable: some View {
        let cards = analyzer.analyzeProfiles(profiles: allProfiles, entries: allEntries)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(isZh ? "来源" : "Source")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isZh ? "胜率" : "Win")
                    .frame(width: 64, alignment: .trailing)
                Text("")
                    .frame(width: 88)
                Text(isZh ? "样本" : "Calls")
                    .frame(width: 64, alignment: .trailing)
                Text(isZh ? "人格" : "Code")
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AT.text3(isDark))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AT.seg(isDark))

            if cards.isEmpty {
                emptyStateHint(
                    icon: "tablecells",
                    title: isZh ? "暂无战绩数据" : "No track record yet",
                    subtitle: isZh
                        ? "存证到期并完成对账后，这里会自动生成来源的红黑榜战绩"
                        : "Once entries expire and settle, the credibility leaderboard fills in automatically."
                )
            } else {
                ForEach(cards) { card in
                    kolLedgerRow(card)
                    Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                }
            }
        }
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func kolLedgerRow(_ card: MBTICardData) -> some View {
        let domain = card.domainTag.replacingOccurrences(of: "关注领域: ", with: "")

        return HStack(spacing: 10) {
            // 来源（头像 + 名称 + 领域）
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(AT.seg(isDark))
                    Text(card.avatarEmoji).font(.system(size: 13))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(card.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AT.text(isDark))
                            .lineLimit(1)
                        if card.isSelf {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AT.warn)
                        }
                    }
                    Text(domain)
                        .font(.system(size: 11))
                        .foregroundColor(AT.text3(isDark))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 胜率数值
            Text(card.totalCount > 0 ? String(format: "%.1f%%", card.winRate) : "—")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(card.totalCount > 0 ? winRateColor(card.winRate) : AT.text3(isDark))
                .frame(width: 64, alignment: .trailing)

            // 胜率条
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AT.track(isDark))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(winRateColor(card.totalCount > 0 ? card.winRate : nil))
                        .frame(width: max(0, g.size.width * CGFloat(card.winRate) / 100.0), height: 5)
                }
            }
            .frame(width: 88, height: 5)

            // 样本
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(card.totalCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AT.text(isDark))
                Text("+\(card.totalFacts)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
            }
            .frame(width: 64, alignment: .trailing)

            // 人格代码
            TagView(text: card.mbtiCode, style: .neutral, dark: isDark)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // 3.5.2 认知人格卡片（原型 .persona：axis-mini 四维 + 避坑指南）
    private func personaCard(data: MBTICardData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：头像 + 代码 + 称号 + 战绩 tag
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle().fill(AT.seg(isDark))
                    Text(data.avatarEmoji).font(.system(size: 13))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(data.mbtiCode)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(AT.text(isDark))
                        Text(data.mbtiTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AT.text(isDark))
                    }
                    Text("\(data.authorName) · \(isZh ? "样本" : "sample") \(data.totalCount)")
                        .font(.system(size: 11))
                        .foregroundColor(AT.text3(isDark))
                }

                Spacer()

                if data.totalCount > 0 {
                    Text(String(format: "%.1f%%", data.winRate))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(winRateColor(data.winRate))
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(winRateColor(data.winRate).opacity(0.14))
                        .cornerRadius(5)
                } else {
                    Text(isZh ? "不计胜率" : "n/a")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.text3(isDark))
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(AT.seg(isDark))
                        .cornerRadius(5)
                }
            }

            // 概述
            Text(data.tags.joined(separator: " · "))
                .font(.system(size: 11.5))
                .foregroundColor(AT.text2(isDark))
                .lineSpacing(2)
                .padding(.top, 10)
                .lineLimit(2)

            // 四维 axis-mini（原型 .axis-mini）
            VStack(spacing: 5) {
                axisMiniRow(
                    label: isZh ? "多空立场" : "Bias",
                    value: data.biasBullishPercent,
                    hiLetter: "B",
                    loLetter: "S"
                )
                axisMiniRow(
                    label: isZh ? "时间跨度" : "Horizon",
                    value: data.horizonCyclePercent,
                    hiLetter: "C",
                    loLetter: "D"
                )
                axisMiniRow(
                    label: isZh ? "归因内核" : "Driver",
                    value: data.driverFundamentalPercent,
                    hiLetter: "F",
                    loLetter: "T"
                )
                axisMiniRow(
                    label: isZh ? "博弈哲学" : "Payoff",
                    value: data.payoffAggressivePercent,
                    hiLetter: "A",
                    loLetter: "P"
                )
            }
            .padding(.top, 12)

            // 轴两端标注
            HStack {
                Spacer()
                Text("S · D · T · P")
                Spacer()
                Text("B · C · F · A")
                Spacer()
            }
            .font(.system(size: 9.5))
            .foregroundColor(AT.text3(isDark))
            .padding(.leading, 62)
            .padding(.top, 2)
            .padding(.bottom, 12)

            // 避坑指南（原型 .advice）
            HStack(alignment: .top, spacing: 4) {
                Text(isZh ? "怎么抄 " : "How to use ")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AT.text(isDark))
                Text(data.copilotAdvice)
                    .font(.system(size: 11.5))
                    .foregroundColor(AT.text2(isDark))
                    .lineSpacing(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AT.seg(isDark))
            .cornerRadius(10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
    }

    /// 原型 .axis-mini：62pt 标签 + 5pt 轨道 + 字母数值
    private func axisMiniRow(label: String, value: Double, hiLetter: String, loLetter: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))
                .frame(width: 62, alignment: .leading)

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AT.track(isDark))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value >= 50 ? AT.accent : AT.text3(isDark))
                        .frame(width: max(0, g.size.width * CGFloat(min(100, max(0, value))) / 100.0), height: 5)
                }
            }
            .frame(height: 5)

            Text("\(value >= 50 ? hiLetter : loLetter) \(Int(value))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(AT.text2(isDark))
                .frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: - 通用空态

    private func emptyStateHint(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(AT.text3(isDark))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AT.text2(isDark))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    // MARK: - 新增行情分类弹窗

    private var addCategorySheet: some View {
        VStack(spacing: 16) {
            Text(isZh ? "新增自定义行情分类" : "Add Custom Market Category")
                .font(.system(size: 14, weight: .bold))

            TextField(isZh ? "例如：商品期货、国内黄金、外汇、美债" : "e.g. Commodities, FX, US Bonds", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: 12) {
                Button(isZh ? "取消" : "Cancel") {
                    showAddCategorySheet = false
                    newCategoryName = ""
                }
                .buttonStyle(.plain)

                Button(isZh ? "确认添加" : "Add") {
                    let clean = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && !customCategories.contains(clean) {
                        customCategories = customCategories + [clean]
                    }
                    showAddCategorySheet = false
                    newCategoryName = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320, height: 160)
    }
}
