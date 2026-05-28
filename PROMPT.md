# 识图翻译 iOS App — 开发提示词

> 把整份文档作为初始指令交给 AI 编程助手（Claude Code / Cursor / Xcode AI），它就能按此规格搭出 MVP。

## 一、产品定位

**App 名称**：识图翻译
**一句话定位**：iOS 上"截图即译"的工具，专治外文 App 界面看不懂的痛点。
**目标用户**：跨境工作 / 留学 / 海淘 / 玩外区游戏 / 用海外软件的中文用户。

## 二、核心用户旅程（MVP）

1. 用户在任意外文 App 中触发"识图翻译"（三种入口任选其一，全部要支持）：
   - **入口 A（最快，推荐）**：操作按钮 / 背面双击 / 控制中心 → 触发 Shortcut → 自动截图 → **在外文 App 上方弹出半屏 Snippet 面板显示翻译结果，用户不会被切出原 App**（基于 App Intent `ShowsSnippetView`，iOS 17+）。Snippet 内放"打开 App 看大图 / 对照原图"按钮兜底复杂操作。
   - **入口 B**：系统截图 → 点击左下角缩略图 → 分享 → 选择"识图翻译"（Action Extension，以 modal sheet 形式叠在截图编辑器上）。
   - **入口 C**：直接打开本 App → 从相册选图 / 现场拍照。
2. 系统在 1~3 秒内返回**保留原版面布局的中文翻译图**。
3. 不同入口的能力边界：
   - **入口 A（Snippet）**：只支持「看翻译图 + 保存到相册 + 打开 App 看大图」三个动作，无复杂手势。
   - **入口 B / C（主 App）**：支持双指捏合放大、长按某段文字看原文、对照查看原图、加入历史。

## 三、iOS 平台限制（必须遵守，别白费力气）

- ❌ 不能后台监听其他 App 的截图事件。
- ❌ 不能跨 App 悬浮窗 / 实时盖在其他 App 界面上（这是安卓的能力，iOS 沙盒禁止）。
- ❌ Action Extension 拿不到系统截图缩略图的预编辑权限，只能在用户点"分享"后接管。
- ✅ Shortcuts + App Intents 是目前最接近"一键"的合规方案。
- ✅ ReplayKit 广播扩展可以做"屏幕录制 + 实时翻译"，但耗电严重且需要用户主动开启录屏，不放进 MVP。

## 四、技术架构

### 4.1 工程结构（Xcode）

```
SnapTranslate/                       # 主 App target（SwiftUI）
├── App/
│   ├── BacktapApp.swift             # @main 入口
│   └── AppIntents/                  # App Intents（让 Shortcuts 调用）
│       └── TranslateScreenshotIntent.swift
├── Features/
│   ├── Translate/
│   │   ├── TranslateView.swift      # 主翻译界面
│   │   ├── TranslateViewModel.swift
│   │   └── ResultImageView.swift    # 翻译后图片预览 + 缩放 + 长按看原文
│   ├── History/                     # 历史记录（本地 SwiftData）
│   └── Settings/                    # 目标语言、翻译引擎切换、隐私说明
├── Core/
│   ├── OCR/
│   │   └── VisionOCRService.swift   # Vision VNRecognizeTextRequest
│   ├── Translation/
│   │   ├── TranslationService.swift # 协议
│   │   ├── AppleTranslationService.swift  # 首选，免费
│   │   └── LLMTranslationService.swift    # 兜底，调 GPT-4o / Claude
│   ├── Rendering/
│   │   └── LayoutPreservingRenderer.swift # 核心：在原图上替换文字
│   └── ImageUtils/
│       └── BackgroundColorSampler.swift   # 估算文字框背景色
└── Resources/
```

### 4.2 关键技术栈

- **语言**：Swift 5.10+
- **UI**：SwiftUI（iOS 17+ 起步）
- **OCR**：`Vision` 框架的 `VNRecognizeTextRequest`，`recognitionLevel = .accurate`，开启 `usesLanguageCorrection`。
- **翻译**：
  - 主：`Translation` 框架（iOS 17.4+，免费、可离线）。
  - 备：调用 LLM API（用户在设置里填 API Key，仅用于 Apple 不支持或翻译质量差的语种）。
