//
//  MarketDataService.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import Foundation

// MARK: - 行情数据传输模型 (DTOs)

/// 实时行情报价数据
struct MarketQuote: Sendable, Codable, Equatable {
    /// 标准化代码 (如 600519, NVDA, BTC/USDT)
    let ticker: String
    /// 标的展示名称 (如 "贵州茅台", "英伟达", "比特币")
    let displayName: String
    /// 当前最新市价 (基准入场价)
    let price: Double
    /// 今日涨跌额
    let change: Double?
    /// 今日涨跌幅百分比 (如 2.35 表示 +2.35%)
    let changePercent: Double?
    /// 所属行情分类 (如 "A股", "美股", "港股", "Crypto")
    let marketCategory: String
    /// 货币单位 (如 "CNY", "USD", "HKD", "USDT")
    let currency: String
    /// 行情更新时间
    let timestamp: Date
    
    init(
        ticker: String,
        displayName: String,
        price: Double,
        change: Double? = nil,
        changePercent: Double? = nil,
        marketCategory: String,
        currency: String = "CNY",
        timestamp: Date = Date()
    ) {
        self.ticker = ticker
        self.displayName = displayName
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.marketCategory = marketCategory
        self.currency = currency
        self.timestamp = timestamp
    }
}

/// 历史对账与收盘价格数据
struct HistoricalQuote: Sendable, Codable, Equatable {
    /// 标的代码
    let ticker: String
    /// 对应交易日日期
    let date: Date
    /// 当日收盘价格 (用于到期判定)
    let closePrice: Double
    /// 当日盘中最高价 (用于提前触达看多目标价判定)
    let highPrice: Double?
    /// 当日盘中最低价 (用于提前触达看空目标价判定)
    let lowPrice: Double?
    /// 行情分类
    let marketCategory: String
    
    init(
        ticker: String,
        date: Date,
        closePrice: Double,
        highPrice: Double? = nil,
        lowPrice: Double? = nil,
        marketCategory: String
    ) {
        self.ticker = ticker
        self.date = date
        self.closePrice = closePrice
        self.highPrice = highPrice
        self.lowPrice = lowPrice
        self.marketCategory = marketCategory
    }
}

/// 标的代码分流路由结果
enum MarketRoute: Sendable, Equatable {
    /// A股 (代码如 600519, 市场前缀如 "sh", "sz", "bj")
    case aShare(code: String, prefix: String)
    /// 港股 (代码如 "00700")
    case hkStock(code: String)
    /// 美股 (代码如 "NVDA", "AAPL")
    case usStock(symbol: String)
    /// 加密货币 (交易对如 "BTCUSDT")
    case crypto(symbol: String)
    /// 大宗商品 / 贵金属 (黄金 XAU、白银 XAG、原油 CL 等)
    case commodity(symbol: String, mappedTicker: String, name: String)
    /// 外汇货币对 (EURUSD, USDJPY 等)
    case forex(pair: String, mappedTicker: String)
    /// 自定义 / 未知格式
    case custom(rawTicker: String)
    
    /// 规范化分类名称
    var categoryName: String {
        switch self {
        case .aShare: return "A股"
        case .hkStock: return "港股"
        case .usStock: return "美股"
        case .crypto: return "Crypto"
        case .commodity: return "黄金与大宗商品"
        case .forex: return "外汇"
        case .custom: return "自定义"
        }
    }
}

/// 行情服务错误定义
enum MarketDataError: LocalizedError, Sendable {
    case invalidTicker(String)
    case unsupportedMarket(String)
    case networkError(String)
    case parsingError(String)
    case noHistoricalData(ticker: String, date: Date)
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .invalidTicker(let ticker):
            return "无效的标的代码格式: \(ticker)"
        case .unsupportedMarket(let market):
            return "当前暂不支持该市场接口: \(market)"
        case .networkError(let message):
            return "行情网络通信异常: \(message)"
        case .parsingError(let detail):
            return "行情数据解析失败: \(detail)"
        case .noHistoricalData(let ticker, let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return "未能获取到标的 \(ticker) 在 \(formatter.string(from: date)) 的有效交易日收盘数据"
        case .rateLimitExceeded:
            return "行情请求频次过高，请稍后重试"
        }
    }
}

// MARK: - MarketDataService (Swift 6 并发服务)

/// 原生轻量化多市场行情获取服务 (PRD 3.1 & 4.1 & 4.2)
/// 支持 A股(腾讯行情零延时)、港股、美股(Yahoo Finance)、加密货币(Binance Public API)
@MainActor
final class MarketDataService: @unchecked Sendable {
    
    /// 全局单例
    static let shared = MarketDataService()
    
    /// 自定义 URLSession 配置
    private let session: URLSession
    
