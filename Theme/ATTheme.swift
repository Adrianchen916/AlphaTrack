//
//  ATTheme.swift
//  AlphaTrack
//
//  原型 v4 (AlphaTrack_Prototype_v4.html) 设计令牌统一落地：
//  行情涨跌（A 股习惯：涨红跌绿）、多空立场、胜率三档、强调色、
//  卡片 / 描边 / 文字 / 表面分层（含深浅双模），以及通用小组件
//  （TagView 徽章、ATSwitch 胶囊开关、ATCheckbox 方形勾选框、按压按钮样式）。
//
//  所有视图一律通过 AT.xxx(isDark) 取色，禁止再散落硬编码颜色，
//  保证 Dashboard / HUD / MenuBar / 详情 / 来源 / 设置六大界面视觉完全一致。
//

import SwiftUI

// MARK: - 设计令牌

enum AT {
    // ---- 固定色（不随深浅切换） ----

    /// 强调蓝 #0A84FF（原型 --accent）
    static let accent = Color(red: 10/255, green: 132/255, blue: 255/255)
    /// 警示琥珀 #FF9F0A（原型 --warn）
    static let warn = Color(red: 255/255, green: 159/255, blue: 10/255)
    /// 强调蓝 hover 态
    static let accentHover = Color(red: 10/255, green: 118/255, blue: 224/255)

    // ---- 行情涨跌（涨绿跌红：与看多/看空立场色统一） ----
    // 设计决策：项目为多市场混合（A股/美股/港股/Crypto/黄金），若沿用 A 股"涨红跌绿"
    // 会与"看多绿、看空红"的立场色互相矛盾（看多持仓上涨时数字红、箭头绿）。
    // 统一为国际通用的涨绿跌红后，全 App 仅一套红绿语义：
    //   绿 = 向上 / 看多 / 判断在兑现
    //   红 = 向下 / 看空 / 判断落空

    /// 上涨绿：浅色 #30A46C / 深色 #3DD68C（与 bull 同色）
    static func rise(_ dark: Bool) -> Color {
        dark ? Color(red: 61/255, green: 214/255, blue: 140/255)
             : Color(red: 48/255, green: 164/255, blue: 108/255)
    }

    /// 下跌红：浅色 #E5484D / 深色 #FF6369（与 bear 同色）
    static func fall(_ dark: Bool) -> Color {
        dark ? Color(red: 255/255, green: 99/255, blue: 105/255)
             : Color(red: 229/255, green: 72/255, blue: 77/255)
    }

    /// 涨跌幅配色：>=0 用涨绿，<0 用跌红
    static func riseFall(_ pct: Double, _ dark: Bool) -> Color {
        pct >= 0 ? rise(dark) : fall(dark)
    }

    // ---- 多空立场（PRD 5.1.2） ----

    /// 看多翡翠绿：浅色 #30A46C / 深色 #3DD68C（原型 --bull）
    static func bull(_ dark: Bool) -> Color {
        dark ? Color(red: 61/255, green: 214/255, blue: 140/255)
             : Color(red: 48/255, green: 164/255, blue: 108/255)
    }

    /// 看空赤红：浅色 #E5484D / 深色 #FF6369（原型 --bear）
    static func bear(_ dark: Bool) -> Color {
        dark ? Color(red: 255/255, green: 99/255, blue: 105/255)
             : Color(red: 229/255, green: 72/255, blue: 77/255)
    }

    // ---- 胜率三档（原型 --win-hi / --win-mid / --win-lo） ----

    static func winHi(_ dark: Bool) -> Color { bull(dark) }
    static func winMid(_ dark: Bool) -> Color {
        dark ? Color(red: 255/255, green: 179/255, blue: 64/255)
             : Color(red: 255/255, green: 159/255, blue: 10/255)
    }
    static func winLo(_ dark: Bool) -> Color { bear(dark) }

    /// 按胜率取三档色：>=60 翡翠绿 / 40–60 琥珀黄 / <40 警戒红；nil 用三级文字色
    static func winRateColor(_ rate: Double?, _ dark: Bool) -> Color {
        guard let rate else { return text3(dark) }
        if rate >= 60 { return winHi(dark) }
        if rate >= 40 { return winMid(dark) }
        return winLo(dark)
    }

    // ---- 表面与分层（原型 --card-bg / --card-border / --seg / --hover / --active-bg / --track / --sep） ----

