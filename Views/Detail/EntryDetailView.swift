//
//  EntryDetailView.swift
//  AlphaTrack
//
//  存证复盘详情页（原型 v4 5.6 Sheet：560×640）：
//  1. 头部：mono 标的 + 名称 + 状态徽章 + 元信息行
//  2. 价格 2×2 网格（基准价 / 结算价 / 目标价 / 结算时间）
//  3. 客观数据与后验反应（事实框 + 反应双卡 + 真实有效 / 数据失真打标胶囊）
//  4. 证据原图 + 手动结算 + 深度链接
//  5. 底部：删除（危险）/ 修改 / 完成
//
//  入口：深链 alphatrack://entry/{uuid} 与列表点击；手动结算兜底对账（PRD 4.2）。
//

import SwiftUI
import SwiftData
import AppKit

struct EntryDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var engine = ArbitrationEngine.shared

    let entry: PredictionEntry

    private var isDark: Bool { colorScheme == .dark }

    // MARK: 手动结算表单状态
    @State private var manualPriceText: String = ""
    @State private var manualDate: Date = Date()
    @State private var showManualForm: Bool = false

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    // MARK: - 编辑与删除状态
    @State private var isEditing: Bool = false
    @State private var showDeleteConfirm: Bool = false

    @State private var editTicker: String = ""
    @State private var editTickerName: String = ""
    @State private var editMarketCategory: String = "A股"
    @State private var editDirection: PredictionDirection = .bullish
    @State private var editEntryPrice: String = ""
    @State private var editTargetPrice: String = ""
    @State private var editAuthorName: String = ""
    @State private var editNotes: String = ""
    @State private var editHorizon: VerificationHorizon = .days30
    @State private var editTargetDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)

            ScrollView {
                if isEditing {
                    editFormSection
                        .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        priceGridSection
                        metadataSection
                        factualSection
                        evidenceSection
                        notesSection
                        actionSection
                        deepLinkSection
                    }
                    .padding(16)
                }
            }
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            footerSection
        }
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 560, minHeight: 640, idealHeight: 640, maxHeight: 640)
        .background(AT.windowBg(isDark))
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("⚠️ 谨慎删除提示", isPresented: $showDeleteConfirm) {
            Button("确认彻底删除", role: .destructive) {
                deleteEntry()
            }
            Button("取消", role: .cancel) { }
        } message: {
            let tickerDisplay = entry.ticker == "—" ? "客观数据存证" : entry.ticker
            Text("确认永久删除此条「\(tickerDisplay) - \(entry.authorName)」的存证判断吗？\n\n删除后将不可撤销与恢复！请谨慎确认。")
        }
    }

    // MARK: - 头部（原型 .sheet-head）
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Text(entry.ticker == "—" ? "📝" : entry.ticker)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(AT.text(isDark))

                if entry.ticker != "—", let name = entry.tickerName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundColor(AT.text2(isDark))
                }

                Spacer()

                // 状态徽章组
                HStack(spacing: 6) {
                    if entry.entryType == .factualSnapshot {
                        TagView(text: "📝 客观数据存证", style: .fact, dark: isDark)
                    }
                    if entry.isSettled {
                        TagView(text: "已结算", style: .winHi, dark: isDark)
                    } else {
                        TagView(text: badgeText, style: badgeStyle, dark: isDark)
                    }
                }
            }

            // 元信息行（原型 .sheet-sub）
            HStack(spacing: 6) {
                Text(entry.marketCategory)
                Text("·")
                Text(entry.authorName)
                Text("·")
                Text("周期 \(entry.horizon.rawValue)")
                Text("·")
                Text("创建 \(dateText(entry.createdAt))")
            }
            .font(.system(size: 11))
            .foregroundColor(AT.text3(isDark))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var badgeText: String {
        if entry.entryType == .factualSnapshot {
            return entry.factCheckStatus.rawValue
        }
        return entry.arbitrationStatus.rawValue
    }

    private var badgeStyle: TagView.Style {
        if entry.entryType == .factualSnapshot {
            switch entry.factCheckStatus {
            case .unverified: return .neutral
            case .verifiedValid: return .winHi
            case .falsified: return .bear
            }
        }
        switch entry.arbitrationStatus {
        case .pending: return .warn
        case .hitEarly, .hit: return .winHi
        case .miss: return .bear
        case .expired: return .neutral
        }
    }

    // MARK: - 价格网格（原型 .price-grid / .price-cell）

    private var priceGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            priceCell(
                title: "入场基准价",
                value: entry.entryPrice > 0 ? format(entry.entryPrice) : "—",
                chg: nil
            )
            priceCell(
                title: "结算价",
                value: optionalPriceText(entry.settlementPrice),
                chg: settlementChg
            )
            priceCell(
                title: "目标价",
                value: optionalPriceText(entry.targetPrice),
                chg: nil,
                muted: entry.targetPrice == nil
            )
            priceCell(
                title: "结算时间",
                value: entry.settlementDate != nil ? dateText(entry.settlementDate) : "--",
                chg: nil,
                small: true
            )
        }
    }

    private var settlementChg: Double? {
        guard let settle = entry.settlementPrice, entry.entryPrice > 0 else { return nil }
        return (settle - entry.entryPrice) / entry.entryPrice * 100.0
    }

    private func priceCell(title: String, value: String, chg: Double?, muted: Bool = false, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: small ? 13 : 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(muted ? AT.text3(isDark) : AT.text(isDark))
                if let c = chg {
                    Text(String(format: "%+.2f%%", c))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.riseFall(c, isDark))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AT.cardBg(isDark))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AT.cardBorder(isDark), lineWidth: 1))
    }

    // MARK: - 存证信息

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("存证信息")
            infoRow("记录类型", entry.entryType.localizedTitle)
            if entry.entryType == .prediction {
                infoRow("预测方向", entry.direction?.localizedTitle ?? "--")
            }
            infoRow("录入时间", dateText(entry.createdAt))
            infoRow("到期时间", "\(dateText(entry.targetDate))（\(remainingText)）")
            infoRow("来源归属", entry.isSelfJudgment ? "我自己的判断" : entry.authorName)
            if entry.syncToReminders || entry.syncToCalendar {
                infoRow("生态同步", syncText)
            }
        }
    }

    private var syncText: String {
        var parts: [String] = []
        if entry.syncToReminders { parts.append("提醒事项") }
        if entry.syncToCalendar { parts.append("系统日历") }
        return parts.joined(separator: " / ")
    }

    private var remainingText: String {
        guard !entry.isSettled else { return "已结算" }
        let seconds = entry.timeRemaining
        if seconds <= 0 { return "已到期，等待对账" }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "剩 \(days) 天 \(hours) 小时" }
        return "剩 \(hours) 小时"
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(AT.text2(isDark))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 客观数据与后验反应（原型 .fact-box / .react-row / .mark-row）

    private var factualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("客观数据与后验反应")

            // 事实框
            if let summary = entry.factualSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(AT.text2(isDark))
                    .lineSpacing(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AT.seg(isDark))
                    .cornerRadius(10)
            } else {
                Text("（本条为方向性预测，无客观数据摘要）")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text3(isDark))
            }

            // 衍生推论 tag
            HStack(spacing: 6) {
                switch entry.factualInference {
                case .bullish:
                    TagView(text: "▲ 衍生看多", style: .bull, dark: isDark)
                case .bearish:
                    TagView(text: "▼ 衍生看空", style: .bear, dark: isDark)
                case .none:
                    TagView(text: "纯客观记录", style: .neutral, dark: isDark)
                }
                if entry.entryType == .factualSnapshot {
                    TagView(text: "不参与胜率统计", style: .neutral, dark: isDark)
                }
            }

            // 后验反应双卡（原型 .react-row）
            HStack(spacing: 8) {
                reactCard(title: "到期真实市场反应", value: reactionText, color: reactionColor)
                reactCard(title: "区间年化波动率", value: volatilityText, color: AT.text(isDark))
            }

            // 打标胶囊（原型 .mark-row）
            if entry.entryType == .factualSnapshot {
                HStack(spacing: 7) {
                    markPill(
                        title: "✓ 标记为 真实有效",
                        isSelected: entry.factCheckStatus == .verifiedValid,
                        color: AT.winHi(isDark)
                    ) {
                        tagFact(entry.factCheckStatus == .verifiedValid ? .unverified : .verifiedValid)
                    }

                    markPill(
                        title: "✕ 标记为 数据失真",
                        isSelected: entry.factCheckStatus == .falsified,
                        color: AT.winLo(isDark)
                    ) {
                        tagFact(entry.factCheckStatus == .falsified ? .unverified : .falsified)
                    }
                }
            }
        }
    }

    private var reactionText: String {
        guard let pct = entry.marketReactionPercent else { return "未计算" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    private var reactionColor: Color {
        guard let pct = entry.marketReactionPercent else { return AT.text3(isDark) }
        return AT.riseFall(pct, isDark)
    }

    private var volatilityText: String {
        guard let vol = entry.marketReactionVolatility else { return "未计算" }
        return "\(String(format: "%.2f", vol))%"
    }

    private func reactCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AT.cardBg(isDark))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AT.cardBorder(isDark), lineWidth: 1))
    }

    /// 原型 .mark：选中态 15% 色底 + 描边
    private func markPill(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(isSelected ? color : AT.text2(isDark))
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(isSelected ? color.opacity(0.15) : AT.control(isDark))
                .overlay(
                    Capsule().stroke(isSelected ? color : AT.cardBorder(isDark), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - 证据原图

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("证据原图")
            if let image = loadedEvidenceImage {
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AT.cardBorder(isDark), lineWidth: 1)
                        )

                    if let url = entry.fullImageURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AT.text3(isDark))
                    }
                }
            } else {
                Text("无附件")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text3(isDark))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(AT.seg(isDark))
                    .cornerRadius(10)
            }
        }
    }

    private var loadedEvidenceImage: NSImage? {
        guard let url = entry.fullImageURL else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - 备注

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("备注 / 逻辑")
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(AT.text2(isDark))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("无")
                    .font(.system(size: 12))
                    .foregroundColor(AT.text3(isDark))
            }
        }
    }

    // MARK: - 对账操作（原型 .manual 三列）

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("对账操作")

            if entry.isSettled {
                Text("本条已结算。如需重新判定，可再次手动填入结算价覆盖。")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 手动结算价
                VStack(alignment: .leading, spacing: 4) {
                    Text("手动结算价")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AT.text3(isDark))
                    TextField("例如 1680.50", text: $manualPriceText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AT.text(isDark))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(AT.control(isDark))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
                }
                .frame(maxWidth: .infinity)

                // 结算日期
                VStack(alignment: .leading, spacing: 4) {
                    Text("结算日期")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AT.text3(isDark))
                    DatePicker("", selection: $manualDate, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(height: 30)
                }
                .frame(maxWidth: .infinity)

                Button(action: { submitManualSettlement() }) {
                    Text("覆盖结算")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AT.text2(isDark))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AT.seg(isDark))
                        .cornerRadius(8)
                }
                .buttonStyle(PressStyle())
                .disabled(manualPriceText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text(manualHintText)
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))

            Button(action: { runAutoArbitration() }) {
                Text("立即自动对账")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AT.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(AT.accent.opacity(0.10))
                    .cornerRadius(8)
            }
            .buttonStyle(PressStyle())
        }
    }

    private var manualHintText: String {
        if entry.entryType == .factualSnapshot {
            return "客观数据记录：填入市价后将计算市场后验涨跌幅，不产生胜负判定。"
        }
        if entry.targetPrice != nil {
            return "方向预测：按结算价是否达成目标价判定命中 / 未命中。"
        }
        return "方向预测：按结算价相对基准价的涨跌方向判定命中 / 未命中。"
    }

    // MARK: - 深度链接（原型 .deeplink）

    private var deepLinkText: String {
        "alphatrack://entry/\(entry.uuid.uuidString)"
    }

    private var deepLinkSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            blockTitle("深度链接")
            HStack(spacing: 7) {
                Text(deepLinkText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AT.text2(isDark))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { copyDeepLink() }) {
                    Text("复制链接")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AT.accent)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AT.control(isDark))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
        }
    }

    // MARK: - 底部（原型 .sheet-foot：删除 / 修改 / 完成）

    private var footerSection: some View {
        HStack(spacing: 8) {
            // 危险删除（原型 .btn-danger）
            Button {
                showDeleteConfirm = true
            } label: {
                Text("删除")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(AT.bear(isDark))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AT.bear(isDark).opacity(0.42), lineWidth: 1)
                    )
                    .cornerRadius(8)
            }
            .buttonStyle(PressStyle())

            Spacer()

            if !isEditing {
                Button {
                    startEditing()
                } label: {
                    Text("修改")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AT.text2(isDark))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AT.seg(isDark))
                        .cornerRadius(8)
                }
                .buttonStyle(PressStyle())
            }

            Button {
                if isEditing {
                    isEditing = false
                } else {
                    dismiss()
                }
            } label: {
                Text(isEditing ? "取消编辑" : "完成")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(AT.accent)
                    .cornerRadius(8)
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(AT.sidebarBg(isDark))
    }

    // MARK: - 编辑表单（保留全部编辑能力，样式按 token 统一）

    private var editFormSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("✏️ 修改存证记录")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AT.text(isDark))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标的代码与名称")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                HStack(spacing: 8) {
                    TextField("代码 (如 600519)", text: $editTicker)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("友好名称 (如 贵州茅台)", text: $editTickerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("行情分类与多空方向")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                HStack(spacing: 12) {
                    Picker("分类", selection: $editMarketCategory) {
                        Text("A股").tag("A股")
                        Text("美股").tag("美股")
                        Text("港股").tag("港股")
                        Text("Crypto").tag("Crypto")
                        Text("黄金与大宗商品").tag("黄金与大宗商品")
                    }
                    .frame(width: 180)

                    Picker("方向", selection: $editDirection) {
                        Text("▲ 看多").tag(PredictionDirection.bullish)
                        Text("▼ 看空").tag(PredictionDirection.bearish)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("点位设置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("基准价:")
                            .font(.system(size: 11))
                            .foregroundColor(AT.text3(isDark))
                        TextField("基准价", text: $editEntryPrice)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 4) {
                        Text("目标价:")
                            .font(.system(size: 11))
                            .foregroundColor(AT.text3(isDark))
                        TextField("选填", text: $editTargetPrice)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("来源发言人归属")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                TextField("来源博主或填「我自己的判断」", text: $editAuthorName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("验证时效周期")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                ScrollView(.horizontal, showsIndicators: false) {
                    Picker("", selection: $editHorizon) {
                        ForEach(VerificationHorizon.allCases, id: \.self) { h in
                            Text(h.rawValue).tag(h)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .onChange(of: editHorizon) { _, newHorizon in
                    if newHorizon != .custom, let interval = newHorizon.defaultTimeInterval {
                        editTargetDate = entry.createdAt.addingTimeInterval(interval)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("到期时间")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                if entry.isSettled {
                    HStack(spacing: 8) {
                        Text(editTargetDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AT.seg(isDark))
                            .cornerRadius(6)
                        Text("（已结算，到期时间锁定）")
                            .font(.system(size: 10))
                            .foregroundColor(AT.text3(isDark))
                    }
                } else {
                    DatePicker(
                        "",
                        selection: $editTargetDate,
                        in: entry.createdAt...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: editTargetDate) { _, newDate in
                        if editHorizon != .custom {
                            let implied = newDate.timeIntervalSince(entry.createdAt)
                            if let expected = editHorizon.defaultTimeInterval,
                               abs(implied - expected) > 60 {
                                editHorizon = .custom
                            }
                        }
                    }
                    Text("修改具体日期后，时效周期会自动切到「自定义」")
                        .font(.system(size: 10))
                        .foregroundColor(AT.text3(isDark))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("详细备注 / 逻辑论据")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AT.text3(isDark))
                TextEditor(text: $editNotes)
                    .font(.system(size: 12))
                    .frame(height: 80)
                    .padding(4)
                    .background(AT.control(isDark))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button("保存修改") {
                    saveEdits()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("取消") {
                    isEditing = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 编辑与删除行为

    private func startEditing() {
        editTicker = entry.ticker
        editTickerName = entry.tickerName ?? ""
        editMarketCategory = entry.marketCategory
        editDirection = entry.direction ?? .bullish
        editEntryPrice = String(format: "%.2f", entry.entryPrice)
        editTargetPrice = entry.targetPrice != nil ? String(format: "%.2f", entry.targetPrice!) : ""
        editAuthorName = entry.isSelfJudgment ? "我自己的判断" : entry.authorName
        editNotes = entry.notes ?? ""
        editHorizon = entry.horizon
        editTargetDate = entry.targetDate
        isEditing = true
    }

    private func saveEdits() {
        let cleanTicker = editTicker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty || entry.entryType == .factualSnapshot else {
            notify(title: "保存失败", message: "方向性预测记录的标的代码不能为空。")
            return
        }
        entry.ticker = cleanTicker.isEmpty ? "—" : cleanTicker
        let cleanName = editTickerName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.tickerName = cleanName.isEmpty ? nil : cleanName
        entry.marketCategory = editMarketCategory
        entry.direction = editDirection
        if let ep = Double(editEntryPrice.replacingOccurrences(of: ",", with: "")) {
            entry.entryPrice = ep
        }
        if let tp = Double(editTargetPrice.replacingOccurrences(of: ",", with: "")) {
            entry.targetPrice = tp
        } else if editTargetPrice.trimmingCharacters(in: .whitespaces).isEmpty {
            entry.targetPrice = nil
        }
        let cleanAuthor = editAuthorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAuthor == "我自己的判断" || cleanAuthor.isEmpty {
            entry.isSelfJudgment = true
            entry.authorName = "我自己的判断"
        } else {
            entry.isSelfJudgment = false
            entry.authorName = cleanAuthor
        }
        let cleanNotes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.notes = cleanNotes.isEmpty ? nil : cleanNotes
        entry.horizon = editHorizon
        if !entry.isSettled {
            entry.targetDate = editTargetDate
        }
        entry.updatedAt = Date()

        do {
            try modelContext.save()
            isEditing = false
            notify(title: "修改成功", message: "存证判断已成功更新并保存。")
        } catch {
            notify(title: "保存失败", message: error.localizedDescription)
        }
    }

    private func deleteEntry() {
        modelContext.delete(entry)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            notify(title: "删除失败", message: error.localizedDescription)
        }
    }

    // MARK: - 行为

    private func tagFact(_ status: FactCheckStatus) {
        entry.factCheckStatus = status
        entry.updatedAt = Date()
        try? modelContext.save()
        notify(title: "已打标", message: "事实有效性标记为「\(status.rawValue)」。")
    }

    private func submitManualSettlement() {
        let trimmed = manualPriceText.trimmingCharacters(in: .whitespaces)
        guard let price = Double(trimmed), price > 0 else {
            notify(title: "无法结算", message: "请输入大于 0 的结算价格。")
            return
        }
        do {
            let status = try ArbitrationEngine.shared.manuallySettle(
                entryID: entry.uuid,
                price: price,
                date: manualDate
            )
            manualPriceText = ""
            showManualForm = false
            if let status {
                notify(title: "手动结算完成", message: "判定结果：\(status.rawValue)，结算价 \(format(price))。")
            } else {
                notify(title: "已记录", message: "市场后验反应已按结算价 \(format(price)) 计算完成。")
            }
        } catch {
            notify(title: "结算失败", message: error.localizedDescription)
        }
    }

    private func runAutoArbitration() {
        Task {
            await ArbitrationEngine.shared.runArbitration()
            await MainActor.run {
                let report = ArbitrationEngine.shared.lastReport?.summary ?? "无待对账记录"
                let failure = ArbitrationEngine.shared.lastError
                notify(
                    title: "对账完成",
                    message: failure == nil ? report : "\(report)\n注意：\(failure!)"
                )
            }
        }
    }

    private func copyDeepLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(deepLinkText, forType: .string)
        notify(title: "已复制", message: "深链接已复制到剪贴板，可粘贴到提醒事项备注中。")
    }

    private func notify(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: - 工具

    private func blockTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AT.text2(isDark))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func optionalPriceText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return format(value)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

#Preview {
    EntryDetailView(entry: PredictionEntry(
        ticker: "600519",
        tickerName: "贵州茅台",
        entryPrice: 1680.0,
        targetPrice: 1750.0,
        authorName: "示例来源"
    ))
    .modelContainer(for: [PredictionEntry.self, SourceProfile.self], inMemory: true)
}
