//
//  EventKitService.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import Foundation
import EventKit
import AppKit

// MARK: - EventKit 错误定义

enum EventKitError: LocalizedError, Sendable {
    case reminderPermissionDenied
    case calendarPermissionDenied
    case defaultSourceNotFound
    case failedToCreateList(String)
    case itemNotFound(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .reminderPermissionDenied:
            return "未能获得 Apple 提醒事项访问权限，请在 macOS「系统设置 -> 隐私与安全性 -> 提醒事项」中允许 AlphaTrack 访问。"
        case .calendarPermissionDenied:
            return "未能获得 Apple 日历访问权限，请在 macOS「系统设置 -> 隐私与安全性 -> 日历」中允许 AlphaTrack 访问。"
        case .defaultSourceNotFound:
            return "未能定位到可用的 iCloud / 本地提醒事项账户源。"
        case .failedToCreateList(let detail):
            return "创建「AlphaTrack 对账」专属清单失败: \(detail)"
        case .itemNotFound(let id):
            return "未在系统中检索到对应标识符的条目: \(id)"
        case .saveFailed(let detail):
            return "写入 Apple 系统生态时发生错误: \(detail)"
        }
    }
}

// MARK: - EventKitService (Swift 6 并发服务)

/// Apple 原生生态协同联动服务 (PRD 4.4)
/// 负责在官方【提醒事项】自动建立「AlphaTrack 对账」清单、计算各市场收盘精准时刻提醒、
/// 写入 deep link (alphatrack://entry/{id}) 以及系统日历日程协同
@MainActor
final class EventKitService: @unchecked Sendable {
    
    /// 全局单例
    static let shared = EventKitService()
    
    /// 系统事件库
    private let eventStore = EKEventStore()
    
    /// 提醒事项专属清单名称
    static let reminderListName: String = "AlphaTrack 对账"
    
    /// Deep link URL 协议 Scheme
    static let urlScheme: String = "alphatrack"
    
    private init() {}
    
    // MARK: - 权限请求 (兼容 macOS 14+ Sonoma 与旧版本)
    
    /// 请求提醒事项读写完整权限
    func requestRemindersAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    /// 请求系统日历读写完整权限
    func requestCalendarAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    // MARK: - 清单管理 (PRD 4.4 自动建立独立的「AlphaTrack 对账」清单)
    
