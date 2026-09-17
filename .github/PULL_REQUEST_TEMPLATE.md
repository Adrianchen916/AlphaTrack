## 改了什么

<!-- 一句话说明；涉及多个改动请分点 -->

## 为什么这么改

<!-- 动机 / 背景 / 关联 Issue（如 Closes #12） -->

## 怎么验证的

<!-- UI 改动建议附截图或录屏 -->

- [ ] 本地 `xcodebuild -scheme AlphaTrack -configuration Debug build` 通过
- [ ] 视觉改动取色全部走 `Theme/ATTheme.swift` 的 `AT` 设计令牌，无硬编码颜色
- [ ] 提交信息符合 Conventional Commits
- [ ] 未引入遥测 / 埋点 / 第三方分析 / 账号体系