- **布局重绘**：`Core Graphics` + `UIGraphicsImageRenderer`。
- **持久化**：`SwiftData`（历史记录）+ `App Group` 让 Extension 共享数据。
- **快捷指令集成**：`AppIntents` 框架。

## 五、核心算法：保持布局的图片翻译

实现 `LayoutPreservingRenderer.render(originalImage:ocrResults:translations:) -> UIImage`：

```
1. 用 Vision OCR 拿到每段文字的 boundingBox（归一化坐标）、原文字符串、置信度。
2. 把相邻的、行高相近的、纵向距离很小的文字块**合并成段**（避免一个句子被切成多个小块翻译错）。
3. 对每段调用 TranslationService → 得到译文。
4. 对每段：
   a. 用 BackgroundColorSampler 在 boundingBox 四个边缘各采样几个像素，取**中位数颜色**作为背景色。
   b. 用该背景色在 boundingBox 区域画一个圆角矩形（盖掉原文）。
   c. 估算原文字号 ≈ boundingBox.height × 0.75。
   d. 用与原图前景对比度高的颜色（黑或白，看背景色亮度决定）绘制译文。
   e. 译文如果超出 boundingBox 宽度，**按比例缩小字号**直到放得下；如果还放不下，允许换行。
5. 输出新图像。
```

**踩坑提示**：
- Vision 返回的坐标系是左下原点 + 归一化，要转成 UIKit 的左上原点 + 像素坐标。
- 别忘了图片的 `imageOrientation`，截图通常是 `.up`，但相册导入的可能有旋转。
- 中文比英文更宽（一个汉字 ≈ 两个英文字符宽度），从英→中常常装不下，缩字号是常态。

## 六、Shortcuts 一键触发 + 半屏 Snippet 面板（核心体验）

让用户能用"操作按钮 / 背面双击 / 控制中心"一键翻译当前屏幕，**且不离开外文 App**——这是本 App 区别于其它翻译软件的关键体验。

### 6.1 实现

`TranslateScreenshotIntent` 让 `perform()` 返回一个 SwiftUI Snippet 视图，系统会自动把它叠在前台 App 上方：

```swift
struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译当前屏幕"
    static let description = IntentDescription("识别截图中的外文并以保留布局的方式翻译成中文")

    @Parameter(title: "截图") var image: IntentFile

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let translated = try await TranslationPipeline.shared.run(imageData: image.data)
        return .result(view: TranslationSnippetView(translated: translated))
    }
}
```

`TranslationSnippetView` 内容**严格保持简单**：
- 一张翻译后图片（`aspectFit`，避免被 sheet 容器裁切）
- "保存到相册"按钮
- "在 App 中打开看大图"按钮（用 `OpenIntent` 或 URL Scheme 跳主 App）

### 6.2 用户侧 Shortcut 配置

用户在 iOS"快捷指令"App 里建一个 Shortcut：
- 步骤 1：系统内置 Action「拍摄屏幕快照」
- 步骤 2：调用我们的 `TranslateScreenshotIntent`，传入上一步的截图
- **整个 Shortcut 不需要"显示结果"动作**——Snippet 由系统自动叠在前台 App 上。

然后把这个 Shortcut 绑到操作按钮 / 背面轻点 / 控制中心。

### 6.3 引导

**首次打开 App 时**用引导页教用户怎么配，并提供一个**预制 Shortcut 的 iCloud 链接**让用户一键导入。

### 6.4 SnippetView 必须绕开的坑

| 限制 | 应对 |
|------|------|
| Snippet 高度约半屏，宽度撑满，不可自定义 | 视图只放一张图 + 两个按钮，不堆复杂排版 |
| 系统容器会抢走多指、长按等手势 | 不在 Snippet 里做缩放 / 长按看原文，这些功能由"打开 App"按钮跳主 App 完成 |
| Intent `perform()` 30 秒超时 | OCR / 翻译都做超时 + 降级（LLM 失败 fallback 到 Apple Translation） |
| Extension 进程内存约 120 MB | 处理前先把截图 `downscale` 到屏幕分辨率，别直接喂 4K 原图给 Vision |
| Snippet 一次性快照，弹出后不能更新 | 必须算完才返回，不要做"先弹空面板再填充"的设计 |
| Apple Translation 首次使用要下载语种包 | 主 App 启动时预下载用户默认目标语言；Snippet 里检测到未下载时直接降级 LLM |

