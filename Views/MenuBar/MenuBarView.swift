//
//  MenuBarView.swift
//  AlphaTrack
//
//  PRD v2.0 / 原型 v4 对齐：菜单栏微面板 (Menu Bar Popover)
//  紧凑展示活跃监控 (最多8条)、上次对账状态、价格推进度与倒计时，
//  底部 2×2 操作网格（快速录入主按钮 + 主面板 / 立即对账 / 设置 ghost 按钮）。
//

import SwiftUI
import SwiftData
import AppKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var engine = ArbitrationEngine.shared
    /// 与主面板/设置页共用同一主题源（MBTIAnalyzer.themeMode）
    @ObservedObject private var theme = MBTIAnalyzer.shared

    @Query(sort: \PredictionEntry.targetDate, order: .forward)
    private var allEntries: [PredictionEntry]

    @State private var livePrices: [String: Double] = [:]
    @State private var isRefreshingPrices: Bool = false

    /// 与主面板共用同一主题：light/dark 直接锁定，自动跟随系统外观
    private var currentColorScheme: ColorScheme {
        switch theme.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemColorScheme
        }
    }

    private var isDark: Bool { currentColorScheme == .dark }

    /// 自定义行情分类（与主面板/HUD 共用同一存储），用于排序
    @AppStorage("AlphaTrack.customMarketCategories")
    private var customCategoriesRaw: String = "黄金与大宗商品"
    private var customCategories: [String] {
        customCategoriesRaw
            .split(separator: "|", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// 进行中的记录，最多展示 8 条。
    /// 排序与主面板"活跃进行中"一致：按行情分类顺序（A股→美股→港股→Crypto→自定义…），
    /// 同分类内最新录入在前——排序决定权在侧栏的行情分类顺序
    private var pendingEntries: [PredictionEntry] {
        let active = allEntries.filter { !$0.arbitrationStatus.isSettled }
        let sorted = PredictionEntry.sortedByMarketCategory(
            active,
            customCategories: customCategories
        )
        return Array(sorted.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView()
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            scanStatusView()
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            contentView()
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            footerView()
        }
        .frame(width: 380)
        .background(AT.windowBg(isDark))
        .preferredColorScheme(currentColorScheme)
        .task { await refreshPrices() }
        // 每次面板弹出都重新拉取现价（.task 只在首次出现时执行，
        // 之后新增的标的会拿不到实时价），并避免首弹时 .task 与通知重复拉取
        .onReceive(NotificationCenter.default.publisher(for: .menubarPanelWillShow)) { _ in
            Task { await refreshPrices() }
        }
    }

    // MARK: - 顶部状态栏（原型 .pop-head）
    private func headerView() -> some View {
        let count = allEntries.filter { !$0.arbitrationStatus.isSettled }.count
        return HStack(spacing: 8) {
            Text("活跃监控")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(AT.text(isDark))
            Text("\(min(count, 8))/8")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AT.text3(isDark))
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    // MARK: - 对账扫描状态行（原型 .mb-scan）
    private func scanStatusView() -> some View {
        let lastRunText: String = {
            guard let at = engine.lastRunAt else { return "尚未对账" }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "\(f.string(from: at))"
        }()
        let pendingCount = pendingEntries.count

        return HStack(spacing: 7) {
            if isRefreshingPrices || engine.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text3(isDark))
            }

            Text("上次对账")
                .font(.system(size: 10.5))
                .foregroundColor(AT.text2(isDark))
            Text(lastRunText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(AT.text(isDark))

            if let report = engine.lastReport {
                Text("· \(report.summary)")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text2(isDark))
                    .lineLimit(1)
            }

            Spacer()

            Text("\(pendingCount) 条待判")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(AT.accent)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(AT.seg(isDark))
    }

    // MARK: - 主体列表（原型 .mb-item）
    private func contentView() -> some View {
        Group {
            if pendingEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundColor(AT.text3(isDark))
                    Text("暂无进行中的判断")
                        .font(.system(size: 12))
                        .foregroundColor(AT.text2(isDark))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                let rows = pendingEntries.map { entry in
                    MenuBarRowData(
                        entry: entry,
                        currentPrice: livePrices[entry.ticker],
                        progress: progress(for: entry)
                    )
                }

                // 不再用 ScrollView：条目上限 8 条，直接全部展示让面板高度自适应内容，
                // 避免出现"2/8 却要滚动才能看全"的体验
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        MenuBarEntryRow(data: row, isDark: isDark)
                        Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - 底部 2×2 操作网格（原型 .pop-foot）
    private func footerView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = engine.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(AT.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 6) {
                // 主按钮：快速录入 ⌥A
                Button(action: {
                    HUDPanelController.shared.show()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("快速录入 ⌥A")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .background(AT.accent)
                    .cornerRadius(8)
                }
                .buttonStyle(PressStyle())

                ghostFooterButton("主面板") {
                    let existing = NSApp.windows.first { window in
                        !window.isKind(of: NSPanel.self) && window.canBecomeMain && window.isVisible
                    } ?? NSApp.windows.first { window in
                        !window.isKind(of: NSPanel.self) && window.canBecomeMain
                    }

                    if let win = existing {
                        if win.isMiniaturized { win.deminiaturize(nil) }
                        win.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }

            HStack(spacing: 6) {
                ghostFooterButton("立即对账", disabled: engine.isRunning) {
                    Task {
                        await engine.runArbitration()
                        await PriceAlertMonitor.shared.checkNow(force: true)
                    }
                }

                ghostFooterButton("设置") {
                    MenubarPanelController.shared.openSettings()
                }
            }
        }
        .padding(11)
        .background(AT.sidebarBg(isDark))
    }

    /// 原型 .pop-foot .btn-ghost：灰底 ghost 按钮
    private func ghostFooterButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(disabled ? AT.text3(isDark) : AT.text2(isDark))
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(AT.seg(isDark))
                .cornerRadius(8)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }

    // MARK: - 数据与计算
    private func refreshPrices() async {
        let tickers = Array(Set(pendingEntries.map { $0.ticker }).prefix(8))
        guard !tickers.isEmpty else { return }
        // 防重入：首弹时 .task 与 willShow 通知可能同时触发
        guard !isRefreshingPrices else { return }

        isRefreshingPrices = true
        defer { isRefreshingPrices = false }

        let items = pendingEntries.map { (ticker: $0.ticker, preferredMarket: Optional($0.marketCategory)) }
        let results = await MarketDataService.shared.batchFetchQuotes(for: items)
        var map: [String: Double] = [:]
        for (ticker, result) in results {
            if case .success(let quote) = result {
                map[ticker] = quote.price
            }
        }
        livePrices = map
    }

    private func progress(for entry: PredictionEntry) -> Double {
        if let target = entry.targetPrice, entry.entryPrice > 0,
           let current = livePrices[entry.ticker] {
            let span = target - entry.entryPrice
            guard abs(span) > 0.0001 else { return 1.0 }
            // 带方向的完成度：公式 (现价-基准)/(目标-基准) 天然带符号
            // —— 价格朝目标走为正，反向走为负（猜错方向）。
            // 正向 100% 封顶，反向 -100% 封底，避免出现没有直觉的 -300%
            return min(1.0, max(-1.0, (current - entry.entryPrice) / span))
        }

        let total = entry.targetDate.timeIntervalSince(entry.createdAt)
        guard total > 0 else { return 1.0 }
        return min(1.0, max(0.0, 1.0 - entry.timeRemaining / total))
    }
}

// MARK: - 列表行
private struct MenuBarRowData: Identifiable {
    let entry: PredictionEntry
    let currentPrice: Double?
    let progress: Double

    var id: PersistentIdentifier { entry.persistentModelID }
}

private struct MenuBarEntryRow: View {
    let data: MenuBarRowData
    let isDark: Bool
    private var entry: PredictionEntry { data.entry }

    private var changePercent: Double? {
        guard let cur = data.currentPrice, entry.entryPrice > 0 else { return nil }
        return (cur - entry.entryPrice) / entry.entryPrice * 100.0
    }

    /// 完成度数字颜色：价格模式用主文字色（黑白，与双向进度条一致，
    /// 对错由 +/- 符号表达）；时间消耗模式保持次要灰
    private var progressLabelColor: Color {
        if entry.targetPrice != nil, data.currentPrice != nil {
            return AT.text(isDark)
        }
        return AT.text2(isDark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Arrow, Ticker, Source
            HStack(spacing: 7) {
                if entry.entryType == .factualSnapshot {
                    Text("▬")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AT.accent)
                } else {
                    Text(entry.direction == .bearish ? "▼" : "▲")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(entry.direction == .bearish ? AT.bear(isDark) : AT.bull(isDark))
                }

                Text(entry.ticker == "—" ? "客观" : entry.ticker)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(AT.text(isDark))

                // 标的名称（与主面板卡片一致的灰色小字），无名称或纯事实记录不显示
                if let name = entry.tickerName, !name.isEmpty, entry.ticker != "—" {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(AT.text3(isDark))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Text(entry.authorName)
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
                    .lineLimit(1)
            }

            // Row 2: Base -> Now (with colored % chg) and Target
            HStack(spacing: 8) {
                Text(Self.price(entry.entryPrice))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AT.text2(isDark))

                if let cur = data.currentPrice {
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundColor(AT.text3(isDark))

                    Text(Self.price(cur))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        // 现价数字按行情着色：涨绿跌红（与旁边涨跌幅同义）
                        .foregroundColor(changePercent.map { AT.riseFall($0, isDark) } ?? AT.text(isDark))

                    if let chg = changePercent {
                        Text(String(format: "%+.2f%%", chg))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(AT.riseFall(chg, isDark))
                    }
                }

                Spacer()

                if let target = entry.targetPrice {
                    // 目标价用立场色（看多绿/看空红）+ 加粗，让判断方向一眼可辨；
                    // "目标"标签保持灰色以维持层级。纯事实记录（无方向）保持中性灰。
                    let stanceColor: Color = {
                        switch entry.direction {
                        case .bullish: return AT.bull(isDark)
                        case .bearish: return AT.bear(isDark)
                        case nil: return AT.text2(isDark)
                        }
                    }()
                    HStack(spacing: 4) {
                        Text("目标")
                            .font(.system(size: 11))
                            .foregroundColor(AT.text3(isDark))
                        Text(Self.price(target))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(stanceColor)
                    }
                }
            }

            // Row 3: B2 目标达成轨
            // 基准恒在左 1/4 处、目标在最右端，向右 = 靠近目标（与多空无关）；
            // 现价点位置即完成度，点跑到基准左侧 = 走反了。零解码、无颜色编码。
            // 微面板空间紧张，省略端点文字标签。
            GeometryReader { g in
                let w = g.size.width
                if entry.targetPrice != nil, data.currentPrice != nil {
                    let overflowW: CGFloat = w / 4
                    let trackW: CGFloat = w - overflowW
                    let p = max(-1, min(1, data.progress))
                    let x = p >= 0 ? overflowW + CGFloat(p) * trackW
                                   : overflowW + CGFloat(p) * overflowW
                    let trackH: CGFloat = 3
                    let dot: CGFloat = 7

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AT.track(isDark).opacity(0.55))
                            .frame(width: overflowW, height: trackH)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(AT.track(isDark))
                            .frame(width: trackW, height: trackH)
                            .offset(x: overflowW)

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

                        Rectangle()
                            .fill(AT.text3(isDark).opacity(0.5))
                            .frame(width: 1, height: 7)
                            .offset(x: overflowW)

                        Circle()
                            .fill(AT.text(isDark))
                            .frame(width: dot, height: dot)
                            .overlay(Circle().stroke(AT.windowBg(isDark), lineWidth: 1.2))
                            .offset(x: max(0, min(w - dot, x - dot / 2)))
                    }
                } else {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AT.track(isDark))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AT.accent)
                            .frame(width: max(0, w * CGFloat(min(1.0, max(0.0, data.progress)))), height: 3)
                    }
                }
            }
            .frame(height: 9)

            // Row 4: Progress meta & Due countdown
            HStack {
                let pct = Int(round(data.progress * 100))
                Text(entry.targetPrice != nil ? "价格完成度 \(pct)%" : "时间消耗 \(pct)%")
                    .font(.system(size: 10))
                    // 颜色跟随行情色（涨红跌绿，与旁边涨跌幅同义），
                    // 不新增"对错色"；正/负由数字符号表达
                    .foregroundColor(progressLabelColor)

                Spacer()

                Text("剩余 \(Self.countdown(entry))")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text2(isDark))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private static func price(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func countdown(_ entry: PredictionEntry) -> String {
        let remaining = entry.timeRemaining
        guard remaining > 0 else { return "已到期" }

        let total = Int(remaining)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }
}
