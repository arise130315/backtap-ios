# CONTEXT.md — iOS快捷翻译

> 项目当前状态。**每次会话结束前更新这份文件**,把这次做了什么、卡在哪、下次接着做什么写清楚。
> 详细的每日改动可以选择性记到 `daily/[日期].md`。

---

## 当前进度

主 App + 两个 AppIntent(快捷翻译 / 快捷分析)端外入口已联通,iOS 26 上的呈现适配是当前的主要工作。

**工作目录有大量未提交改动**(主项目 `~/Desktop/iOS快捷翻译` 在 `main` 分支),具体见下方"未解决"。

## 正在做什么

分析 snippet 在 iOS 26 上的呈现适配。**根因已锁定**:iOS 26 给所有第三方 AppIntent 的 `ShowsSnippetView`(自定义 SwiftUI 视图)默认盖一层黄底 + 红色禁用图标的"未经验证 UI"警告;只有 `ProvidesDialog`(纯文字)走系统原生渲染管道,不会被加警告。

- 快捷分析:已改 `ProvidesDialog`,**无黄底**。失去 Markdown 加粗等富文本能力,用 `【内容】`/`【要点】`、Unicode 软换行/段落分隔符做排版。
- 快捷翻译:结果是图片,Dialog 装不下,只能继续 `ShowsSnippetView`,**接受黄底**。

## 未解决的问题 / 卡点

1. **翻译 snippet 黄底**:产品权衡,不是 bug——iOS 26 的硬限制,没办法在保留图片预览的同时去掉警告。
2. **Dialog "平衡换行"行宽变窄**:iOS Dialog 对短段落用 minimum-raggedness 算法,行宽看起来短。已用"无 bullet 标记 + `\u{2028}` 软换行连入同段"绕过,大段场景能填满,某些短 bullet 仍偏短。这是 iOS 渲染器行为,端不可控,接受现状。
3. **工作目录脏**:主 App 资源(`AppIcon.icon/`、`Assets.xcassets/AppIcon.appiconset/`、`Onboarding`、`Settings`、`HistoryView`、`HistoryItem`)有未本会话明确触碰的改动,提交前需要梳理。
4. **`AnalysisDetailView`(历史详情页)**未跟进:它仍用 `Text(LocalizedStringKey)` + `.textSelection(.enabled)`,跟主页的 `SelectableMarkdownText` 不一致。
5. **`SelectableMarkdownText` 的拖拽未禁**:UITextView 默认允许把选中文字拖到其他 App。在主 App 内不易触发,但严格说也应加 `textDragInteraction.isEnabled = false`。

## 下一步打算

- 把工作区改动整理成提交(用户决定一次还是分批)
- 推到 GitHub 远端
- 决定是否给 `AnalysisDetailView` 换 `SelectableMarkdownText` 保持一致
- 决定是否给 `SelectableMarkdownText` 关拖拽

---

## 会话日志(倒序,最新在上)

### 2026-05-17 (Claude Code)

**主线**:iOS 26 上 AppIntent snippet 黄底警告诊断与处理 + 多处 UI 打磨。

#### 关键诊断
- 黄底+禁用图标来自 **iOS 26 对所有 `ShowsSnippetView` 自动盖的"未经验证第三方 UI"警告**,跟 LLM、网络、图片、PrivacyInfo 都无关。
- 验证路径:`Text(LocalizedStringKey)` → `AttributedString(markdown:)` → 加 `.background` 兜底 → 新建 `PrivacyInfo.xcprivacy` → 改 `Dialog + SnippetView` 组合 → 全部无效,**只有改纯 `ProvidesDialog` 才生效**。

#### 改动文件清单

**`SnapTranslate/SnapTranslate/AppIntents/AnalyzeScreenshotIntent.swift`** — 大幅简化
- 返回类型 `ShowsSnippetView` → `ProvidesDialog`
- 删除 `AnalysisSnippetView` struct(死代码)、`import SwiftUI`/`import UIKit`
- 新增 `formatForDialog(_:)`:
  - `**内容**`/`**要点**` → `【内容】`/`【要点】`
  - 状态机按行解析(header / paragraph / bullet),bullet continuation 拼回 bullet 内
  - 不加 `- ` `• ` 等段首符号(iOS 对 "符号+空格" 段首会进 list-mode 缩进,行宽变窄)
  - 用 `\u{2028}` LINE SEPARATOR / `\u{2029}` PARAGRAPH SEPARATOR 替代 `\n`(iOS 会把 `\n` 折叠成空格)
  - header 之间用 `\u{2029}\u{00A0}\u{2029}` 制造视觉空行(NBSP 占位防 trim)

**`SnapTranslate/SnapTranslate/AppIntents/TranslateScreenshotIntent.swift`**
- 试 `Dialog & ShowsSnippetView` 组合无效,回滚原 `ShowsSnippetView`,接受黄底
- `TranslationSnippetView` 删 `cornerRadius: 24`,圆角回 0

**`SnapTranslate/SnapTranslate/Core/Translation/LLMTranslationService.swift`**
- 新增 `struct SameLanguageError: Error`
- 70%+ 段与原文一致时改抛 `SameLanguageError`(原抛带文案的 `LLMError`,会触发"翻译失败"提示)

**`SnapTranslate/SnapTranslate/Core/Translation/TranslationPipeline.swift`**(AppIntent 端外路径)
- `catch is LLMTranslationService.SameLanguageError` → 返回原图

**`SnapTranslate/SnapTranslate/ContentView.swift`**
- `runBuiltinTranslation` / `runLLMTranslation` 都加 `catch is SameLanguageError`,静默吞,`translatedImage` 保持 nil → 用户看到原图,不弹错
- `analysisArea` 上移按钮:VStack `spacing: 0` + HStack `.padding(.top, -16)`
- 新增 `SelectableMarkdownText`(UIViewRepresentable 包 `UITextView`),让分析正文支持长按选词跟手指弹菜单;含 `sizeThatFits(_:uiView:context:)` 防止把页面撑大
- `analysisArea` 底部 `LinearGradient` 渐变遮罩(暗示有更多内容可滑)
- 新增 `loadingBackground` 计算属性:浅色 5% 黑 / 深色 10% 白,24pt 圆角
- `ProgressView` 去掉 `.tint(.white)` `.foregroundStyle(.white)`,跟随系统色

**`SnapTranslate/SnapTranslate/Core/Analysis/ImageAnalysisService.swift`**
- 试 prompt 字数压到 ≤150 字 + sanitize 截到 160,**回滚**——用户反馈面板高度变小,改回 200 字 + sanitize 250
- iOS Dialog 是**动态高度**,内容长面板就高,这是甜区平衡

**`SnapTranslate/SnapTranslate/PrivacyInfo.xcprivacy`**(新增)
- 声明:不追踪、收集 Photos/UserContent 仅用于 AppFunctionality、用 UserDefaults/FileTimestamp/DiskSpace/SystemBootTime 等 Required Reason API
- 起初想用来解黄底,事实无关。但 manifest 本身有用(Apple 隐私清单合规),保留

#### 提交状态
**全部未提交**,工作目录仍脏。用户偏好:改动后主动询问是否提交+推送。
