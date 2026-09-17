# 贡献指南

感谢你愿意为 AlphaTrack 出一份力。🎉

## 开工前

**环境要求**

- macOS 14.0+ (Sonoma 及以上)
- Xcode 15+（项目在 Xcode 27 上开发验证）
- 无需付费开发者账号：`Signing` 勾选 `Automatically manage signing` 即可本地运行

**本地跑起来**

```bash
git clone https://github.com/Adrianchen916/AlphaTrack.git
cd AlphaTrack
open AlphaTrack.xcodeproj
# ⌘R 运行；或用命令行验证编译
xcodebuild -scheme AlphaTrack -configuration Debug build
```

## 提 Issue

- **Bug**：请附上 macOS 版本、Xcode 版本、复现步骤、以及 Console.app 里 `[AlphaTrack]` 前缀的日志
- **功能建议**：说清楚你想解决的**场景**，而不是直接给解决方案 —— 大多数情况下会有更好的做法
- 提交前先搜一下是否已有同类 Issue

## 提交 PR

流程：

1. Fork 仓库，从 `main` 拉分支：`feat/xxx` 或 `fix/xxx`
2. 写代码
3. **必须本地验证编译通过**：
   ```bash
   xcodebuild -scheme AlphaTrack -configuration Debug build
   ```
   只在 Xcode 里点 Run 不算通过。
4. 提交信息遵守 **Conventional Commits**
5. 开 PR，说明改了什么、为什么这么改、怎么验证的

### Commit Message 规范

```
feat(Dashboard): 新增收益曲线卡片
fix(MenuBar): 修复微面板每次弹出不刷新现价
chore: 清理无用 Assets
docs: 补充 README 构建说明
refactor(Theme): 收敛硬编码颜色至 AT 令牌
```

Scope 取值倾向用模块名：`HUD` / `Dashboard` / `MenuBar` / `MarketData` / `Arbitration` / `Storage` / `Settings` / `Theme`。

## 代码约定

这几条是硬性要求，PR review 会卡：

1. **取色必须走设计令牌**
   所有颜色统一走 `Theme/ATTheme.swift` 的 `AT.xxx(isDark)`，禁止在视图里散落硬编码 `Color(...)`/`Color.red`。目的是保证 Dashboard / HUD / MenuBar / 详情 / 来源 / 设置六大界面视觉完全一致。

2. **视觉的唯一来源是设计令牌**
   `Theme/ATTheme.swift` 就是 UI 的对齐基准 —— 颜色、圆角、间距全部集中在这里。改动视觉请先改令牌，让六大界面一起生效，不要在单个视图里做局部特调。

3. **颜色语义：涨绿跌红**
   因为项目横跨 A股 / 美股 / 港股 / Crypto 多市场，全 App 只保留一套红绿语义：
   - 绿 = 向上 / 看多 / 判断在兑现
   - 红 = 向下 / 看空 / 判断落空

4. **新增 Swift 文件放对应子目录即可**
   工程用的是 Xcode 文件夹同步组，新文件会自动纳入编译，不需要手动 Add to Target。

5. **`AppIconMaster.png` 不要移出源码根**
   运行时从 bundle 读取，移动会导致图标失效。

6. **对账逻辑不可误判**
   `ArbitrationEngine` 的铁律：取数失败一律保持「进行中」等待重试，**绝不自动判定失效或判负**。任何触碰这条的改动都需要特别说明。

7. **隐私红线**
   项目卖点是「零云端依赖、纯本地私密」。任何引入遥测、埋点、第三方分析 SDK、账号体系的改动都会被拒绝。

## 行情数据源注意事项

- A股 / 港股实时行情走腾讯财经 `qt.gtimg.cn`（返回 GB18030 编码，`Info.plist` 里配了 ATS 例外）
- 美股 / 大宗 / 外汇历史 K 走 Yahoo Finance v8 Chart API
- **Crypto 必须用 `data-api.binance.vision`**，不要改回 `api.binance.com` —— 主域会对中国大陆等受限地区返回 HTTP 451，导致 Crypto 分类彻底取不到价
- 新增接口请加请求节流/缓存，别把公开接口打爆

## 行为准则

保持友善，对事不对人。讨论的是代码，不是写代码的人。