## 七、设置项（MVP）

- 目标语言（默认简体中文，可选英语、日语、韩语等）。
- 翻译引擎：Apple Translation（默认）/ 自定义 LLM（高级用户）。
- LLM 配置：API Key、模型名、Base URL（兼容 OpenAI 协议即可）。
- 是否保存历史记录、清空历史。
- 关于：版本、隐私政策（强调"图片不上传服务器，Apple 翻译离线，LLM 仅在用户开启时联网"）。

## 八、隐私与上架要点

- **明确告知**：默认走 Apple Translation，数据不出设备；只有用户主动切到 LLM 时才联网。
- Info.plist 配齐：`NSPhotoLibraryAddUsageDescription`（保存翻译结果）、`NSCameraUsageDescription`（如支持拍照）。
- Action Extension 的 `NSExtensionActivationRule` 严格限定为 `NSExtensionActivationSupportsImageWithMaxCount = 1`。
- App Tracking Transparency 不需要（我们不追踪）。
- App Store 描述里直接写明用途与隐私模型，避免审核拒。

## 九、MVP 不做的事（避免范围蔓延）

- ❌ 实时屏幕录制翻译（v2 再说）。
- ❌ 多人协作 / 云同步。
- ❌ 付费墙（先免费跑通体验，验证用户再说商业化）。
- ❌ 自定义术语库 / 翻译记忆。
- ❌ 文字朗读 / TTS。

## 十、开发顺序与验收

按顺序做，每步做完都要在真机或模拟器上跑通：

| 步骤 | 内容 | 验收 |
|------|------|------|
| 1 | 主 App 骨架 + 相册选图 | 选一张外文截图能显示在界面上 |
| 2 | 集成 Vision OCR | 选图后能在 Console 打印识别到的文字 + 边界框 |
| 3 | 集成 Apple Translation | OCR 结果能逐段翻译成中文 |
| 4 | 实现 LayoutPreservingRenderer | 屏幕上能看到译文盖在原文位置上，位置准、不溢出 |
| 5 | 增加 Action Extension | 系统截图 → 分享 → 选本 App → 拿到翻译图 |
| 6 | 增加 AppIntent | 在快捷指令 App 里能搜到"翻译截图"动作并运行 |
| 7 | 历史记录 + 设置页 | 翻译过的图能在列表里翻看 |
| 8 | LLM 兜底翻译 | 在设置里填 OpenAI / Claude Key，能切换并工作 |
| 9 | 引导页 + Shortcut 一键导入 | 新用户能在 60 秒内配好"操作按钮触发" |
| 9.5 | 在外文 App 里测 Snippet 体验 | 在 Safari 打开一个英文网页 → 按操作按钮 → 1~3 秒内半屏面板弹出译图 → 关闭后仍停留在 Safari，无任何"被切走"的感觉 |
| 10 | TestFlight + 上架材料 | 真机走通 3 个典型场景：游戏 / 海外购物 App / 工作软件 |

## 十一、给 AI 编程助手的执行规则

1. **先建 Xcode 工程**，再开始写代码。如果你（AI）不能直接建 .xcodeproj，列出需要我手动建的 target、Capability、Info.plist 配置，再写文件。
2. **每完成一个步骤（章节十的表格一行）就停下来**，让我在真机上验证，再继续下一步。
3. 遇到任何要花钱的服务（LLM API）默认**不调用**，先写好接口和占位，由我提供 Key。
4. **不要引入第三方库**除非 Apple 原生方案做不到。能用 Vision / Translation / SwiftUI / SwiftData 就不要引 Alamofire / SnapKit / RxSwift。
5. 所有面向用户的文案默认中文。
6. 写完一个文件就给我对应的文件路径和关键代码段说明，方便我 review。

---

**开始吧。先列出 Xcode 工程需要手动建的 target 和 Capability 清单，然后从步骤 1 开始。**
