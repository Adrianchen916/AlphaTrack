//
//  EntryLedgerView.swift
//  AlphaTrack
//
//  存证流水窗口：单条记录的检索与复盘入口（样式按原型 v4 token 统一）。
//  看板只呈现 KOL 聚合卡片，自定义行情分类（外汇、期货）与长期停牌标的
//  需要一个能直接触达单条记录、手动填入结算价完成对账的界面（PRD 4.2）。
//

import SwiftUI
import SwiftData

struct EntryLedgerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \PredictionEntry.createdAt, order: .reverse)
    private var entries: [PredictionEntry]

    @State private var filter: LedgerFilter = .pending
    @State private var searchText: String = ""
    @State private var detailEntry: PredictionEntry?

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Rectangle().fill(AT.sep(isDark)).frame(height: 1)
            listContent
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(AT.windowBg(isDark))
        .sheet(item: $detailEntry) { entry in
            EntryDetailView(entry: entry)
        }
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(LedgerFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            TextField("搜索标的 / 来源", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Spacer()

            Text("共 \(filteredEntries.count) 条")
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
        }
        .padding(12)
    }

    // MARK: - 列表

    private var listContent: some View {
        Group {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            LedgerRow(entry: entry, isDark: isDark)
                                .contentShape(Rectangle())
                                .onTapGesture { detailEntry = entry }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundColor(AT.text3(isDark))
            Text(emptyHint)
                .font(.system(size: 12))
                .foregroundColor(AT.text2(isDark))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: String {
        if searchText.isEmpty {
            return "该筛选条件下暂无存证记录"
        }
        return "没有匹配「\(searchText)」的存证记录"
    }

    // MARK: - 数据

    private var filteredEntries: [PredictionEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        return entries.filter { entry in
            if !filter.matches(entry) { return false }
            guard !keyword.isEmpty else { return true }
            return entry.ticker.lowercased().contains(keyword)
                || entry.authorName.lowercased().contains(keyword)
                || (entry.tickerName ?? "").lowercased().contains(keyword)
        }
    }

    enum LedgerFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case pending = "进行中"
        case settled = "已结算"

        var id: String { rawValue }

        func matches(_ entry: PredictionEntry) -> Bool {
            switch self {
            case .all:     return true
            case .pending: return !entry.arbitrationStatus.isSettled
            case .settled: return entry.arbitrationStatus.isSettled
            }
        }
    }
}

// MARK: - 单行

private struct LedgerRow: View {
    let entry: PredictionEntry
    let isDark: Bool

    /// 是否为「无标的的纯事实存证」(ticker 占位符"—")
    private var isFactualWithoutTicker: Bool {
        entry.ticker == "—"
    }

    private var entryPriceText: String {
        entry.entryPrice > 0 ? LedgerRow.price(entry.entryPrice) : "—"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isFactualWithoutTicker {
                        Text("📝")
                            .font(.system(size: 11))
                    } else if entry.entryType == .factualSnapshot {
                        Text("▬")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AT.accent)
                    } else {
                        Text(entry.direction?.symbol ?? "•")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(entry.direction == .bearish ? AT.bear(isDark) : AT.bull(isDark))
                    }

                    if isFactualWithoutTicker {
                        Text("客观数据存证")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AT.text2(isDark))
                    } else {
                        Text(entry.ticker)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(AT.text(isDark))
                    }

                    if !isFactualWithoutTicker, let name = entry.tickerName, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundColor(AT.text3(isDark))
                    }
                }
                Text("\(entry.marketCategory) · \(entry.authorName) · \(entry.horizon.rawValue)")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
            }
            .frame(width: 260, alignment: .leading)

            Text(entryPriceText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isFactualWithoutTicker ? AT.text3(isDark) : AT.text(isDark))
                .frame(width: 90, alignment: .trailing)

            Text(LedgerRow.optionalPrice(entry.targetPrice))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AT.text2(isDark))
                .frame(width: 90, alignment: .trailing)

            Text(LedgerRow.optionalPrice(entry.settlementPrice))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AT.text(isDark))
                .frame(width: 90, alignment: .trailing)

            statusChip
                .frame(width: 90, alignment: .center)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(AT.text3(isDark))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AT.cardBg(isDark))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AT.cardBorder(isDark), lineWidth: 1))
    }

    private var statusChip: some View {
        Group {
            if entry.entryType == .factualSnapshot {
                switch entry.factCheckStatus {
                case .unverified:
                    TagView(text: entry.factCheckStatus.rawValue, style: .neutral, dark: isDark)
                case .verifiedValid:
                    TagView(text: entry.factCheckStatus.rawValue, style: .winHi, dark: isDark)
                case .falsified:
                    TagView(text: entry.factCheckStatus.rawValue, style: .bear, dark: isDark)
                }
            } else {
                switch entry.arbitrationStatus {
                case .pending:
                    TagView(text: entry.arbitrationStatus.rawValue, style: .warn, dark: isDark)
                case .hitEarly, .hit:
                    TagView(text: entry.arbitrationStatus.rawValue, style: .winHi, dark: isDark)
                case .miss:
                    TagView(text: entry.arbitrationStatus.rawValue, style: .bear, dark: isDark)
                case .expired:
                    TagView(text: entry.arbitrationStatus.rawValue, style: .neutral, dark: isDark)
                }
            }
        }
    }

    private static func price(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func optionalPrice(_ value: Double?) -> String {
        guard let value else { return "--" }
        return price(value)
    }
}

#Preview {
    EntryLedgerView()
        .modelContainer(for: [PredictionEntry.self, SourceProfile.self], inMemory: true)
}
