//
//  QuickEntryView.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//  UI 依据 AlphaTrack_Prototype_v4.html 的 HUD 六层结构完全对齐：
//  头部：绿点 + 快速存证 + ⌥A / ESC 键帽
//  L1 行情分类（胶囊 + 切换自动重抓市价）
//  L2 标的 · 基准价（状态灯在标签行）· 目标价（盈亏比）· 方向（多/空实色按钮）
//  L3 客观数据三列（推论单选 + 文字摘要 + 56pt 截图框）
//  L4 有效验证周期（全周期胶囊 + 到期时刻）
//  L5 来源归属（我自己的判断 + 来源档案胶囊：数字键 + 胜率）
//  L6 Apple 生态协同（行内勾选框，默认不勾选）
//  底部：时效摘要 + 取消 + 存入对账账本 ⌘↩
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct QuickEntryView: View {
    @Environment(\.modelContext) private var modelContext

    /// 关闭浮窗回调
    var onDismiss: () -> Void

    // MARK: - 主题与外观
    @ObservedObject private var theme = MBTIAnalyzer.shared
    @Environment(\.colorScheme) private var systemColorScheme

    private var currentColorScheme: ColorScheme {
        switch theme.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemColorScheme
        }
    }

    fileprivate var isDark: Bool {
        currentColorScheme == .dark
    }

    // MARK: - SwiftData 历史博主档案
    @Query(sort: \SourceProfile.lastUsedAt, order: .reverse)
    private var allProfiles: [SourceProfile]

    // MARK: - 状态管理

    // 标的代码与名称
    @State private var tickerInput: String = ""
    @State private var tickerDisplayName: String = ""

    // 行情分类
    @State private var selectedMarketCategory: String = "A股"
    @State private var isCustomMarketEditing: Bool = false
    @State private var customMarketText: String = ""

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

    // 多空观点
    @State private var viewMode: HUDViewMode = .bullish

    // 入场基准价
    @State private var entryPrice: Double = 1480.00
    @State private var entryPriceInput: String = "1480.00"
    @State private var isManuallyAdjustedPrice: Bool = false
    @State private var priceCurrency: String = "CNY"
    @State private var isFetchingQuote: Bool = false
    @State private var quoteErrorMessage: String?

    // 目标价
    @State private var targetPriceInput: String = ""

    // 客观事实与衍生推论
    @State private var factualSummaryInput: String = ""
    @State private var factualInferenceDirection: FactualInferenceDirection = .none

    // 有效验证周期
    @State private var selectedHorizon: VerificationHorizon = .days30
    @State private var customTargetDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var showCustomDatePicker: Bool = false
    @State private var customDurationValue: String = "5"
    @State private var customDurationUnit: String = "分钟"

    // 证据截图
    @State private var attachedImageRelativePath: String?
    @State private var attachedImageFilename: String?
    @State private var attachedThumbnail: NSImage?
    @State private var isDropTargeted: Bool = false

    // 来源归属
    @State private var isSelfJudgment: Bool = false
    @State private var authorNameInput: String = ""
    @State private var isKeepSourceEnabled: Bool = true
    @State private var isNewAuthorEditing: Bool = false

    // Apple 生态联动 (默认全部为 false 不勾选)
    @State private var syncToReminders: Bool = false
    @State private var syncToCalendar: Bool = false

    // 防抖与任务
    @State private var tickerDebounceTask: Task<Void, Never>?

    // 提交校验提示
    @State private var submitValidationMessage: String?

    // MARK: - 模式枚举
    enum HUDViewMode: String, CaseIterable, Identifiable {
        case bullish = "bullish"
        case bearish = "bearish"
        case fact = "fact"

        var id: String { rawValue }
    }

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // MARK: - 颜色 Tokens（HUD 面板表面）

    private var panelBackgroundFill: Color {
        isDark
            ? Color(red: 32/255, green: 33/255, blue: 37/255).opacity(0.94)
            : Color.white.opacity(0.96)
    }

    private var panelShadowColor: Color {
        isDark ? .black.opacity(0.55) : .black.opacity(0.28)
    }

    // MARK: - 视图主体

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    layer(L1Header) { marketCategoryLayer }
                    layer(L2Header) { coreTickerAndPriceLayer }
                    layer(L3Header) { factualDataLayer }
                    layer(L4Header) { horizonLayer }
                    layer(L5Header) { sourceLayer }
                    layer(L6Header) { appleSyncLayer }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
            }

            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            footerBar
        }
        .frame(width: 650, height: 640)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(panelBackgroundFill)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AT.cardBorder(isDark), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: panelShadowColor, radius: 30, x: 0, y: 15)
        .preferredColorScheme(currentColorScheme)
        .onAppear {
            if let m = HUDPanelController.shared.currentPresetMarket {
                applyPresetMarket(m)
            }
            if let s = HUDPanelController.shared.currentPresetIsSelf {
                self.isSelfJudgment = s
            }
            setupInitialState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AlphaTrack_PresetHUD"))) { note in
            if let market = note.userInfo?["market"] as? String {
                applyPresetMarket(market)
            }
            if let isSelf = note.userInfo?["isSelf"] as? Bool {
                self.isSelfJudgment = isSelf
            }
        }
        .onChange(of: tickerInput) { _, _ in
            if submitValidationMessage != nil { submitValidationMessage = nil }
        }
        .onChange(of: factualSummaryInput) { _, _ in
            if submitValidationMessage != nil { submitValidationMessage = nil }
        }
    }

    // MARK: - 头部（原型 .hud-head：绿点 + 标题 + 键帽）
    private var headerBar: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(AT.winHi(isDark))
                .frame(width: 8, height: 8)

            Text("快速存证")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AT.text(isDark))

            KbdBadge(key: "⌥ A")

            Spacer()

            HStack(spacing: 4) {
                Text("ESC 关闭")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text3(isDark))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    // MARK: - 层容器（原型 .layer：hairline 分隔，非卡片）
    // 所有 layer 统一按 leading 排版且撑满宽度，
    // 这样 L1/L5 等较窄的行就会和 L2/L3 一样贴左对齐。
    private func layer<Header: View, Content: View>(
        _ header: Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
        .overlay(
            Rectangle().fill(AT.sep(isDark)).frame(height: 1),
            alignment: .bottom
        )
        .padding(.bottom, 10)
    }

    /// 原型 .layer-n：L 徽章 + 标题 + 可选说明
    private func layerN(_ l: String, _ title: String, opt: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(l)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(AT.text3(isDark))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(AT.seg(isDark))
                .cornerRadius(4)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AT.text2(isDark))
            if let opt {
                Text(opt)
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.text3(isDark))
            }
        }
    }

    private var L1Header: some View {
        layerN("L1", "行情分类", opt: "切换自动重抓市价")
    }

    private var L2Header: some View {
        layerN("L2", "标的 · 基准价 · 目标价 · 方向")
    }

    private var L3Header: some View {
        layerN("L3", "客观数据与现状观察 (双轨制)", opt: "选择推论即标记为客观事实")
    }

    private var L4Header: some View {
        HStack(spacing: 6) {
            layerN("L4", "有效验证周期")
            Spacer()
            // 点头部到期时间可展开自定义面板
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    showCustomDatePicker.toggle()
                    if showCustomDatePicker {
                        selectedHorizon = .custom
                    }
                }
            }) {
                HStack(spacing: 3) {
                    Text("到期")
                        .font(.system(size: 10.5))
                        .foregroundColor(AT.text3(isDark))
                    Text(dueSummaryText)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(AT.text2(isDark))
                        .underline(color: AT.text3(isDark))
                }
            }
            .buttonStyle(PressStyle())
        }
    }

    private var L5Header: some View {
        layerN("L5", "来源归属", opt: "数字键 1–4 快速点选 · 连续存证自动记忆")
    }

    private var L6Header: some View {
        // L6 在原型中是 inline 单行：L 徽章 + 标题 + 说明 + 勾选框在右侧
        // 不再走 layer 容器，直接渲染成 HUD 内嵌行
        HStack(spacing: 6) {
            Text("L6")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(AT.text3(isDark))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(AT.seg(isDark))
                .cornerRadius(4)
            Text("Apple 生态协同")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AT.text2(isDark))
            Text("默认不勾选")
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))
            Spacer()
            HStack(spacing: 14) {
                ATCheckbox(title: "同步至 Apple 提醒事项", isOn: syncToReminders) {
                    syncToReminders.toggle()
                }
                ATCheckbox(title: "写入系统日历", isOn: syncToCalendar) {
                    syncToCalendar.toggle()
                }
            }
        }
    }

    // MARK: - L1 行情分类（原型 .cat-row）

    private var marketCategoryLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                // 内置分类与主面板侧栏 builtinMarketNames 完全一致（4 个），
                // 不再硬编码 v1 遗留的"黄金白银/商品期货"胶囊
                catPill(flag: "🇨🇳", title: "A股", category: "A股")
                catPill(flag: "🇺🇸", title: "美股", category: "美股")
                catPill(flag: "🇭🇰", title: "港股", category: "港股")
                catPill(flag: "🪙", title: "Crypto", category: "Crypto")

                // 自定义分类与主面板共用同一 @AppStorage，同步渲染；
                // 过滤 v1 遗留分类，防止旧 UserDefaults 数据再次出现
                ForEach(customCategories.filter { !["黄金白银", "商品期货"].contains($0) }, id: \.self) { cat in
                    catPill(flag: cat == "黄金与大宗商品" ? "🟡" : "⚡", title: cat, category: cat)
                }
            }

            if isCustomMarketEditing {
                customMarketInputRow
            }
        }
    }

    private func catPill(flag: String, title: String, category: String) -> some View {
        let isSelected = selectedMarketCategory == category
        return Button(action: {
            selectedMarketCategory = category
            triggerQuoteFetch()
        }) {
            HStack(spacing: 4) {
                Text(flag).font(.system(size: 11))
                Text(title).font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : AT.text2(isDark))
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(isSelected ? AT.accent : Color.clear)
            .overlay(
                Capsule().stroke(
                    isSelected ? AT.accent : AT.cardBorder(isDark),
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var customMarketInputRow: some View {
        HStack(spacing: 6) {
            TextField("输入自定义分类名，如：外汇、期权、美债", text: $customMarketText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(AT.text(isDark))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
                .onSubmit(commitCustomCategory)

            Button("添加") { commitCustomCategory() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AT.accent)

            Button("取消") {
                isCustomMarketEditing = false
                customMarketText = ""
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(AT.text2(isDark))
        }
        .padding(.top, 2)
    }

    private func commitCustomCategory() {
        let clean = customMarketText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            customMarketText = ""
            isCustomMarketEditing = false
        }
        guard !clean.isEmpty else { return }
        if !customCategories.contains(clean) {
            customCategories = customCategories + [clean]
        }
        selectedMarketCategory = clean
    }

    // MARK: - L2 四要素（原型 .quad：145pt 标的 | 基准价 | 目标价 | 方向）

    private var coreTickerAndPriceLayer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 1. 标的代码（145pt）
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel {
                    Text("标的代码")
                    Spacer()
                    if tickerInput.isEmpty && !factualSummaryInput.isEmpty {
                        Text("· 纯事实模式")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(AT.accent)
                    } else if !tickerDisplayName.isEmpty && tickerDisplayName != tickerInput {
                        Text(tickerDisplayName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(AT.accent)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    TextField("如 600519 / NVDA", text: $tickerInput)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(AT.text(isDark))
                        .textFieldStyle(.plain)
                        .onChange(of: tickerInput) { _, newValue in
                            handleTickerChanged(newValue)
                        }

                    if isFetchingQuote {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(width: 145)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
            }

            // 2. 入场基准价（状态灯置于标签行，原型 .lb .st2）
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel {
                    Text("入场基准价")
                    HStack(spacing: 3) {
                        Circle()
                            .fill(priceStateColor)
                            .frame(width: 5, height: 5)
                        Text(priceStateText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(priceStateColor)
                        Button(action: {
                            isManuallyAdjustedPrice = false
                            triggerQuoteFetch()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundColor(AT.text3(isDark))
                        }
                        .buttonStyle(.plain)
                        .help("重新抓取实盘价格")
                    }
                    .help(quoteErrorMessage ?? "实盘报价正常")
                }

                HStack(spacing: 5) {
                    Text(currencySymbol)
                        .font(.system(size: 12))
                        .foregroundColor(AT.text3(isDark))

                    TextField("0.00", text: $entryPriceInput)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(AT.text(isDark))
                        .textFieldStyle(.plain)
                        .onChange(of: entryPriceInput) { _, newValue in
                            if let val = Double(newValue.replacingOccurrences(of: ",", with: "")), val > 0 {
                                entryPrice = val
                                isManuallyAdjustedPrice = true
                            }
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
            }

            // 3. 目标价（选填，标签行右侧盈亏比，原型 .ratio）
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel {
                    Text("目标价 (选填)")
                    Spacer()
                    if let ratio = targetRatio {
                        Text(String(format: "预期 %+.1f%%", ratio))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(AT.winHi(isDark))
                    }
                }

                HStack(spacing: 5) {
                    Text(currencySymbol)
                        .font(.system(size: 12))
                        .foregroundColor(AT.text3(isDark))

                    TextField("0.00", text: $targetPriceInput)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(AT.text(isDark))
                        .textFieldStyle(.plain)
                        .onChange(of: targetPriceInput) { _, newValue in
                            let cleaned = newValue.replacingOccurrences(of: ",", with: "")
                            if Double(cleaned) == nil && !cleaned.isEmpty {
                                targetPriceInput = String(targetPriceInput.filter { "0123456789.".contains($0) })
                            }
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
            }

            // 4. 方向（原型 .dir-btns：实色 bull / bear）
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel { Text("方向") }

                HStack(spacing: 5) {
                    dirButton(mode: .bullish, symbol: "▲", title: "看多")
                    dirButton(mode: .bearish, symbol: "▼", title: "看空")
                }
            }
        }
    }

    private func fieldLabel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(AT.text3(isDark))
        .frame(height: 13)
    }

    private var currencySymbol: String {
        switch priceCurrency {
        case "CNY": return "¥"
        case "USD": return "$"
        case "HKD": return "HK$"
        default: return ""
        }
    }

    private var priceStateColor: Color {
        if isManuallyAdjustedPrice { return AT.accent }
        if quoteErrorMessage != nil { return AT.warn }
        return AT.winHi(isDark)
    }

    private var priceStateText: String {
        if isManuallyAdjustedPrice { return "手动" }
        if quoteErrorMessage != nil { return "未联网" }
        return "实时"
    }

    private var targetRatio: Double? {
        guard let ep = Double(entryPriceInput.replacingOccurrences(of: ",", with: "")), ep > 0,
              let tp = Double(targetPriceInput.replacingOccurrences(of: ",", with: "")), tp > 0 else { return nil }
        return (tp - ep) / ep * 100.0
    }

    private func dirButton(mode: HUDViewMode, symbol: String, title: String) -> some View {
        let isSelected = viewMode == mode
        let solidColor = mode == .bullish ? AT.bull(isDark) : AT.bear(isDark)

        return Button(action: {
            withAnimation(.easeOut(duration: 0.14)) { viewMode = mode }
        }) {
            HStack(spacing: 4) {
                Text(symbol).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : AT.text2(isDark))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(isSelected ? solidColor : AT.control(isDark))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? solidColor : AT.cardBorder(isDark), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - L3 客观数据三列（原型 .fact-grid：175pt 单选 | 文字 | 64pt 截图）

    private var factualDataLayer: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左：3 个推论单选
            VStack(spacing: 4) {
                inferenceRadioItem(direction: .none, symbol: "·", title: "纯客观 (无推论)")
                inferenceRadioItem(direction: .bullish, symbol: "▲", title: "衍生看多")
                inferenceRadioItem(direction: .bearish, symbol: "▼", title: "衍生看空")
            }
            .frame(width: 175)

            // 中：事实摘要
            ZStack(alignment: .topLeading) {
                if factualSummaryInput.isEmpty {
                    Text("输入行业指标、调研纪要或链上客观数据…")
                        .font(.system(size: 12))
                        .foregroundColor(AT.text3(isDark))
                        .lineSpacing(3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $factualSummaryInput)
                    .font(.system(size: 12))
                    .foregroundColor(AT.text(isDark))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
            }
            .frame(minHeight: 96)
            .frame(maxWidth: .infinity)
            .background(AT.control(isDark))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))

            // 右：56pt 截图框（原型 .shot-box）
            VStack(spacing: 5) {
                shotBox
                Text("证据 ⌘V")
                    .font(.system(size: 10))
                    .foregroundColor(AT.text3(isDark))
            }
        }
    }

    private var shotBox: some View {
        ZStack {
            if let thumb = attachedThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 15))
                    .foregroundColor(isDropTargeted ? AT.accent : AT.text3(isDark))
            }
        }
        .frame(width: 56, height: 56)
        .background(
            ZStack {
                if attachedThumbnail == nil {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted ? AT.accent.opacity(0.08) : AT.seg(isDark))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    attachedThumbnail == nil
                        ? (isDropTargeted ? AT.accent : AT.cardBorder(isDark))
                        : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: attachedThumbnail == nil ? [4, 3] : [])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if attachedThumbnail != nil {
                removeAttachment()
            } else {
                handlePasteImage()
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .help(attachedThumbnail != nil ? "点击移除截图" : "拖拽或点击粘贴截图")
    }

    private func inferenceRadioItem(direction: FactualInferenceDirection, symbol: String, title: String) -> some View {
        let isSelected = factualInferenceDirection == direction
        return Button(action: {
            factualInferenceDirection = direction
            // 任何「客观数据 / 现状观察」的推论选项都视为事实存证模式 (.fact)
            viewMode = .fact
        }) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AT.accent : AT.text3(isDark), lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                    if isSelected {
                        Circle()
                            .fill(AT.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AT.text2(isDark))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AT.accent : AT.text2(isDark))
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(isSelected ? AT.accent.opacity(0.10) : AT.control(isDark))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - L4 有效验证周期（原型 .hz-row：全周期胶囊）

    private var horizonLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                horizonPill(horizon: .min1, title: "1 分钟")
                horizonPill(horizon: .min5, title: "5 分钟")
                horizonPill(horizon: .min15, title: "15 分钟")
                horizonPill(horizon: .hour1, title: "1 小时")
                horizonPill(horizon: .hours4, title: "4 小时")
                horizonPill(horizon: .hours12, title: "12 小时")
                horizonPill(horizon: .hours24, title: "24 小时")
                horizonPill(horizon: .days3, title: "3 天")
                horizonPill(horizon: .days7, title: "7 天")
                horizonPill(horizon: .days30, title: "30 天")
                horizonPill(horizon: .longTerm, title: "长期")
            }

            // 自定义面板（点击头部到期时间展开）
            if showCustomDatePicker {
                customHorizonPanel
            }
        }
    }

    private func horizonPill(horizon: VerificationHorizon, title: String) -> some View {
        let isSelected = selectedHorizon == horizon
        return Button(action: {
            selectedHorizon = horizon
            showCustomDatePicker = false
            if let interval = horizon.defaultTimeInterval {
                customTargetDate = Date().addingTimeInterval(interval)
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AT.text2(isDark))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(isSelected ? AT.accent : Color.clear)
                .overlay(
                    Capsule().stroke(isSelected ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var customHorizonPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 快捷短线
            HStack(spacing: 5) {
                Text("⚡ 快捷短线:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AT.text3(isDark))

                quickDurationPill(title: "1分钟", seconds: 60)
                quickDurationPill(title: "5分钟", seconds: 300)
                quickDurationPill(title: "15分钟", seconds: 900)
                quickDurationPill(title: "1小时", seconds: 3600)
                quickDurationPill(title: "4小时", seconds: 14400)
            }

            // 自由数值与单位
            HStack(spacing: 8) {
                Text("自定义时长:")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text2(isDark))

                TextField("数值", text: $customDurationValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 45)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AT.control(isDark))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(AT.cardBorder(isDark), lineWidth: 1))
                    .onChange(of: customDurationValue) { _, _ in
                        applyCustomDuration()
                    }

                Picker("", selection: $customDurationUnit) {
                    Text("分钟").tag("分钟")
                    Text("小时").tag("小时")
                    Text("天").tag("天")
                    Text("月").tag("月")
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .onChange(of: customDurationUnit) { _, _ in
                    applyCustomDuration()
                }

                Spacer()
            }

            // 精确时刻
            HStack(spacing: 8) {
                Text("指定时刻:")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text2(isDark))

                DatePicker(
                    "",
                    selection: $customTargetDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(.system(size: 11))

                Spacer()
            }
        }
        .padding(8)
        .background(AT.seg(isDark).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .padding(.top, 2)
    }

    private func quickDurationPill(title: String, seconds: TimeInterval) -> some View {
        let isSelected = selectedHorizon == .custom && abs(customTargetDate.timeIntervalSince(Date()) - seconds) < 5
        return Button(action: {
            selectedHorizon = .custom
            showCustomDatePicker = true
            customTargetDate = Date().addingTimeInterval(seconds)
            if seconds < 3600 {
                customDurationValue = "\(Int(seconds / 60))"
                customDurationUnit = "分钟"
            } else if seconds < 86400 {
                customDurationValue = "\(Int(seconds / 3600))"
                customDurationUnit = "小时"
            } else {
                customDurationValue = "\(Int(seconds / 86400))"
                customDurationUnit = "天"
            }
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AT.text2(isDark))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? AT.accent : AT.control(isDark))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
                )
        }
        .buttonStyle(PressStyle())
    }

    private func applyCustomDuration() {
        guard let val = Double(customDurationValue), val > 0 else { return }
        let multiplier: TimeInterval
        switch customDurationUnit {
        case "分钟": multiplier = 60
        case "小时": multiplier = 3600
        case "天": multiplier = 86400
        case "月": multiplier = 30 * 86400
        default: multiplier = 60
        }
        customTargetDate = Date().addingTimeInterval(val * multiplier)
    }

    /// L4 头部与底部摘要共用的到期时刻文本
    private var dueSummaryText: String {
        let target: Date
        if selectedHorizon == .custom {
            target = customTargetDate
        } else if let interval = selectedHorizon.defaultTimeInterval {
            target = Date().addingTimeInterval(interval)
        } else {
            target = customTargetDate
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: target)
    }

    private var horizonSummaryText: String {
        switch selectedHorizon {
        case .min1: return "1 分钟"
        case .min5: return "5 分钟"
        case .min15: return "15 分钟"
        case .hour1: return "1 小时"
        case .hours4: return "4 小时"
        case .hours12: return "12 小时"
        case .hours24: return "24 小时"
        case .days3: return "3 天"
        case .days7: return "7 天"
        case .days30: return "30 天"
        case .longTerm: return "长期"
        case .custom: return "自定义"
        }
    }

    // MARK: - L5 来源归属（原型 .src-pills：档案胶囊 + 数字键 + 胜率）

    /// 星标优先、最近使用靠前的来源档案（最多展示 4 个）
    private var hudSourceProfiles: [SourceProfile] {
        let sorted = allProfiles
            .filter { !$0.isSelf }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
        return Array(sorted.prefix(4))
    }

    private var sourceLayer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                // 我自己的判断
                sourceSelfPill

                // 来源档案胶囊
                ForEach(Array(hudSourceProfiles.enumerated()), id: \.element.uuid) { index, profile in
                    sourceProfilePill(profile, keyIndex: index + 1)
                }

                // 新增来源
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isNewAuthorEditing.toggle()
                        if isNewAuthorEditing {
                            isSelfJudgment = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text("新增来源").font(.system(size: 11.5))
                    }
                    .foregroundColor(AT.text3(isDark))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(AT.cardBorder(isDark), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }

            // 新来源名称输入行
            if isNewAuthorEditing {
                HStack(spacing: 6) {
                    TextField("输入博主 / 机构名称，如 @PlanB、中金研报", text: $authorNameInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundColor(AT.text(isDark))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AT.control(isDark))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
                        .onSubmit {
                            isNewAuthorEditing = false
                            isSelfJudgment = false
                        }

                    Button("确认") {
                        isNewAuthorEditing = false
                        isSelfJudgment = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AT.accent)

                    Button("取消") {
                        isNewAuthorEditing = false
                        authorNameInput = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(AT.text2(isDark))
                }
            }
        }
    }

    private var sourceSelfPill: some View {
        let isSelected = isSelfJudgment
        return Button(action: {
            isSelfJudgment = true
            isNewAuthorEditing = false
        }) {
            HStack(spacing: 5) {
                Text("🧠").font(.system(size: 11))
                Text("我自己的判断").font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? AT.accent : AT.text(isDark))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? AT.accent.opacity(0.15) : AT.control(isDark))
            .overlay(
                Capsule().stroke(isSelected ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func sourceProfilePill(_ profile: SourceProfile, keyIndex: Int) -> some View {
        let isSelected = !isSelfJudgment && !isNewAuthorEditing
            && (authorNameInput == profile.name || profile.aliasNames.contains(authorNameInput))

        return Button(action: {
            isSelfJudgment = false
            isNewAuthorEditing = false
            authorNameInput = profile.name
        }) {
            HStack(spacing: 5) {
                Text("\(keyIndex)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : AT.text3(isDark))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isSelected ? AT.accent : AT.seg(isDark))
                    .cornerRadius(3)

                Text("\(profile.avatarEmoji) \(profile.name)")
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AT.accent : AT.text(isDark))
                    .lineLimit(1)

                Text(profile.totalPredictionsCount > 0
                     ? String(format: "%.0f%%", profile.winRate)
                     : "—")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? AT.accent : AT.text3(isDark))
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(isSelected ? AT.accent.opacity(0.15) : AT.control(isDark))
            .overlay(
                Capsule().stroke(isSelected ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - L6 Apple 生态协同（原型 .layer-eco：行内勾选框）

    private var appleSyncLayer: some View {
        // L6Header 已包含全部内容（标题 + 勾选框），这里保持空以维持 layer 容器
        EmptyView()
    }

    // MARK: - 底部操作栏（原型 .hud-foot）

    private var footerBar: some View {
        VStack(spacing: 6) {
            if let message = submitValidationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AT.warn)
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AT.warn)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AT.warn.opacity(0.1))
                .cornerRadius(5)
                .padding(.horizontal, 15)
            }

            HStack {
                // 时效摘要（原型 .foot-sum）
                HStack(spacing: 4) {
                    Text("时效")
                    Text(horizonSummaryText)
                        .fontWeight(.semibold)
                    Text("·")
                    Text("到期")
                    Text(dueSummaryText)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11))
                .foregroundColor(AT.text2(isDark))

                Spacer()

                Button(action: onDismiss) {
                    Text("取消")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AT.text2(isDark))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AT.seg(isDark))
                        .cornerRadius(8)
                }
                .buttonStyle(PressStyle())

                Button(action: submitEntry) {
                    HStack(spacing: 6) {
                        Text("存入对账账本")
                            .font(.system(size: 12.5, weight: .semibold))
                        KbdBadge(key: "⌘↩")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(AT.accent)
                    .cornerRadius(8)
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .background(AT.sidebarBg(isDark))
    }

    // MARK: - 逻辑处理与数据交互（保持原有行为）

    private func setupInitialState() {
        triggerQuoteFetch()
    }

    private func applyPresetMarket(_ market: String) {
        self.selectedMarketCategory = market
        if !tickerInput.isEmpty {
            triggerQuoteFetch()
        }
    }

    private func handleTickerChanged(_ newTicker: String) {
        tickerDebounceTask?.cancel()
        tickerDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled {
                triggerQuoteFetch()
            }
        }
    }

    private func triggerQuoteFetch() {
        let code = tickerInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        isFetchingQuote = true
        quoteErrorMessage = nil

        Task {
            do {
                let quote = try await MarketDataService.shared.fetchRealTimeQuote(
                    for: code,
                    preferredMarket: selectedMarketCategory
                )
                await MainActor.run {
                    self.entryPrice = quote.price
                    self.entryPriceInput = String(format: "%.2f", quote.price)
                    self.priceCurrency = quote.currency
                    self.tickerDisplayName = quote.displayName
                    self.selectedMarketCategory = quote.marketCategory
                    self.isFetchingQuote = false
                    self.isManuallyAdjustedPrice = false
                }
            } catch {
                await MainActor.run {
                    self.isFetchingQuote = false
                    self.quoteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handlePasteImage() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            if let img = NSImage(contentsOf: firstURL) {
                saveImageToSandbox(img)
                return
            }
        }

        if let imgData = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let img = NSImage(data: imgData) {
            saveImageToSandbox(img)
            return
        }

        if let image = NSImage(pasteboard: pb) {
            saveImageToSandbox(image)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var targetURL: URL? = nil
                if let url = item as? URL {
                    targetURL = url
                } else if let nsURL = item as? NSURL {
                    targetURL = nsURL as URL
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    targetURL = url
                }

                if let url = targetURL, let nsImage = NSImage(contentsOf: url) {
                    Task { @MainActor in
                        self.saveImageToSandbox(nsImage)
                    }
                }
            }
            return true
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                if let nsImage = image as? NSImage {
                    Task { @MainActor in
                        self.saveImageToSandbox(nsImage)
                    }
                }
            }
            return true
        }
        return false
    }

    private func saveImageToSandbox(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }

        let screenshotsDir = StorageManager.shared.screenshotsDirectoryURL
        try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

        let filename = "evidence_\(UUID().uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970)).png"
        let destURL = screenshotsDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: destURL)
            self.attachedImageRelativePath = "Screenshots/\(filename)"
            self.attachedImageFilename = filename
            self.attachedThumbnail = image
        } catch {
            print("Failed to save screenshot: \(error)")
        }
    }

    private func removeAttachment() {
        attachedThumbnail = nil
        attachedImageFilename = nil
        attachedImageRelativePath = nil
    }

    /// 保存并提交存证记录
    private func submitEntry() {
        let cleanTicker = tickerInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanSummary = factualSummaryInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // 复合校验：标的代码 或 「客观数据/现状观察」文字 至少要有一个非空
        guard !cleanTicker.isEmpty || !cleanSummary.isEmpty else {
            submitValidationMessage = "请至少填写「标的代码」，或在「客观数据/现状观察」中输入记录文字"
            return
        }
        submitValidationMessage = nil

        let isTickerEmpty = cleanTicker.isEmpty
        let finalTicker = isTickerEmpty ? "—" : cleanTicker
        let finalTickerName: String? = isTickerEmpty
            ? nil
            : (tickerDisplayName.isEmpty ? cleanTicker : tickerDisplayName)

        let entryType: EntryType
        let direction: PredictionDirection?
        if isTickerEmpty {
            entryType = .factualSnapshot
            direction = nil
        } else {
            entryType = (viewMode == .fact) ? .factualSnapshot : .prediction
            direction = (viewMode == .bullish) ? .bullish : ((viewMode == .bearish) ? .bearish : nil)
        }

        let targetPrice: Double? = (entryType == .prediction)
            ? Double(targetPriceInput.replacingOccurrences(of: ",", with: ""))
            : nil

        let targetDate: Date
        if selectedHorizon == .custom {
            targetDate = customTargetDate
        } else if let interval = selectedHorizon.defaultTimeInterval {
            targetDate = Date().addingTimeInterval(interval)
        } else {
            targetDate = customTargetDate
        }

        var matchedProfile: SourceProfile?
        if !isSelfJudgment {
            let author = authorNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !author.isEmpty {
                matchedProfile = allProfiles.first(where: { profile in
                    profile.name == author || profile.aliasNames.contains(author)
                })
                if matchedProfile == nil {
                    let newProfile = SourceProfile(name: author, platform: "社交网络/研报")
                    modelContext.insert(newProfile)
                    matchedProfile = newProfile
                }
                matchedProfile?.lastUsedAt = Date()
            }
        }

        let finalEntryPrice: Double = isTickerEmpty
            ? 0
            : (Double(entryPriceInput.replacingOccurrences(of: ",", with: "")) ?? entryPrice)

        let finalFactualSummary: String? = (entryType == .factualSnapshot) ? cleanSummary : nil

        let entry = PredictionEntry(
            ticker: finalTicker,
            tickerName: finalTickerName,
            marketCategory: selectedMarketCategory,
            entryType: entryType,
            direction: direction,
            factualSummary: finalFactualSummary,
            factualInference: factualInferenceDirection,
            entryPrice: finalEntryPrice,
            targetPrice: targetPrice,
            horizon: selectedHorizon,
            targetDate: targetDate,
            imageRelativePath: attachedImageRelativePath,
            isSelfJudgment: isSelfJudgment,
            authorName: isSelfJudgment ? "我自己的判断" : (authorNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "外部研报" : authorNameInput),
            sourceProfile: matchedProfile,
            syncToReminders: syncToReminders,
            syncToCalendar: syncToCalendar
        )

        modelContext.insert(entry)
        try? modelContext.save()

        let savedEntry = entry
        if syncToReminders || syncToCalendar {
            Task {
                if syncToReminders {
                    if let reminderId = try? await EventKitService.shared.syncPredictionReminder(for: savedEntry) {
                        savedEntry.remindersIdentifier = reminderId
                    }
                }
                if syncToCalendar {
                    if let eventId = try? await EventKitService.shared.syncPredictionCalendarEvent(for: savedEntry) {
                        savedEntry.calendarEventIdentifier = eventId
                    }
                }
                try? modelContext.save()
            }
        }

        onDismiss()
    }
}