    /// 内存实时报价缓存 (Ticker -> (Quote, CacheTime))，防止 HUD 输入时高频抖动请求
    private var quoteCache: [String: (quote: MarketQuote, timestamp: Date)] = [:]
    /// 缓存有效期 (5 秒)
    private let cacheDuration: TimeInterval = 5.0
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10.0
        configuration.timeoutIntervalForResource = 15.0
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "Accept": "*/*"
        ]
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - 核心对外 API
    
    /// 1. 获取标的当前实时基准价格与元数据 (PRD 4.1 入场市价自动抓取)
    /// - Parameters:
    ///   - ticker: 标的代码 (如 600519, NVDA, BTC/USDT, 0700.HK)
    ///   - preferredMarket: 用户手动指定的市场（可选，若为空则依据代码规则自动分流）
    /// - Returns: 统一规范的 MarketQuote 报价结构体
    func fetchRealTimeQuote(for ticker: String, preferredMarket: String? = nil) async throws -> MarketQuote {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else {
            throw MarketDataError.invalidTicker(ticker)
        }
        
        let route = detectRoute(for: cleanTicker, preferredMarket: preferredMarket)
        let cacheKey = "\(route.categoryName):\(cleanTicker)"
        
        // 检查内存有效缓存
        if let cached = quoteCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.quote
        }
        
        let quote: MarketQuote
        switch route {
        case .aShare(let code, let prefix):
            quote = try await fetchAShareQuote(code: code, prefix: prefix)
        case .hkStock(let code):
            quote = try await fetchHKStockQuote(code: code)
        case .usStock(let symbol):
            quote = try await fetchUSStockQuote(symbol: symbol)
        case .crypto(let symbol):
            quote = try await fetchCryptoQuote(symbol: symbol)
        case .commodity(let symbol, let mappedTicker, let name):
            quote = try await fetchCommodityQuote(symbol: symbol, mappedTicker: mappedTicker, defaultName: name)
        case .forex(let pair, let mappedTicker):
            quote = try await fetchForexQuote(pair: pair, mappedTicker: mappedTicker)
        case .custom:
            throw MarketDataError.unsupportedMarket("自定义代码需手动填入基准价")
        }
        
        // 写入缓存
        quoteCache[cacheKey] = (quote, Date())
        return quote
    }
    
    /// 2. 获取标的到期日收盘价格 (PRD 4.2 自动对账验真)
    /// - Parameters:
    ///   - ticker: 标的代码
    ///   - date: 到期验证日期 (遇周末/节假日自动向前或向后对齐最接近的真实交易日)
    ///   - preferredMarket: 指定市场分类
    /// - Returns: 包含收盘价、盘中高低价的历史数据
    func fetchHistoricalClose(for ticker: String, on date: Date, preferredMarket: String? = nil) async throws -> HistoricalQuote {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else {
            throw MarketDataError.invalidTicker(ticker)
        }
        
        let route = detectRoute(for: cleanTicker, preferredMarket: preferredMarket)
        switch route {
        case .aShare(let code, let prefix):
            return try await fetchAShareHistorical(code: code, prefix: prefix, on: date)
        case .hkStock(let code):
            return try await fetchHKStockHistorical(code: code, on: date)
        case .usStock(let symbol):
            return try await fetchUSStockHistorical(symbol: symbol, on: date)
        case .crypto(let symbol):
            return try await fetchCryptoHistorical(symbol: symbol, on: date)
        case .commodity(_, let mappedTicker, _):
            return try await fetchUSStockHistorical(symbol: mappedTicker, on: date, overrideCategory: "黄金与大宗商品")
        case .forex(_, let mappedTicker):
            return try await fetchUSStockHistorical(symbol: mappedTicker, on: date, overrideCategory: "外汇")
        case .custom:
            throw MarketDataError.unsupportedMarket("自定义代码需手动对账结算")
        }
    }
    
    /// 2.5 获取指定区间内的日 K 序列 (PRD 4.2 提前命中逐日扫描)
    /// - Parameters:
    ///   - ticker: 标的代码
    ///   - startDate: 区间起始日（含）
    ///   - endDate: 区间结束日（含）
    ///   - preferredMarket: 指定市场分类
    /// - Returns: 按日期升序排列的日 K 序列；区间内无交易日时返回空数组
    func fetchDailyRange(for ticker: String, from startDate: Date, to endDate: Date, preferredMarket: String? = nil) async throws -> [HistoricalQuote] {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else {
            throw MarketDataError.invalidTicker(ticker)
        }
        
        let route = detectRoute(for: cleanTicker, preferredMarket: preferredMarket)
        let candles: [HistoricalQuote]
        switch route {
        case .aShare(let code, let prefix):
            candles = try await fetchAShareDailyCandles(code: code, prefix: prefix)
        case .hkStock(let code):
            candles = try await fetchYahooDailyCandles(symbol: "\(code).HK", category: "港股", from: startDate, to: endDate)
        case .usStock(let symbol):
            candles = try await fetchYahooDailyCandles(symbol: symbol, category: "美股", from: startDate, to: endDate)
        case .crypto(let symbol):
            candles = try await fetchCryptoDailyCandles(symbol: symbol)
        case .commodity(_, let mappedTicker, _):
            candles = try await fetchYahooDailyCandles(symbol: mappedTicker, category: "黄金与大宗商品", from: startDate, to: endDate)
        case .forex(_, let mappedTicker):
            candles = try await fetchYahooDailyCandles(symbol: mappedTicker, category: "外汇", from: startDate, to: endDate)
        case .custom:
            throw MarketDataError.unsupportedMarket("自定义代码需手动对账结算")
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let startDay = calendar.startOfDay(for: startDate)
        // 结束日放宽到当日 23:59，覆盖收盘时刻落在当天的情况
        let endDay = calendar.startOfDay(for: endDate).addingTimeInterval(86399)
        
        return candles
            .filter { $0.date >= startDay && $0.date <= endDay }
            .sorted { $0.date < $1.date }
    }
    
    /// 3. 批量并发获取多个标的实时报价 (利用 Swift 6 async let / TaskGroup)
    func batchFetchQuotes(for tickers: [String]) async -> [String: Result<MarketQuote, Error>] {
        await withTaskGroup(of: (String, Result<MarketQuote, Error>).self) { group in
            for ticker in tickers {
                group.addTask {
                    do {
                        let q = try await self.fetchRealTimeQuote(for: ticker)
                        return (ticker, .success(q))
                    } catch {
                        return (ticker, .failure(error))
                    }
                }
            }
            
            var results: [String: Result<MarketQuote, Error>] = [:]
            for await (ticker, res) in group {
                results[ticker] = res
            }
            return results
        }
    }

    /// 3b. 批量并发获取实时报价（携带市场分类）
    ///
    /// 与 `batchFetchQuotes(for:)` 的区别：会把每条记录的市场分类透传给路由算法。
    /// A 股代码（如 600519）与美股代码规则存在重叠（纯 6 位数字也可能被误判），
    /// 不指定市场时容易路由到错误的行情源导致取价失败，目标价监控会因此彻底失效。
    /// - Parameter items: (标的代码, 市场分类) 列表
    func batchFetchQuotes(for items: [(ticker: String, preferredMarket: String?)]) async -> [String: Result<MarketQuote, Error>] {
        await withTaskGroup(of: (String, Result<MarketQuote, Error>).self) { group in
            for item in items {
                group.addTask {
                    do {
                        let q = try await self.fetchRealTimeQuote(
                            for: item.ticker,
                            preferredMarket: item.preferredMarket
                        )
                        return (item.ticker, .success(q))
                    } catch {
                        return (item.ticker, .failure(error))
                    }
                }
            }

            var results: [String: Result<MarketQuote, Error>] = [:]
            for await (ticker, res) in group {
                results[ticker] = res
            }
            return results
        }
    }
    
    // MARK: - 代码智能识别与自动分流算法 (PRD 4.1 核心录入体验)
    
    /// 依据代码前缀、后缀特征与常见符号，智能路由至对应的行情子系统
    func detectRoute(for rawTicker: String, preferredMarket: String? = nil) -> MarketRoute {
        let text = rawTicker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanText = text.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")

        // 0. 黄金白银大宗商品专属智能识别 (XAU、XAG、原油 CL 等)
        if cleanText == "XAU" || cleanText == "XAUUSD" || cleanText == "GOLD" || cleanText == "GC" || cleanText == "GC=F" {
            return .commodity(symbol: text, mappedTicker: "GC=F", name: "现货黄金 (XAU/USD)")
        }
        if cleanText == "XAG" || cleanText == "XAGUSD" || cleanText == "SILVER" || cleanText == "SI" || cleanText == "SI=F" {
            return .commodity(symbol: text, mappedTicker: "SI=F", name: "现货白银 (XAG/USD)")
        }
        if cleanText == "CL" || cleanText == "WTI" || cleanText == "CRUDE" || cleanText == "OIL" || cleanText == "CL=F" {
            return .commodity(symbol: text, mappedTicker: "CL=F", name: "WTI 原油期货")
        }
        if cleanText == "BZ" || cleanText == "BRENT" || cleanText == "BZ=F" {
            return .commodity(symbol: text, mappedTicker: "BZ=F", name: "布伦特原油期货")
        }
        if cleanText == "HG" || cleanText == "COPPER" || cleanText == "HG=F" {
            return .commodity(symbol: text, mappedTicker: "HG=F", name: "纽约期铜")
        }

        // 0.1 常见外汇货币对 (EURUSD, USDJPY, GBPUSD, AUDUSD, USDCAD, USDCHF, USDCNH, USDCNY 等)
        let knownForexPairs: Set<String> = [
            "EURUSD", "USDJPY", "GBPUSD", "AUDUSD", "USDCAD", "USDCHF",
            "NZDUSD", "EURGBP", "EURJPY", "GBPJPY", "USDCNH", "USDCNY"
        ]
        if knownForexPairs.contains(cleanText) || (preferredMarket == "外汇" && cleanText.count == 6) {
            return .forex(pair: text, mappedTicker: "\(cleanText)=X")
        }

        // 1. 如果用户明确指定了市场，优先按指定市场路由
        if let pref = preferredMarket {
            switch pref {
            case "A股", "aShare", "ASHAR":
                return parseAShareCode(text)
            case "港股", "hkStock", "HK":
                return parseHKCode(text)
            case "美股", "usStock", "US":
                return .usStock(symbol: cleanSymbolOnly(text))
            case "Crypto", "加密货币", "CRYPTO":
                return .crypto(symbol: normalizeCryptoSymbol(text))
            case "黄金与大宗商品", "大宗商品", "商品期货", "贵金属":
                if cleanText.contains("GOLD") || cleanText.contains("XAU") {
                    return .commodity(symbol: text, mappedTicker: "GC=F", name: "现货黄金")
                } else if cleanText.contains("SILVER") || cleanText.contains("XAG") {
                    return .commodity(symbol: text, mappedTicker: "SI=F", name: "现货白银")
                } else if cleanText.contains("OIL") || cleanText.contains("WTI") {
                    return .commodity(symbol: text, mappedTicker: "CL=F", name: "WTI原油")
                }
            case "外汇", "FX", "FOREX":
                return .forex(pair: text, mappedTicker: "\(cleanText)=X")
            default:
                break
            }
        }
        
        // 2. 特征一：加密货币常见特征 (包含 USDT, BTC, ETH, SOL 等)
        if isCryptoPattern(text) {
            return .crypto(symbol: normalizeCryptoSymbol(text))
        }
        
        // 3. 特征二：A股明确前缀或后缀 (sh600519, sz000001, 600519.SH, 000858.SZ)
        if text.hasPrefix("SH") || text.hasPrefix("SZ") || text.hasPrefix("BJ") {
            let prefix = String(text.prefix(2)).lowercased()
            let code = String(text.dropFirst(2))
            return .aShare(code: code, prefix: prefix)
        }
        if text.hasSuffix(".SH") || text.hasSuffix(".SS") {
            let code = String(text.dropLast(3))
            return .aShare(code: code, prefix: "sh")
        }
        if text.hasSuffix(".SZ") {
            let code = String(text.dropLast(3))
            return .aShare(code: code, prefix: "sz")
        }
        if text.hasSuffix(".BJ") {
            let code = String(text.dropLast(3))
            return .aShare(code: code, prefix: "bj")
        }
        
        // 4. 特征三：港股明确标识 (0700.HK, 09988.HK, HK00700)
        if text.hasSuffix(".HK") {
            let num = String(text.dropLast(3))
            return .hkStock(code: formatHKCode(num))
        }
        if text.hasPrefix("HK") && text.count >= 5 {
            let num = String(text.dropFirst(2))
            return .hkStock(code: formatHKCode(num))
        }
        
        // 5. 特征四：纯数字代码自动归类
        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: text)) {
            if text.count == 6 {
                // A股 6 位数字代码智能前缀分配
                if text.hasPrefix("60") || text.hasPrefix("688") {
                    return .aShare(code: text, prefix: "sh") // 上证主板 / 科创板
                } else if text.hasPrefix("00") || text.hasPrefix("30") {
                    return .aShare(code: text, prefix: "sz") // 深证主板 / 创业板
                } else if text.hasPrefix("8") || text.hasPrefix("4") || text.hasPrefix("92") {
                    return .aShare(code: text, prefix: "bj") // 北交所 / 新三板
                } else {
                    return .aShare(code: text, prefix: "sh")
                }
            } else if text.count <= 5 {
                // 1~5 位纯数字通常为港股 (如 700 -> 00700, 9988 -> 09988)
                return .hkStock(code: formatHKCode(text))
            }
        }
        
        // 6. 特征五：1~5 个英文字母，默认按美股标的解析 (如 NVDA, AAPL, TSLA, SPY, QQQ)
        let lettersOnly = text.replacingOccurrences(of: ".", with: "")
        if lettersOnly.count >= 1 && lettersOnly.count <= 6 && lettersOnly.allSatisfy({ $0.isLetter }) {
            return .usStock(symbol: text)
        }
        
        // 无法识别的退回通用
        return .custom(rawTicker: text)
    }
    
    // MARK: - 子系统 4：大宗商品与贵金属行情 (复用 Yahoo Finance 全球期货与现货衍生品接口)
    
    private func fetchCommodityQuote(symbol: String, mappedTicker: String, defaultName: String) async throws -> MarketQuote {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(mappedTicker)?interval=1d&range=5d") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw MarketDataError.networkError("大宗商品行情源响应异常")
        }
        
        let decoded = try JSONDecoder().decode(YahooFinanceChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first else {
            throw MarketDataError.parsingError("大宗商品查询失败")
        }
        
        let meta = result.meta
        let currentPrice = meta.regularMarketPrice ?? meta.previousClose ?? 0.0
        guard currentPrice > 0 else {
            throw MarketDataError.parsingError("未能获取大宗商品最新报价")
        }
        
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? currentPrice
        let change = currentPrice - prevClose
        let changePercent = prevClose > 0 ? (change / prevClose * 100.0) : 0.0
        let name = meta.shortName ?? defaultName
        
        return MarketQuote(
            ticker: symbol,
            displayName: name,
            price: currentPrice,
            change: change,
            changePercent: changePercent,
            marketCategory: "黄金与大宗商品",
            currency: meta.currency ?? "USD"
        )
    }

    // MARK: - 子系统 5：外汇市场行情 (Yahoo Finance 外汇即时汇率)
    
    private func fetchForexQuote(pair: String, mappedTicker: String) async throws -> MarketQuote {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(mappedTicker)?interval=1d&range=5d") else {
            throw MarketDataError.invalidTicker(pair)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw MarketDataError.networkError("外汇行情源响应异常")
        }
        
        let decoded = try JSONDecoder().decode(YahooFinanceChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first else {
            throw MarketDataError.parsingError("外汇查询失败")
        }
        
        let meta = result.meta
        let currentPrice = meta.regularMarketPrice ?? meta.previousClose ?? 0.0
        guard currentPrice > 0 else {
            throw MarketDataError.parsingError("未能获取外汇最新汇率")
        }
        
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? currentPrice
        let change = currentPrice - prevClose
        let changePercent = prevClose > 0 ? (change / prevClose * 100.0) : 0.0
        let name = meta.shortName ?? "\(pair) 汇率"
        
        return MarketQuote(
            ticker: pair,
            displayName: name,
            price: currentPrice,
            change: change,
            changePercent: changePercent,
            marketCategory: "外汇",
            currency: meta.currency ?? "USD"
        )
    }

    // MARK: - 子系统 1：A股行情接口 (腾讯财经 API，免鉴权/零延时)
    
    private func fetchAShareQuote(code: String, prefix: String) async throws -> MarketQuote {
        let fullSymbol = "\(prefix.lowercased())\(code)"
        guard let url = URL(string: "http://qt.gtimg.cn/q=\(fullSymbol)") else {
            throw MarketDataError.invalidTicker(fullSymbol)
        }
        
        let (data, response) = try await session.data(from: url)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw MarketDataError.networkError("腾讯行情响应非 200")
        }
        
        guard let text = decodeGBKOrUTF8(data: data) else {
            throw MarketDataError.parsingError("无法解码行情文本")
        }
        
        // 腾讯行情格式：v_sh600519="1~贵州茅台~600519~1600.00~1590.00~1595.00~...~20260905150000~10.00~0.63~...";
        guard let content = text.split(separator: "=").last else {
            throw MarketDataError.parsingError("数据内容为空")
        }
        let clean = content.trimmingCharacters(in: CharacterSet(charactersIn: "\"; \n\r"))
        let fields = clean.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        
        guard fields.count > 32 else {
            throw MarketDataError.parsingError("行情字段不完整: \(fullSymbol)")
        }
        
        let stockName = fields[1]
        let currentPrice = Double(fields[3]) ?? 0.0
        let prevClose = Double(fields[4]) ?? 0.0
        let change = Double(fields[31])
        let changePercent = Double(fields[32])
        
        // 若盘前当前价为0，使用昨收价保底
        let finalPrice = currentPrice > 0 ? currentPrice : prevClose
        guard finalPrice > 0 else {
            throw MarketDataError.parsingError("标的当前价为 0 或已停牌")
        }
        
        return MarketQuote(
            ticker: code,
            displayName: stockName.isEmpty ? code : stockName,
            price: finalPrice,
            change: change,
            changePercent: changePercent,
            marketCategory: "A股",
            currency: "CNY",
            timestamp: Date()
        )
    }
    
    private func fetchAShareHistorical(code: String, prefix: String, on targetDate: Date) async throws -> HistoricalQuote {
        let candles = try await fetchAShareDailyCandles(code: code, prefix: prefix)
        guard !candles.isEmpty else {
            throw MarketDataError.noHistoricalData(ticker: code, date: targetDate)
        }
        let targetStr = formatDate(targetDate)
        // 精确匹配到期日，或取此前最近的一个真实交易日收盘（遇周末/节假日自动对齐）
        guard let matched = candles.last(where: { formatDate($0.date) <= targetStr }) ?? candles.first else {
            throw MarketDataError.noHistoricalData(ticker: code, date: targetDate)
        }
        return matched
    }
    
    /// 拉取 A 股全部可得日 K（前复权），供历史收盘查询与提前命中扫描共用
    private func fetchAShareDailyCandles(code: String, prefix: String) async throws -> [HistoricalQuote] {
        let fullSymbol = "\(prefix.lowercased())\(code)"
        // 腾讯日 K 线端点 (最多 640 个交易日，约 2.5 年，足以覆盖最长验证周期)
        guard let url = URL(string: "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(fullSymbol),day,,,640,qfq") else {
            throw MarketDataError.invalidTicker(fullSymbol)
        }
        
        let (data, _) = try await session.data(from: url)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let stockDict = dataDict[fullSymbol] as? [String: Any] else {
            throw MarketDataError.parsingError("未能解析 A 股历史 K 线 JSON")
        }
        
        // 优先使用前复权 qfqday，不存在则使用 day
        let rawDays = (stockDict["qfqday"] as? [[Any]]) ?? (stockDict["day"] as? [[Any]]) ?? []
        
        // 每一项: ["2026-09-04", "开盘", "收盘", "最高", "最低", "成交量"]
        return rawDays.compactMap { item -> HistoricalQuote? in
            guard item.count >= 5,
                  let dStr = item[0] as? String,
                  let date = parseDate(dStr),
                  let close = Double(String(describing: item[2])) else { return nil }
            return HistoricalQuote(
                ticker: code,
                date: date,
                closePrice: close,
                highPrice: Double(String(describing: item[3])),
                lowPrice: Double(String(describing: item[4])),
                marketCategory: "A股"
            )
        }
        .sorted { $0.date < $1.date }
    }
    
    /// 拉取美股 / 港股指定区间日 K (Yahoo Finance v8 Chart API)
    private func fetchYahooDailyCandles(symbol: String, category: String, from startDate: Date, to endDate: Date) async throws -> [HistoricalQuote] {
        let period1 = Int(startDate.timeIntervalSince1970)
        let period2 = Int(endDate.timeIntervalSince1970) + 86400
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?period1=\(period1)&period2=\(period2)&interval=1d") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(YahooFinanceChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let quotes = result.indicators?.quote?.first,
              let closes = quotes.close else {
            throw MarketDataError.noHistoricalData(ticker: symbol, date: endDate)
        }
        
        var out: [HistoricalQuote] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < closes.count, let close = closes[i] else { continue }
            let high = (quotes.high != nil && i < quotes.high!.count) ? quotes.high![i] : nil
            let low = (quotes.low != nil && i < quotes.low!.count) ? quotes.low![i] : nil
            out.append(HistoricalQuote(
                ticker: symbol,
                date: Date(timeIntervalSince1970: TimeInterval(ts)),
                closePrice: close,
                highPrice: high,
                lowPrice: low,
                marketCategory: category
            ))
        }
        return out.sorted { $0.date < $1.date }
    }
    
    /// 拉取加密货币日 K (Binance Public Klines)
    ///
    /// ⚠️ 域名说明：必须使用 `data-api.binance.vision`，**不要改回 `api.binance.com`**。
    /// Binance 主域（api / api1 / api2）对中国大陆等受限地区返回 HTTP 451 区域限制，
    /// 会导致 Crypto 分类完全取不到价。`data-api.binance.vision` 是 Binance 官方提供的
    /// 只读镜像，专为受限地区设计，API 路径与主域完全一致。
    private func fetchCryptoDailyCandles(symbol: String) async throws -> [HistoricalQuote] {
        let cleanSymbol = normalizeCryptoSymbol(symbol)
        guard let url = URL(string: "https://data-api.binance.vision/api/v3/klines?symbol=\(cleanSymbol)&interval=1d&limit=1000") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        let (data, _) = try await session.data(from: url)
        guard let klines = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw MarketDataError.parsingError("加密货币日 K 解析失败")
        }
        
        // Binance kline: [开盘时间(ms), 开盘价, 最高价, 最低价, 收盘价, 成交量, ...]
        return klines.compactMap { c -> HistoricalQuote? in
            guard c.count >= 5,
                  let openMs = (c[0] as? NSNumber)?.doubleValue,
                  let close = Double(String(describing: c[4])) else { return nil }
            return HistoricalQuote(
                ticker: formatCryptoDisplayName(cleanSymbol),
                date: Date(timeIntervalSince1970: openMs / 1000.0),
                closePrice: close,
                highPrice: Double(String(describing: c[2])),
                lowPrice: Double(String(describing: c[3])),
                marketCategory: "Crypto"
            )
        }
        .sorted { $0.date < $1.date }
    }
    
    // MARK: - 子系统 2：港股行情接口 (腾讯 r_hk 前缀 / Yahoo Finance)
    
    private func fetchHKStockQuote(code: String) async throws -> MarketQuote {
        let fullCode = "r_hk\(code)"
        guard let url = URL(string: "http://qt.gtimg.cn/q=\(fullCode)") else {
            throw MarketDataError.invalidTicker(code)
        }
        
        let (data, _) = try await session.data(from: url)
        guard let text = decodeGBKOrUTF8(data: data),
              let content = text.split(separator: "=").last else {
            throw MarketDataError.parsingError("港股数据响应解析失败")
        }
        
        let clean = content.trimmingCharacters(in: CharacterSet(charactersIn: "\"; \n\r"))
        let fields = clean.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        
        guard fields.count > 32 else {
            throw MarketDataError.parsingError("港股字段不足")
        }
        
        let name = fields[1]
        let currentPrice = Double(fields[3]) ?? 0.0
        let prevClose = Double(fields[4]) ?? 0.0
        let change = Double(fields[31])
        let changePercent = Double(fields[32])
        
        let finalPrice = currentPrice > 0 ? currentPrice : prevClose
        return MarketQuote(
            ticker: "\(code).HK",
            displayName: name.isEmpty ? "\(code).HK" : name,
            price: finalPrice,
            change: change,
            changePercent: changePercent,
            marketCategory: "港股",
            currency: "HKD"
        )
    }
    
    private func fetchHKStockHistorical(code: String, on date: Date) async throws -> HistoricalQuote {
        // 港股日线借助 Yahoo Finance 稳妥获取
        let yahooTicker = "\(code).HK"
        return try await fetchUSStockHistorical(symbol: yahooTicker, on: date, overrideCategory: "港股")
    }
    
    // MARK: - 子系统 3：美股行情接口 (Yahoo Finance v8 Chart API)
    
    private func fetchUSStockQuote(symbol: String) async throws -> MarketQuote {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=5d") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw MarketDataError.networkError("Yahoo Finance 响应异常")
        }
        
        let decoded = try JSONDecoder().decode(YahooFinanceChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first else {
            let errorMsg = decoded.chart.error?.description ?? "无返回结果"
            throw MarketDataError.parsingError("美股查询失败: \(errorMsg)")
        }
        
        let meta = result.meta
        let currentPrice = meta.regularMarketPrice ?? meta.previousClose ?? 0.0
        guard currentPrice > 0 else {
            throw MarketDataError.parsingError("未能获取美股最新报价")
        }
        
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? currentPrice
        let change = currentPrice - prevClose
        let changePercent = prevClose > 0 ? (change / prevClose * 100.0) : 0.0
        let name = meta.shortName ?? meta.longName ?? symbol
        
        return MarketQuote(
            ticker: symbol,
            displayName: name,
            price: currentPrice,
            change: change,
            changePercent: changePercent,
            marketCategory: "美股",
            currency: meta.currency ?? "USD"
        )
    }
    
    private func fetchUSStockHistorical(symbol: String, on targetDate: Date, overrideCategory: String = "美股") async throws -> HistoricalQuote {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=6mo") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(YahooFinanceChartResponse.self, from: data)
        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let quotes = result.indicators?.quote?.first,
              let closes = quotes.close else {
            throw MarketDataError.noHistoricalData(ticker: symbol, date: targetDate)
        }
        
        let targetSec = targetDate.timeIntervalSince1970
        
        // 寻找时间最接近且 <= 目标结算时刻的交易日收盘
        var bestIndex: Int?
        for (i, ts) in timestamps.enumerated().reversed() {
            if Double(ts) <= targetSec + 86400 { // 宽松覆盖当天的交易收盘
                if i < closes.count, closes[i] != nil {
                    bestIndex = i
                    break
                }
            }
        }
        
        let finalIndex = bestIndex ?? (closes.indices.last)
        guard let idx = finalIndex, idx < closes.count, let closePrice = closes[idx] else {
            throw MarketDataError.noHistoricalData(ticker: symbol, date: targetDate)
        }
        
        let highPrice = (quotes.high != nil && idx < quotes.high!.count) ? quotes.high![idx] : nil
        let lowPrice = (quotes.low != nil && idx < quotes.low!.count) ? quotes.low![idx] : nil
        let matchedDate = Date(timeIntervalSince1970: TimeInterval(timestamps[idx]))
        
        return HistoricalQuote(
            ticker: symbol,
            date: matchedDate,
            closePrice: closePrice,
            highPrice: highPrice,
            lowPrice: lowPrice,
            marketCategory: overrideCategory
        )
    }
    
    // MARK: - 子系统 4：加密货币行情接口 (Binance Public REST API)
    
    private func fetchCryptoQuote(symbol: String) async throws -> MarketQuote {
        let cleanSymbol = normalizeCryptoSymbol(symbol)
        guard let url = URL(string: "https://data-api.binance.vision/api/v3/ticker/24hr?symbol=\(cleanSymbol)") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        let (data, response) = try await session.data(from: url)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            // 若 24hr 失败，降级尝试简易 ticker/price
            return try await fetchCryptoSimpleQuote(cleanSymbol: cleanSymbol)
        }
        
        let ticker24 = try JSONDecoder().decode(Binance24hrTicker.self, from: data)
        guard let price = Double(ticker24.lastPrice) else {
            throw MarketDataError.parsingError("加密货币最新价转换失败")
        }
        
        let change = Double(ticker24.priceChange ?? "")
        let changePercent = Double(ticker24.priceChangePercent ?? "")
        let display = formatCryptoDisplayName(cleanSymbol)
        
        return MarketQuote(
            ticker: display,
            displayName: display,
            price: price,
            change: change,
            changePercent: changePercent,
            marketCategory: "Crypto",
            currency: "USDT"
        )
    }
    
    private func fetchCryptoSimpleQuote(cleanSymbol: String) async throws -> MarketQuote {
        guard let url = URL(string: "https://data-api.binance.vision/api/v3/ticker/price?symbol=\(cleanSymbol)") else {
            throw MarketDataError.invalidTicker(cleanSymbol)
        }
        let (data, _) = try await session.data(from: url)
        let simple = try JSONDecoder().decode(BinancePriceTicker.self, from: data)
        guard let price = Double(simple.price) else {
            throw MarketDataError.parsingError("加密货币价格解析失败")
        }
        let display = formatCryptoDisplayName(cleanSymbol)
        return MarketQuote(
            ticker: display,
            displayName: display,
            price: price,
            change: nil,
            changePercent: nil,
            marketCategory: "Crypto",
            currency: "USDT"
        )
    }
    
    private func fetchCryptoHistorical(symbol: String, on targetDate: Date) async throws -> HistoricalQuote {
        let cleanSymbol = normalizeCryptoSymbol(symbol)
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: targetDate)
        let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endMs = startMs + 86400000 // 24小时后
        
        guard let url = URL(string: "https://data-api.binance.vision/api/v3/klines?symbol=\(cleanSymbol)&interval=1d&startTime=\(startMs)&endTime=\(endMs)&limit=1") else {
            throw MarketDataError.invalidTicker(symbol)
        }
        
        let (data, _) = try await session.data(from: url)
        guard let klines = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let firstCandle = klines.first,
              firstCandle.count >= 5 else {
            throw MarketDataError.noHistoricalData(ticker: symbol, date: targetDate)
        }
        
        // Binance kline 格式: [开盘时间, 开盘价, 最高价, 最低价, 收盘价, 成交量, ...]
        let highStr = String(describing: firstCandle[2])
        let lowStr = String(describing: firstCandle[3])
        let closeStr = String(describing: firstCandle[4])
        
        guard let closePrice = Double(closeStr) else {
            throw MarketDataError.parsingError("加密货币日 K 收盘价解析失败")
        }
        
        return HistoricalQuote(
            ticker: formatCryptoDisplayName(cleanSymbol),
            date: targetDate,
            closePrice: closePrice,
            highPrice: Double(highStr),
            lowPrice: Double(lowStr),
            marketCategory: "Crypto"
        )
    }
    
    // MARK: - 工具方法与解析辅助
    
    private func isCryptoPattern(_ text: String) -> Bool {
        if text.contains("/USDT") || text.contains("-USDT") || text.hasSuffix("USDT") ||
           text.contains("/USD") || text.contains("-USD") || text.contains("/BUSD") ||
           text.contains("/USDC") {
            return true
        }
        let commonCoins: Set<String> = [
            "BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "AVAX", "DOT", "LINK",
            "MATIC", "NEAR", "SUI", "APT", "PEPE", "SHIB", "TRX", "TON", "LTC", "BCH",
            "UNI", "ATOM", "ARB", "OP", "RENDER", "FET", "INJ", "FIL", "TIA", "KAS"
        ]
        return commonCoins.contains(text)
    }
    
    private func normalizeCryptoSymbol(_ raw: String) -> String {
        var clean = raw.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.hasSuffix("USDT") && !clean.hasSuffix("BUSD") && !clean.hasSuffix("USDC") {
            clean += "USDT"
        }
        return clean
    }
    
    private func formatCryptoDisplayName(_ cleanSymbol: String) -> String {
        if cleanSymbol.hasSuffix("USDT") {
            let base = String(cleanSymbol.dropLast(4))
            return "\(base)/USDT"
        }
        return cleanSymbol
    }
    
    private func parseAShareCode(_ text: String) -> MarketRoute {
        let clean = cleanDigitsAndLetters(text)
        if clean.hasPrefix("SH") || clean.hasPrefix("SZ") || clean.hasPrefix("BJ") {
            return .aShare(code: String(clean.dropFirst(2)), prefix: String(clean.prefix(2)).lowercased())
        }
        if clean.count == 6 {
            let prefix = (clean.hasPrefix("60") || clean.hasPrefix("688")) ? "sh" : ((clean.hasPrefix("8") || clean.hasPrefix("4") || clean.hasPrefix("92")) ? "bj" : "sz")
            return .aShare(code: clean, prefix: prefix)
        }
        return .aShare(code: clean, prefix: "sh")
    }
    
    private func parseHKCode(_ text: String) -> MarketRoute {
        let digits = text.filter { $0.isNumber }
        return .hkStock(code: formatHKCode(digits.isEmpty ? text : digits))
    }
    
    private func formatHKCode(_ numStr: String) -> String {
        let digits = numStr.filter { $0.isNumber }
        let padding = max(0, 5 - digits.count)
        return String(repeating: "0", count: padding) + digits
    }
    
    private func cleanDigitsAndLetters(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }
    }
    
    private func cleanSymbolOnly(_ text: String) -> String {
        text.replacingOccurrences(of: ".US", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeGBKOrUTF8(data: Data) -> String? {
        // 使用 GB18030 / GBK 解码中文字符
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        if let str = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
            return str
        }
        return String(data: data, encoding: .utf8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}

// MARK: - Yahoo Finance JSON 映射

private struct YahooFinanceChartResponse: Codable {
    let chart: ChartContent
    
    struct ChartContent: Codable {
        let result: [ChartResult]?
        let error: ChartError?
    }
    
    struct ChartResult: Codable {
        let meta: ChartMeta
        let timestamp: [Int]?
        let indicators: ChartIndicators?
    }
    
    struct ChartMeta: Codable {
        let currency: String?
        let symbol: String?
        let regularMarketPrice: Double?
        let previousClose: Double?
        let chartPreviousClose: Double?
        let shortName: String?
        let longName: String?
    }
    
    struct ChartIndicators: Codable {
        let quote: [QuoteValues]?
    }
    
    struct QuoteValues: Codable {
        let high: [Double?]?
        let low: [Double?]?
        let open: [Double?]?
        let close: [Double?]?
    }
    
    struct ChartError: Codable {
        let code: String?
        let description: String?
    }
}

// MARK: - Binance JSON 映射

private struct Binance24hrTicker: Codable {
    let symbol: String
    let priceChange: String?
    let priceChangePercent: String?
    let lastPrice: String
}

private struct BinancePriceTicker: Codable {
    let symbol: String
    let price: String
}