    /// 获取或自动新建官方【提醒事项】中的「AlphaTrack 对账」清单
    func getOrCreateRemindersList() async throws -> EKCalendar {
        let hasAccess = try await requestRemindersAccess()
        guard hasAccess else {
            throw EventKitError.reminderPermissionDenied
        }
        
        let calendars = eventStore.calendars(for: .reminder)
        
        // 1. 查找是否已存在「AlphaTrack 对账」清单
        if let existing = calendars.first(where: { $0.title == Self.reminderListName }) {
            return existing
        }
        
        // 2. 不存在则创建新清单
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = Self.reminderListName
        
        // 优先挂载至 iCloud source，若无则使用默认/本地 source
        let sources = eventStore.sources
        let preferredSource = sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") })
            ?? eventStore.defaultCalendarForNewReminders()?.source
            ?? sources.first(where: { $0.sourceType == .local })
            ?? sources.first
        
        guard let validSource = preferredSource else {
            throw EventKitError.defaultSourceNotFound
        }
        
        newCalendar.source = validSource
        
        // 设置标志性品牌蓝色
        newCalendar.cgColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0).cgColor
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            throw EventKitError.failedToCreateList(error.localizedDescription)
        }
    }
    
    // MARK: - 提醒事项创建 (PRD 4.4 闭环待办与精准收盘时刻)
    
    /// 存证录入时，向「AlphaTrack 对账」清单同步创建带收盘时刻提醒与 Deep Link 的待办
    /// - Parameter entry: 已初始化的 PredictionEntry 实体
    /// - Returns: 生成的 Apple 提醒事项唯一标识符 (remindersIdentifier)
    @discardableResult
    func syncPredictionReminder(for entry: PredictionEntry) async throws -> String {
        let targetList = try await getOrCreateRemindersList()
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = targetList
        
        // 1. 标题设定
        if entry.entryType == .factualSnapshot {
            reminder.title = "【客观复盘】\(entry.authorName) · \(entry.ticker) 数据公布后走势回溯"
        } else {
            let dirText = entry.direction?.localizedTitle ?? "方向预测"
            let targetText = entry.targetPrice != nil ? "目标价 \(formatPrice(entry.targetPrice!))" : ""
            reminder.title = "【对账提醒】\(entry.authorName) · \(entry.ticker) \(dirText) \(targetText) 到期核验"
        }
        
        // 2. 深度链接设定 (alphatrack://entry/{id})
        let deepLinkString = "\(Self.urlScheme)://entry/\(entry.uuid.uuidString)"
        if let deepLinkURL = URL(string: deepLinkString) {
            reminder.url = deepLinkURL
        }
        
        // 3. 计算市场闭市精准触发时刻 (A股 15:00, 港股 16:00, 美股 04:00/05:00, Crypto 23:59)
        let triggerDate = calculateMarketClosingTime(for: entry.targetDate, marketCategory: entry.marketCategory)
        
        // 4. 设定到期时间与闹钟
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        reminder.dueDateComponents = components
        reminder.addAlarm(EKAlarm(absoluteDate: triggerDate))
        
        // 5. 详细备注说明 (在 iPhone / Watch 提醒卡片中提供富信息展示)
        reminder.notes = makeReminderNotes(for: entry, deepLink: deepLinkString, closingTime: triggerDate)
        
        // 6. 保存至 Apple Reminders
        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - 系统日历日程写入 (PRD 4.4 针对重磅事件/季度结算写入系统日历)
    
    /// 将预测或长线结算日写入苹果系统日历
    /// - Parameter entry: PredictionEntry 实体
    /// - Returns: 生成的日历日程唯一标识符 (calendarEventIdentifier)
    @discardableResult
    func syncPredictionCalendarEvent(for entry: PredictionEntry) async throws -> String {
        let hasAccess = try await requestCalendarAccess()
        guard hasAccess else {
            throw EventKitError.calendarPermissionDenied
        }
        
        guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            throw EventKitError.defaultSourceNotFound
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.calendar = defaultCalendar
        
        let triggerDate = calculateMarketClosingTime(for: entry.targetDate, marketCategory: entry.marketCategory)
        event.startDate = triggerDate
        event.endDate = triggerDate.addingTimeInterval(1800) // 30 分钟事件
        
        let dirText = entry.entryType == .factualSnapshot ? "客观数据观察" : (entry.direction?.localizedTitle ?? "预测结算")
        event.title = "【AlphaTrack】\(entry.ticker) (\(entry.authorName)) \(dirText) 结算对账"
        
        let deepLinkString = "\(Self.urlScheme)://entry/\(entry.uuid.uuidString)"
        if let deepLinkURL = URL(string: deepLinkString) {
            event.url = deepLinkURL
        }
        
        event.notes = makeReminderNotes(for: entry, deepLink: deepLinkString, closingTime: triggerDate)
        
        // 提前 15 分钟发出日历通知
        event.addAlarm(EKAlarm(relativeOffset: -900))
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            throw EventKitError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - 删除与注销
    
    /// 根据标识符移除已建立的提醒事项
    func removeReminder(identifier: String) async throws {
        guard try await requestRemindersAccess() else { return }
        if let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            try eventStore.remove(item, commit: true)
        }
    }
    
    /// 根据标识符移除已建立的日历日程
    func removeCalendarEvent(identifier: String) async throws {
        guard try await requestCalendarAccess() else { return }
        if let item = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(item, span: .thisEvent, commit: true)
        }
    }
    
    // MARK: - 市场收盘精准时刻计算 (PRD 4.4 精准触发时刻)
    
    /// 依据各主要金融市场的闭市时间规则，计算到期日当天的精准收盘时间
    /// - Parameters:
    ///   - targetDate: 设定到期验证日期
    ///   - marketCategory: 市场类型 ("A股", "港股", "美股", "Crypto", 或自定义)
    /// - Returns: 精确到秒的闭盘时间戳
    func calculateMarketClosingTime(for targetDate: Date, marketCategory: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        
        switch marketCategory {
        case "A股":
            // A股收盘时刻：北京时间 15:00:00 (UTC+8)
            if let shanghaiTZ = TimeZone(identifier: "Asia/Shanghai") {
                calendar.timeZone = shanghaiTZ
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 15
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps) ?? targetDate
            
        case "港股":
            // 港股收盘时刻：香港时间 16:00:00 (UTC+8)
            if let hkTZ = TimeZone(identifier: "Asia/Hong_Kong") {
                calendar.timeZone = hkTZ
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 16
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps) ?? targetDate
            
        case "美股":
            // 美股收盘时刻：美东时间 16:00:00 (EDT/EST)
            if let nyTZ = TimeZone(identifier: "America/New_York") {
                calendar.timeZone = nyTZ
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 16
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps) ?? targetDate
            
        case "Crypto":
            // 加密货币：全天候交易，默认取当天 23:59:00 或格林威治 00:00 日结
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 23
            comps.minute = 59
            comps.second = 0
            return calendar.date(from: comps) ?? targetDate
            
        default:
            // 默认取当天下午 15:00
            var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
            comps.hour = 15
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps) ?? targetDate
        }
    }
    
    // MARK: - 辅助内容拼装
    
    private func makeReminderNotes(for entry: PredictionEntry, deepLink: String, closingTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let closingStr = formatter.string(from: closingTime)
        
        var lines: [String] = []
        lines.append("【AlphaTrack 智能行情对账待办】")
        lines.append("• 标的代码: \(entry.ticker) (\(entry.tickerName ?? entry.ticker)) [\(entry.marketCategory)]")
        lines.append("• 观点来源: \(entry.authorName)")
        lines.append("• 入场基准价: ¥ \(entry.entryPrice)")
        
        if entry.entryType == .factualSnapshot {
            lines.append("• 记录类型: 客观数据 / 行业事实")
            if let fact = entry.factualSummary, !fact.isEmpty {
                lines.append("• 事实摘要: \(fact)")
            }
            if entry.factualInference != .none {
                lines.append("• 衍生推论: \(entry.factualInference.localizedTitle)")
            }
        } else {
            lines.append("• 预测方向: \(entry.direction?.localizedTitle ?? "未定")")
            if let target = entry.targetPrice {
                lines.append("• 目标点位: \(formatPrice(target)) (触及提前计为命中)")
            }
        }
        
        lines.append("• 收盘结算时刻: \(closingStr)")
        lines.append("")
        lines.append("👉 点击下方链接直达 Mac / iPhone 实盘对账卡片:")
        lines.append(deepLink)
        
        return lines.joined(separator: "\n")
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