    /// 卡片底：浅色纯白 / 深色白 5%（原型 --card-bg）
    static func cardBg(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.05) : Color.white
    }

    /// 卡片描边（0.5px hairline 的 1px 近似）
    static func cardBorder(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    /// 分组灰底（原型 --seg）
    static func seg(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055)
    }

    /// 悬停底（原型 --hover）
    static func hover(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    /// 选中激活底（原型 --active-bg）
    static func activeBg(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.075)
    }

    /// 控件底（输入框等，原型 --control）
    static func control(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.white.opacity(0.85)
    }

    /// 进度条轨道（原型 --track）
    static func track(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    /// 分隔线（原型 --sep）
    static func sep(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.11)
    }

    /// 侧栏底色（原型 --sidebar-bg）
    static func sidebarBg(_ dark: Bool) -> Color {
        dark ? Color.black.opacity(0.18)
             : Color(red: 233/255, green: 235/255, blue: 241/255).opacity(0.6)
    }

    /// 窗口底色（原型 --win-bg 的不透明近似）
    static func windowBg(_ dark: Bool) -> Color {
        dark ? Color(red: 32/255, green: 33/255, blue: 37/255)
             : Color(red: 246/255, green: 246/255, blue: 248/255)
    }

    // ---- 文字层级（原型 --text / --text-2 / --text-3） ----

    static func text(_ dark: Bool) -> Color {
        dark ? Color(red: 245/255, green: 245/255, blue: 247/255)
             : Color(red: 29/255, green: 29/255, blue: 31/255)
    }

    static func text2(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.60) : Color.black.opacity(0.62)
    }

    static func text3(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.34) : Color.black.opacity(0.34)
    }

    // ---- 市场分类圆点（原型侧栏 nav-dot 配色） ----

    static func marketDot(_ name: String) -> Color {
        switch name {
        case "A股":   return Color(red: 229/255, green: 72/255, blue: 77/255)
        case "美股":  return AT.accent
        case "港股":  return Color(red: 255/255, green: 159/255, blue: 10/255)
        case "Crypto": return Color(red: 142/255, green: 124/255, blue: 255/255)
        default:      return Color(red: 199/255, green: 163/255, blue: 74/255)
        }
    }

    // ---- 市场分类旗帜 / 圆点双呈现 ----

    static func marketFlag(_ name: String) -> String {
        switch name {
        case "A股": return "🇨🇳"
        case "美股": return "🇺🇸"
        case "港股": return "🇭🇰"
        case "Crypto": return "🪙"
        case "黄金白银", "黄金与大宗商品": return "🟡"
        case "商品期货": return "🌾"
        default: return "⚡"
        }
    }
}

// MARK: - 通用小组件

/// 原型 .tag 徽章：19pt 高、5pt 圆角、11px semibold、色底 14% 透明度
struct TagView: View {
    enum Style {
        case neutral          // 灰
        case rise             // 涨红
        case fall             // 跌绿
        case bull             // 看多绿
        case bear             // 看空红
        case fact             // 客观蓝
        case warn             // 琥珀
        case winHi            // 胜率绿
    }

    let text: String
    let style: Style
    var dark: Bool

    private var fg: Color {
        switch style {
        case .neutral: return AT.text2(dark)
        case .rise:    return AT.rise(dark)
        case .fall:    return AT.fall(dark)
        case .bull:    return AT.bull(dark)
        case .bear:    return AT.bear(dark)
        case .fact:    return AT.accent
        case .warn:    return AT.warn
        case .winHi:   return AT.winHi(dark)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(fg.opacity(0.14))
            .cornerRadius(5)
            .lineLimit(1)
    }
}

/// 原型 .switch 胶囊开关：38×22、圆角 999、白珠
struct ATSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AT.winHi(false) : AT.track(false))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

/// 原型 .check 方形勾选框：15×15、4pt 圆角、选中 accent 填充 + 白勾
struct ATCheckbox: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? AT.accent : AT.control(false))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isOn ? AT.accent : AT.cardBorder(false), lineWidth: 1)
                        )
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(width: 15, height: 15)

                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(AT.text2(false))
            }
        }
        .buttonStyle(.plain)
    }
}

/// 按压缩放按钮样式（原型 .press: active scale 0.97）
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

/// 原型 kbd 小键帽徽章
struct KbdBadge: View {
    let key: String
    var size: CGFloat = 10

    var body: some View {
        Text(key)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundColor(AT.text3(false))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(AT.seg(false))
            .cornerRadius(4)
    }
}

/// 原型 section-head：13px semibold 标题 + 11px hint + 延伸 hairline
struct SectionHead: View {
    let title: String
    var hint: String? = nil
    var dark: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AT.text(dark))
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(dark))
            }
            Rectangle()
                .fill(AT.sep(dark))
                .frame(height: 1)
        }
    }
}

/// 原型 page-head：22px 粗标题 + 12px 副标
struct PageHead: View {
    let title: String
    let subtitle: String
    var dark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AT.text(dark))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(AT.text2(dark))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
