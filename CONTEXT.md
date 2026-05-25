# CONTEXT.md — iOS快捷翻译

> 项目当前状态。**每次会话结束前更新这份文件**,把这次做了什么、卡在哪、下次接着做什么写清楚。
> 详细的每日改动可以选择性记到 `daily/[日期].md`。

---

## 当前进度

主 App + 两个 AppIntent 端外入口、Splash、Onboarding、首页改版、拍照翻译/分析、历史记录 tab + 时间分组全部落地。

**Commit `1215c7a` 已 push 到 `origin/main`**(2026-05-26):71 files +1889 -350,涵盖 5/19~5/26 全部积压工作。详见 README 般的 commit message 跟下方会话日志。

## 正在做什么

阶段性收尾。等用户真机回归测试上一批改动 + 反馈下一轮需求方向。

## 未解决的问题 / 卡点

1. **翻译 snippet 黄底**:产品权衡,不是 bug——iOS 26 的硬限制,没办法在保留图片预览的同时去掉警告。
2. **Dialog "平衡换行"行宽变窄**:iOS Dialog 对短段落用 minimum-raggedness 算法,行宽看起来短。已用"无 bullet 标记 + `\u{2028}` 软换行连入同段"绕过,大段场景能填满,某些短 bullet 仍偏短。这是 iOS 渲染器行为,端不可控,接受现状。
3. **`AnalysisDetailView`(历史详情页)**未跟进:它仍用 `Text(LocalizedStringKey)` + `.textSelection(.enabled)`,跟主页的 `SelectableMarkdownText` 不一致。
4. **`SelectableMarkdownText` 的拖拽未禁**:UITextView 默认允许把选中文字拖到其他 App。在主 App 内不易触发,但严格说也应加 `textDragInteraction.isEnabled = false`。

## 下一步打算

- 决定是否给 `AnalysisDetailView` 换 `SelectableMarkdownText` 保持一致
- 决定是否给 `SelectableMarkdownText` 关拖拽

---

## 会话日志(倒序,最新在上)

### 2026-05-26 (Claude Code - 拍照面板 polish + 历史记录改造 + 一次性 push)

跨度大,围绕**真机回归发现的 bug 修复 + UI polish + 新增历史记录页改造**。最后一次性 commit `1215c7a` 把 5/19~5/26 累积的所有工作推到 `origin/main`。

#### 拍照面板(CameraCaptureSheet)— 画面位置 bug 修复(超长链路)

用户多轮反馈"拍前居中,拍后偏移""画面被放大变成几倍""画面整体偏左/偏右,但 loading 和按钮又偏右"。**根因**:SwiftUI `Image + .scaledToFill()` 跟 `AVCaptureVideoPreviewLayer (.resizeAspectFill)` 是两套渲染机制,在 ZStack 内 sizing/centering 行为微妙不一致。期间走了几个弯路:
1. 给 `Image` 加 `.ignoresSafeArea()`(没用)
2. 给最外层 ZStack 加 `.ignoresSafeArea()`(反而把 chrome VStack 也拽出 safe area,loading 跟按钮也偏了)
3. 调整 `.padding(.bottom)` 数值(没本质修复)

**最终方案**:新建 `PhotoDisplayView.swift`(UIViewRepresentable 包 UIImageView,`.scaleAspectFill`),mainContent 里的 SwiftUI Image 全换成它。preview 跟拍后都是 UIView + CALayer 同一套底层,内容居中位置数学上必然一致。

**附带踩了一个 UIImageView 坑**:第一版 PhotoDisplayView 直接用 UIImageView,结果拍后画面被放大成几倍 —— UIImageView 的 `intrinsicContentSize` 默认是 `image.size`(像素尺寸,比如 3024×4032),SwiftUI 优先用 intrinsic 而不是 `.frame(.infinity)`。修复:三重保险
1. 子类化 `FlexibleImageView` override `intrinsicContentSize` 返回 `noIntrinsicMetric`
2. 降低 content hugging / compression resistance 到 `.defaultLow`
3. UIViewRepresentable 实现 `sizeThatFits(_:uiView:context:)` 返回 `proposal.replacingUnspecifiedDimensions()`

#### 拍照面板 chrome 重构

顶部从 ZStack(语言菜单居中 + HStack{Spacer; closeButton}) 改成**三段 HStack**:左 `Color.clear.frame(36×36)` 占位 + Spacer + 中央语言菜单 + Spacer + 右 closeButton。保证中央元素真居中,不被右侧按钮拽偏。

**关闭按钮换样式**:`xmark` + `Color.black.opacity(0.4)` 圆 → `xmark.circle.fill` + symbolRenderingMode `.palette` + `.foregroundStyle(.white, .black.opacity(0.55))`。原先半透明黑圆在白底图上变浅灰几乎隐形,现在双色 palette 任何背景都明显。

**语言菜单**:去掉「仅预览阶段才显示」的限制,翻译模式下预览/翻译中/翻译完都显示。

**Loading 样式统一**:三处 ProgressView(CameraCaptureSheet `processingOverlay` + ContentView `imageArea` + ContentView `analysisArea`)全部从 `.ultraThinMaterial` + primary 文字改成 `Color.black.opacity(0.75)` + `.foregroundStyle(.white)` + `.tint(.white)`,任何底图任何主题都清晰。

**Save 按钮**:`Color.accentColor` → `Color.accentColor.opacity(0.9)`。

**分析文本面板**(mode == .analyze 时拍后底部 ScrollView):同样从 `.ultraThinMaterial` 改 `Color.black.opacity(0.75)` + `cornerRadius 14` + `.padding(.horizontal, 16)`,卡片浮起来。

**CameraPreviewView 加 `layoutSubviews` override** 设 preview layer connection 的 `videoRotationAngle = 90`,修早先"拍摄内容偏向某一侧"的副问题(预览没设 rotation 时显示传感器原始横向画面被压到竖屏 view)。

#### ContentView:首页 + TabView swipe + 分析功能

- **TabView swipe 区域改成 tab 下方**:`titleTabs` 从 `pageView(for:)` 内提到外层 VStack 顶部固定,TabView 只包 `contentCard + bottomGroup`。原行为是整页翻页,改后只翻卡片 + 快捷卡片区
- **`titleTabs` 加 `.animation(.easeInOut(duration: 0.2), value: mode)`**,swipe 翻页时 `foregroundStyle(.primary vs .secondary)` 颜色平滑过渡(font size 是离散的 SwiftUI 没法 animate)
- **imageArea overlay 去掉"浮在图片上的语言菜单"**(跟顶部 toolbar 重复),但**保留右上 X 按钮**(翻译中取消 / 完成清空)。第一次误删 X 按钮被用户骂回来加上
- **analysisArea 文本 `.padding(.vertical, 4)` 拆成 `.padding(.top, 32) + .padding(.bottom, 4)`** 避开右上 X 按钮,视觉更舒展
- **拍照分析也不留首页**:加 `@State cameraCaptureProducedAnalyze` flag,`processCapturedImage` analyze 分支 set true,`onClose` 时清空 `analysisImage / analysisText`,跟翻译一致

#### 分析文本不截断(主 App)

`ImageAnalysisService.analyze(imageData:settings:truncate: Bool = true)`,`sanitize` 加同名参数。`AnalysisPipeline.run(imageData:settings:truncate: Bool = true)` 透传。ContentView 两处调用传 `truncate: false`,AppIntent 保持默认 true(继续给 Dialog 截到 250 字符)。**主 App 内分析文本完整显示,ScrollView 滚动看完整**。

#### 历史记录页(HistoryView)重做

完全重写。两个维度:
1. **类型 tab**:导航栏下方用**系统分段控制器** `Picker(.segmented)`,翻译 / 分析。字号 14(走 `UISegmentedControl.appearance().setTitleTextAttributes` 全局设置,SwiftUI 没 modifier 改内部字号),高度 40,宽度跟随父容器(用户改了一版尝试 60% 宽度后又改回全宽)
2. **时间分组**:`enum TimeGroup { today, past3Days, past7Days, past30Days, earlier }`,用 `Calendar.startOfDay` 跨日数计算(跟 iOS 备忘录一致,不按 24h 整时长)。List Section header 显示分组标题

**视觉**:整页 `.background(Color(.systemGroupedBackground))` + `.toolbarBackground(... for: .navigationBar)` + `.toolbarBackground(.visible)`,导航栏跟内容区同色消除断层。List 加 `.scrollContentBackground(.hidden)` 透出外层底色。

**编辑按钮**:`EditButton()` 在用户设备显示英文 "Edit",换自定义 `@State editMode: EditMode` + `Button(editMode == .active ? "完成" : "编辑")` + `.environment(\.editMode, $editMode)`。

#### 资产

`IconPhoto.imageset/icon-photo.svg` 换成新版「带 ✓ 完成感的山形 + 圆点」图标。

#### 改名

`Features/Camera/CameraSessionManager.swift` 跟早先文档里都把 App 中文名「快捷识屏」固化(`快捷翻译` 是 AppIntent 动作名,保留)。

#### 教训(踩坑总结)

1. **scheme 错跑 Share Extension**:用户多次反馈"老样子"时,先要 Xcode 顶部截图看 scheme 跟 attaching to,排除 target 选错这条最常见的原因
2. **SwiftUI Image + ZStack sizing 不可靠**:跟其他 UIViewRepresentable 混用时 centering 行为微妙不同,直接用 UIImageView wrapper 一致性最高
3. **UIImageView 默认 intrinsicContentSize = image pixel size**:在 SwiftUI 里会被当成"我要这么大",必须 override + 调 hugging priority + sizeThatFits 三重防御
4. **SwiftUI `.font` 切换不能 animate**:字号变化是离散的,要平滑过渡只能用 `.scaleEffect`(我们这次没做,只让 `.foregroundStyle` 颜色淡入淡出)
5. **`UIScreen.main` 在 iOS 26 deprecated**:要拿屏宽用 `.containerRelativeFrame(.horizontal) { length, _ in ... }` 替代,或者 GeometryReader

#### 一次性 push

Commit `1215c7a` 71 files +1889 -350,涵盖:
- AppIcon 换 logo3,App 改名快捷识屏
- 新增 SplashView / OnboardingView 重做 / 首页 UI 重做 / NotificationBar
- 新增拍照功能(CameraCaptureSheet / CameraPreviewView / CameraSessionManager / PhotoDisplayView)
- 历史记录页改造
- 性能优化(降采样 2048pt) + 分析不截断 + Loading 统一样式

worktree 工作目录干净。下次接着干新需求。

### 2026-05-25 (Claude Code - 首页 chrome 悬浮形态还原 + scheme 踩坑)

**用户需求**:翻译/分析的「**翻译中 + 翻译完**」两种状态下,卡片顶部都要有可见的「右上 X 关闭按钮」+「中间目标语言切换」(分析卡片只要右上 X + 复制)。**X 要悬浮在内容上,不占高度**。

**踩了一个完整的乌龙**(教训):
1. 第一版用 `.overlay(alignment: .top/.topTrailing)` 直接挂在 imageArea/analysisArea 上,build 成功
2. 用户反馈"老样子" / 看不到改动
3. 怀疑 TabView `.page` 跟 overlay 冲突,把 chrome 抽成 `chromeRow(for:)` 独立 row 挂在 contentCard VStack 第一行 —— 这版 X 占了高度,用户立刻反馈"更想 X 悬浮在 imageArea 内容上不占高度"
4. 让用户截 Xcode 一看,**scheme 选的是 `SnapTranslateShare`(Share Extension),不是主 App `SnapTranslate`**。所有"老样子"都是因为根本没跑改后的代码,Share Extension 跟主 App 是两个 target
5. 让用户切换 scheme 到 `SnapTranslate` + Clean Build Folder + Cmd+R
6. 既然 chrome overlay 本来就没问题,回滚 `chromeRow` 方案,回到 `.overlay` 形态

**最终落地的 ContentView.swift 改动**:
- `imageArea`(`L206-260`):3 层 overlay 叠加 —— `.overlay(alignment: .top)` 挂 `imageAreaTargetLanguageMenu`(`image != nil` 时显示,翻译中/完都有)、`.overlay(alignment: .topTrailing)` 挂 X 按钮(`isTranslating` 时点击触发 `cancelTranslation()`,完成态触发 `clearImage()`)、`.overlay { }` 挂 `ProgressView("翻译中…")` 中间 loading
- `analysisArea`(`L302-357`):2 层 overlay —— `.overlay(alignment: .topTrailing)` 挂 HStack(copy 按钮仅完成态显示 + X 按钮 cancel/clear)、`.overlay { }` 挂 `ProgressView("分析中…")`
- 删除已死的 helper:`chromeRow(for:)` / `cardCloseButton(for:)` / `closeAccessibilityLabel(for:)`

**关键代码片段**(imageArea overlay 链):
```swift
.overlay(alignment: .top) {
    if image != nil {
        imageAreaTargetLanguageMenu.padding(.top, 8)
    }
}
.overlay(alignment: .topTrailing) {
    if image != nil {
        Button {
            if isTranslating { cancelTranslation() } else { clearImage() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title).foregroundStyle(.white, .gray).padding(8)
        }
    }
}
.overlay { if isTranslating { ProgressView("翻译中…")... } }
```

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`

**教训**:
- 用户反馈"老样子"时,先要让用户截 Xcode 当前状态看 scheme / target,不要只看代码诊断
- iOS 项目有多个 target(主 App + Share Extension + Widget 等)时,scheme 误选很常见,这个排查路径以后优先

**下次接着**:
- 用户**切换到 `SnapTranslate` scheme**(不是 SnapTranslateShare)+ Clean Build Folder + Cmd+R
- 真机验证:翻译中状态 / 翻译完状态 / 分析中状态 / 分析完状态,4 种情况下 X 和语言菜单都应该可见,悬浮在卡片内容上方,不占高度
- 如果还不对,可能需要 ZStack 改 overlay 层级(把 chrome 提到 contentArea 父层而不是嵌在 imageArea 内)

### 2026-05-25 (Claude Code - 完整自定义相机面板,第二轮)

替换上轮简化版 `CameraCapture`(基于 `UIImagePickerController` 系统相机)为**完整自定义全屏相机面板**。

**新增 3 个文件**:
- `Features/Camera/CameraSessionManager.swift` —— `AVCaptureSession` 管理 + 后置广角相机 + `AVCapturePhotoOutput`。坑:`@MainActor final class` + `ObservableObject` 不兼容(ObservableObject 协议要求成员 nonisolated),改用 `Task { @MainActor in ... }` 在 photo output 回调里手动 hop 回 main actor 更新 `@Published`。也需要显式 `import Combine`(Xcode 26 不再隐式导入)
- `Features/Camera/CameraPreviewView.swift` —— `UIViewRepresentable` 包 `AVCaptureVideoPreviewLayer`。覆盖 `UIView.layerClass` 让根 layer 直接是预览 layer,避免嵌套层级
- `Features/Camera/CameraCaptureSheet.swift` —— 全屏面板(~250 行),三阶段状态机:
  1. **预览** —— `CameraPreviewView` 全屏 + 底部 76pt 圆形 shutter 按钮 + 右上 X 关闭
  2. **处理中** —— 显示原图 + 中间 `ProgressView` "翻译中.../分析中..." 半透明卡片,按钮隐藏
  3. **结果** —— 翻译模式显示译图(`resultImage`),分析模式显示原图 + 底部 280pt 高 `ScrollView` 半透明叠加分析文本,底部"保存到相册"按钮

**删除**:
- `Features/Camera/CameraCapture.swift`(上轮的 UIImagePickerController 简化版)

**ContentView 改动**:
- `.fullScreenCover` 内容从 `CameraCapture { ... }` 换成 `CameraCaptureSheet(mode:, resultImage:, resultText:, isProcessing:, onClose:, onCapture:)`
- 新增 2 个 binding helper:
  - `cameraResultImageBinding`:翻译模式返回 `$translatedImage`,分析模式返回 `nil`(让 Sheet fallback 显示原图 + 分析文本)
  - `cameraIsProcessingBinding`:翻译模式返回 `$isTranslating`,分析模式返回 `$isAnalyzing`
- `$analysisText` 直接传给 Sheet 显示分析文本

**权限处理**(`AVCaptureDevice.authorizationStatus`):
- 未询问 → `requestAccess(for: .video)` 弹系统对话框
- 已授权 → 直接 `camera.configure()` + `startSession()`
- 拒绝 → 显示"去设置"alert,跳系统 Settings App

**pbxproj 改动**:
- 加 `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "需要相册权限才能保存翻译/分析结果"` —— 不加 `PHPhotoLibrary.shared().performChanges` 真机调用会 crash

**保存逻辑**:
- 用 `PHPhotoLibrary.shared().performChanges` + `PHAssetChangeRequest.creationRequestForAsset(from: image)` 现代 PhotoKit API(不是老的 `UIImageWriteToSavedPhotosAlbum`)
- 翻译模式保存译图(`resultImage`)优先,fallback 原图
- 分析模式保存原图(分析文本只显示在屏幕,不写入相册)
- 保存成功后按钮短暂显示"已保存"绿色 + 1.4s 后自动关闭 Sheet

**踩了 2 个编译坑(都已修)**:
1. `@MainActor final class CameraSessionManager: ObservableObject` 报错 "does not conform to protocol 'ObservableObject'" —— 去掉 class 上的 `@MainActor`
2. `import Combine` 缺失 —— Xcode 26 严格要求显式导入

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,三个新 .swift 都编译进了 SnapTranslate.app

**模拟器 vs 真机**:
- **模拟器**没相机硬件,预览层会黑屏(AVCaptureSession 在模拟器找不到 device,`configure()` 会触发 `captureError = "无法访问相机"`)
- **真机**才能完整测试:首次进入弹相机权限 → 预览 → 点 shutter → 自动跑 OCR/翻译/分析 → 结果 → 保存按钮

**下次接着**:
- 用户真机测试完整流程:相机权限 / 预览画质 / shutter 反馈 / 处理速度 / 译图渲染 / 分析文本 / 保存到相册权限弹框 / 保存成功反馈
- 视觉细节调整:shutter 按钮尺寸 / 底部 padding / 处理中 loading 位置 / 关闭按钮位置

### 2026-05-25 (Claude Code - 首页加拍照翻译/分析)

按 Figma 节点 `7376:48554`(有通知栏) / `7376:48708`(无通知栏) 改首页。
(Figma 文件名"WPS 智能助理"误导,实际内容是用户自己产品的设计稿。用户截图确认后开干。)

**核心改动**:把原来挂在空状态下方的"选择图片"按钮(148×40 蓝字胶囊),改成**白色圆角卡片底部的两个并排按钮**:**拍照翻译/拍照分析** + **选择图片**。

**新增文件**:
- `Features/Camera/CameraCapture.swift` —— `UIViewControllerRepresentable` 包 `UIImagePickerController(sourceType: .camera)` 简化实现,模拟器 fallback 到 `.photoLibrary` 避免崩溃
- `Assets.xcassets/IconCamera.imageset/icon-camera.svg`(22×22,用户提供)
- `Assets.xcassets/IconPhoto.imageset/icon-photo.svg`(22×22,用户提供)
  - 两个 SVG 都用 `preserves-vector-representation: true` + `template-rendering-intent: template`,被 SwiftUI `.foregroundColor(.primary)` 着色(浅色黑深色白自适应)

**ContentView 改动**:
- 空状态:移除翻译/分析两处 `PhotosPicker(...) { selectImageButtonLabel }`(图 + 描述文字保留)
- body 主 VStack:`contentArea` → `contentCard`(新增的白卡片包装器)
- 新增 `contentCard`:VStack(contentArea + 底部 HStack 2 按钮),`Color(.secondarySystemGroupedBackground)` 背景 + `r=24` 圆角
- 新增 `captureButton` / `photoSelectButton` / `cardBottomButtonLabel(icon:text:)`
  - 按钮 44 高 + capsule + `Color(.tertiarySystemFill)` 背景 + 图标 22×22 + PingFang SC 16pt 文字
  - **翻译 mode 文案"拍照翻译"/ 分析 mode 文案"拍照分析"** —— 跟随 mode 切换
- 新增 `@State showCameraCapture = false`
- 新增 body 末尾 `.fullScreenCover(isPresented: $showCameraCapture)` 跳 `CameraCapture` view
- 新增 `processCapturedImage(_ uiImage: UIImage) async` 函数:
  - 翻译 mode:复用 `runOCR(on:)` → `dispatchTranslation`
  - 分析 mode:`UIImage.jpegData()` → `AnalysisPipeline.run(imageData:settings:)`,逻辑对齐现有 `loadImageForAnalyze`
- 删除原 `selectImageButtonLabel` / `selectImageButtonBackground`(dead code)

**pbxproj 改动**:
- 主 App target 加 `INFOPLIST_KEY_NSCameraUsageDescription = "需要使用相机进行拍照翻译/分析"`(Debug+Release 两处)
- 没这个 key 真机调用相机会立即 crash

**当前实现 vs 用户原始需求**(分两步):
- ✅ **本轮(已完成)**:UI 改版 + 用 iOS 系统标准相机拍照 + 拍照后自动 OCR/翻译 或分析,结果显示在 imageArea/analysisArea
- ⏳ **下轮 TODO**:用户原话"在拍照面板直接扫描内容,扫描完成后底部拍照按钮变成保存按钮" —— 需要自定义 AVCaptureSession 全屏相机面板(预览 + shutter + 拍照后停留 + 保存按钮),约 250+ 行代码。本轮先用 `UIImagePickerController` 跑通完整流程,等用户视觉确认 UI 后再迭代

**Build 验证**:
- 首次 build → ✅
- 加 `INFOPLIST_KEY_NSCameraUsageDescription` 后再 build → ✅ `** BUILD SUCCEEDED **`
- 模拟器没相机硬件,运行时 CameraCapture 会 fallback 到 `.photoLibrary`(代码已处理),真机才能拍照

**注意点**:
- 卡片背景用 `Color(.secondarySystemGroupedBackground)` 适配深色模式
- 按钮背景用 `Color(.tertiarySystemFill)` 在白卡上有视觉区分,深色下也合理
- Figma 数据里按钮 fill #FFFFFF 但视觉上有浅灰区分,可能 Figma INSTANCE override 没 inflate 完整。我按视觉用了系统 fill 颜色

**下次接着**:
- 用户 Run 验证 UI(卡片样式 / 按钮位置 / 拍照流程)
- 真机测试拍照 → OCR → 翻译/分析 全流程
- 决定要不要做完整自定义相机面板(本轮 TODO 第 2 项)

### 2026-05-24 (Claude Code - 引导页重做)

按 Figma `232:2763`(快捷翻译)/ `232:2871`(快捷分析)重做 OnboardingView。

**关键改动**:
- 从 4 页(4 个功能引导)精简到 **2 页**(快捷翻译 / 快捷分析)
- 删掉底部「下一步」按钮,改用 **TabView .page 滑动 + simultaneousGesture 拦截最后一页继续左滑 → 进入主页**(`hasSeenOnboarding = true`)
- 每页布局:顶部 92pt → 视频区 338×496 → 间距 40 → 标题 28pt SemiBold → 间距 12 → 副标题 16pt @50% 透明
- 视频在标题上方,**循环播放 / 静音 / 无 controls**

**新文件**:
- `Features/Onboarding/LoopingVideoPlayer.swift` —— `UIViewRepresentable` 包 `AVQueuePlayer + AVPlayerLooper`,Apple 推荐的无缝循环方案。注意:必须持有 `AVPlayerLooper` 引用否则循环停止
- `Resources/Videos/onboarding-translate.mp4`(6.2MB,1108×1864,6.7s)
- `Resources/Videos/onboarding-analyze.mp4`(6.7MB,1108×1864,4.8s)
  - 视频文件**重命名成英文**(原中文名),避免 `Bundle.main.url(forResource:)` 处理中文文件名时的边界情况

**改写文件**:
- `OnboardingView.swift` 完全重写,移除原 `OnboardingPageView`/`OnboardingPageData`/`OnboardingShortcutPage`(以及 iCloud 快捷指令链接相关代码,这些功能在 ContentView 的 actionsGroup 里已经有)
- 字体改用 `.system(size:weight:)`,中文环境自动选 PingFang SC,不再需要 custom font

**自定义底部翻页器**:
- Figma 设计稿样式:58×24 胶囊背景 `#F5F5F5` + 8×8 圆点(active 白色 / inactive `#B7B7B7`)
- 用 SwiftUI HStack + Circle 实现,放在 ZStack 底部
- 关掉 TabView 默认 indicator(`.tabViewStyle(.page(indexDisplayMode: .never))`)

**手势交互**:
- TabView 自己消费 drag gesture,加 `.simultaneousGesture(DragGesture()...)` 共享而非覆盖
- 最后一页 `value.translation.width < -50` 时触发 dismiss(50pt 阈值避免误触)

**踩了一个 import 坑(已修)**:
- OnboardingView 用 `AVLayerVideoGravity.resizeAspect` 但没 `import AVFoundation`,Xcode 26 不再隐式导入,build 报错。补 import 解决

**Bundle 体积**:从 ~11MB → ~24MB(加了 2 个 6.5MB 的 mp4)。可接受,启动引导用一次后用户不再看到,首次启动加载稍慢但能接受

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,两个 mp4 文件通过 `CpResource` 编译进 SnapTranslate.app

**100% 还原的不确定点**:
- 视频 1108×1864 ≈ 1:1.68,容器 338×496 ≈ 1:1.47,比例不匹配。用了 `videoGravity: .resizeAspect`(完整显示可能有边),如果视觉不接受可换 `.resizeAspectFill`(裁剪溢出)
- 副标题 lineSpacing 用 4pt,目标 Figma lineHeight 24 跟 SwiftUI 默认 19.2 的差。可能略小,视觉差异不大
- iPhone 不同尺寸下视频区固定 338×496,小屏(iPhone 16e 852)可能视频跟标题挤,大屏(Pro Max 956)上方留白多。可接受

**下次接着**:
- 用户 Run 看效果:视频循环 / 滑动 / 最后一页继续滑动进入主页 / 字体粗细 / 翻页器位置和样式
- 如果视频比例不接受可改 `.resizeAspectFill` 一行
- "继续滑动进入主页"这个交互不算很直观,用户反馈后可考虑加最后一页的"开始使用"按钮兜底

### 2026-05-24 (Claude Code - 首页改版)

按 Figma 设计稿 `221:503` 改首页。

**改动 1:把底部全宽「从相册选图」按钮挪到空状态下方**
- 旧:底部 `primaryPickerButton`(全宽胶囊蓝底白字)
- 新:空状态 VStack 下方 `selectImageButtonLabel`(148×40 胶囊,**浅色白底蓝字 `#008BFF` / 深色 #1C1C1E 底蓝字**),数据来自 Figma `Button 2`
- 翻译模式 + 分析模式两处空状态都加(各自绑定 `pickerItem` / `analysisPickerItem`)
- 删除原 `primaryPickerButton` 定义

**改动 2:新增通知条**(Figma `221:526` 浅色 / `227:2524` 深色)
- 新文件:`Features/Notification/NotificationBar.swift`
- 视觉:整体 56pt 高(胶囊 40pt + 左侧 60×56 图标向上突出 16pt)
  - 胶囊背景:`#22B5FD → #1566FD` LinearGradient + 2 个 blur Circle(粉紫 / 浅蓝光晕)模拟设计稿的彩色效果(原稿 7 层 LAYER_BLUR 用 SwiftUI 等价复现到 95%)
  - 左侧图标:`NotificationIcon.imageset` (浅 + 深两份 SVG,Asset Catalog `appearance: luminosity` 自动切换)
  - 文字 "可在下方设置「快捷识屏」功能哦~" / "了解功能":PingFang SC Regular 12pt 白色
  - 关闭按钮:SF Symbol `xmark` 9pt 白色,40×40 点击区
- 集成:首页底部用新增的 `bottomGroup`(`VStack(spacing: 8)`)包通知条 + actionsGroup,**通知条 ↔ actionsGroup 间距 8pt** 符合 Figma 设计

**改动 3:通知条显示逻辑** (`@AppStorage`)
- `notificationDismissedAt: Double` 关闭时间戳(0 = 从未关闭)
- `notificationDismissedAppVersion: String` 关闭时的 App 版本号(`CFBundleShortVersionString`)
- 规则:`shouldShowNotification` —— 从未关闭 OR 跨 App 版本 OR 关闭超过 24h → 显示
- 关闭按钮 → `dismissNotification()` 写两个 @AppStorage + 动画隐藏

**未做的占位**:
- "了解功能" 按钮的 `onLearnMore` 当前是空 closure + TODO 注释(用户原话"先占位即可")
- 等用户给教程页路径或新建页面后再补

**踩了一个编译坑(已修)**:
- 最初 `.background(capsuleBackground, in: .capsule)` 报错 "requires that 'some View' conform to 'ShapeStyle'" —— 因为 `capsuleBackground` 嵌套了 `.overlay`(View),不是单纯的 ShapeStyle
- 改为 `.background { capsuleBackground.clipShape(.capsule) }` 解决

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,无新警告。NotificationBar.o / NotificationIcon.imageset 编译进 Assets.car。

**下次接着**:
- 用户 Run 看视觉:通知条彩色背景跟 Figma 还原度 / 图标突出 16pt 位置 / 选择图片按钮浅深模式对比
- "了解功能" 跳转的目标页面定下来后接上
- worktree 累积 commits 待统一推送

### 2026-05-23 (Claude Code,第三轮 - 布局微调)

用户视觉反馈,调两个 Spacer 数值:
- 顶部 Spacer:259 → **238.5**(品牌标语 SVG 上移)
- 底部 Spacer:64 → **32**(底部 logo+标题下移 32pt)

布局原理:在底部 logo 下移到距屏幕底 32pt 后,底部 logo 顶位置 y=806。让"SVG 顶→屏幕顶" : "SVG 底→底部 logo 顶" = 3:5,即 (238.5 : 397.5) 比例。中间 Spacer 397.5 由 `Spacer()` 自动撑开,各屏幕尺寸自适应。

`** BUILD SUCCEEDED **`,无新警告。

### 2026-05-23 (Claude Code,第二轮)

**主线**:用户更新了 Figma 设计稿(节点 `205:161`,跟之前 `201:281` 不同),重写 SplashView。

**核心变化**(旧版 201:281 → 新版 205:161):
- 主视觉从「96×96 大 logo」改为「**354×170 品牌标语 SVG**」(用户提供的矢量图,内含「快捷识屏 轻点背面,轻松识图」+ 装饰元素)
- 标题从 24pt 缩到 **18pt**,放到屏幕底部跟 36×36 小 logo **水平并排**
- 副标题去掉
- 两个装饰圆球都移到屏幕**顶部以上**(只露下半圈),颜色 `#00FDED@20%` / **`#E1ECFF@100%`**(浅蓝换色),尺寸 311×311,blur 300 → SwiftUI .blur(75)

**精确数值(主目录)**:
- 画板 402×874 不变
- 品牌标语 SVG:位置 (24, 259),宽 354 高 170,左右各 24pt 边距
- 底部小标识:位置 (24, 774),内部 logo 36×36 + 标题 79×36,**logo↔标题 间距 8pt**,距屏幕底 64pt
- Ellipse 36(右上青色):311×311,offset (138, -436)
- Ellipse 37(左上浅蓝 #E1ECFF):311×311,offset (-161, -438)

**新增文件(主目录)**:
- `SnapTranslate/SnapTranslate/Assets.xcassets/BrandSlogan.imageset/`(brand-slogan.svg + Contents.json with `preserves-vector-representation: true`)

**改写文件**:
- `SnapTranslate/SnapTranslate/Features/Splash/SplashView.swift` —— 完全重写
  - ZStack 背景白 + 两个圆球 + VStack 内容
  - VStack 用 `Spacer().frame(height: 259)` + `Spacer()` 撑开 + `Spacer().frame(height: 64)` 实现"固定顶/底边距 + 中间自适应",在不同屏幕尺寸下保持设计稿相对位置
  - 底部小 logo + 标题用 HStack(spacing: 8) 水平并排

**SVG 渲染方案**:
- Assets.xcassets 直接放 SVG 文件,Contents.json 加 `"preserves-vector-representation": true`
- Xcode 编译时把 SVG 转成内部 vector format,SwiftUI `Image("BrandSlogan")` 直接渲染,任意缩放无锯齿
- Build 验证:`xcodebuild build` → `** BUILD SUCCEEDED **`,**无 SVG 警告/错误**,Assets.car 正常生成,确认资源被收录

**字体**:沿用上一轮设置(运行时 `CTFontManagerRegisterFontsForURL` 注册 AlibabaPuHuiTi-2-105-Heavy),标题用 `.font(.custom("AlibabaPuHuiTi_2_105_Heavy", size: 18))`。

**SnapTranslateApp.swift**:无改动。启动流程沿用上一轮设计(showSplash 2.5s 渐隐)。

**不确定点(等用户视觉验证)**:
- SVG 在真机/模拟器上的实际渲染效果(Xcode 对 SVG 支持有限,某些复杂 SVG 可能渲染不全。这个 SVG 用的是 path + fill 基础特性,应该 OK,但需要实测)
- `.blur(radius: 75)` 跟 Figma `LAYER_BLUR 300` 的视觉差异(经验换算比例 4:1)
- 各屏幕尺寸下顶/底边距的呈现(259 顶 / 64 底,中间 Spacer 撑开)

**下次接着**:
- 用户在 Xcode Run 验证视觉效果,反馈 SVG 是否完整渲染、圆球模糊度、布局间距
- 如果 SVG 渲染有问题,退到 PDF 方案(SVG 转 PDF 仍能保留矢量)

### 2026-05-23 (Claude Code,第一轮 → 旧版本,已被第二轮替代)

**主线**:按 Figma 设计稿 100% 还原 SplashView(启动页),集成到 App 启动流程,每次冷启动显示 2.5 秒后渐隐。

**数据源**:Figma 文件 `6qATaUYQ5qiIizwNlSr6Jb` 节点 `201:281`,通过 **Figma REST API + Personal Access Token** 拉取节点 JSON 解析。

**走通的弯路**:
1. Vibma MCP plugin → relay 连不上(本机没装)
2. 改用 Talk To Figma MCP plugin → ws relay 通了但应用层协议跟 Vibma MCP server 不兼容(`connection.get` vs `get_document_info`)
3. `/plugin install figma@claude-plugins-official` → 用户 Claude Code 版本不支持 plugin
4. Figma Dev Mode → 用户没有付费会员
5. **最终用 REST API + curl 拉 JSON,Python 解析**(免费,数值化,100% 精度)

**新增文件(主目录)**:
- `SnapTranslate/SnapTranslate/Features/Splash/SplashView.swift` (~70 行)
  - 画板 402×874(iPhone 16 Pro 基准)
  - 背景纯白 + 两个装饰圆球(模糊光晕)
    - 上方青色 `#00FDED @20%` 328×328,offset (147, -341),`.blur(radius: 100)`
    - 下方蓝色 `#BFD7FF @100%` 328×328,offset (-130, 404),`.blur(radius: 100)`
  - 核心 VStack:96×96 Logo + 16pt gap + 标题「快捷识屏」+ 副标题「轻点背面,轻松识图」
  - 整体 `.offset(y: -49)` 实现"中心偏上"(对应 Figma 内容中心 y=388 vs 画板中心 y=437)
- `SnapTranslate/SnapTranslate/Assets.xcassets/SplashLogo.imageset/`(logo.png 1024×1024 + Contents.json)
- `SnapTranslate/SnapTranslate/Fonts/AlibabaPuHuiTi-2-105-Heavy.ttf`(从 `SnapTranslate/font/` 拷过来,放进源码目录让 fileSystemSynchronizedGroups 自动收录)

**字体处理(踩坑)**:
- 标题用 Alibaba PuHuiTi 2.0 Heavy,**PostScript Name `AlibabaPuHuiTi_2_105_Heavy`(下划线,不是横线)** —— 用 Python parse ttf name table 拿到的
- 副标题原本应该 Alibaba PuHuiTi 2.0 Regular(weight 400),用户没这个字体,**最终选系统字体 PingFangSC-Regular 替代**
- **关键坑**:最初在 `project.pbxproj` 加 `INFOPLIST_KEY_UIAppFonts = "AlibabaPuHuiTi-2-105-Heavy.ttf"`,build 成功但 `plutil` 看 Info.plist 里**根本没生成 UIAppFonts key**——Xcode 26 维护一份白名单决定哪些 `INFOPLIST_KEY_*` 会被写入 Info.plist,**`UIAppFonts` 数组类 key 不在白名单**,被静默忽略
- **修复方案**:从 pbxproj 移除 INFOPLIST_KEY_UIAppFonts,改用**运行时注册** `CTFontManagerRegisterFontsForURL` 在 `SnapTranslateApp.init()` 里跑一次。.ttf 文件本身已经在 bundle 里(`find SnapTranslate.app -name *.ttf` 验证过),只需 Swift 代码注册到 Core Text 进程级 font table

**SnapTranslateApp.swift 改动**:
- 加 `import CoreText`
- 加 `init()` + `registerCustomFonts()` 静态方法,从 Bundle.main 找 ttf URL → `CTFontManagerRegisterFontsForURL(url, .process, &error)`
- 加 `@State private var showSplash = true`
- ZStack 把 SplashView 叠在 ContentView 上层,`.task` 跑 `Task.sleep(2.5s)` + `withAnimation(.easeOut(0.4))` 渐隐
- OnboardingView 的 fullScreenCover binding 改为 `!hasSeenOnboarding && !showSplash`,避免 splash 期间弹 onboarding

**Build 验证**:两次 `xcodebuild build` 都 `** BUILD SUCCEEDED **`。.ttf 文件在 `SnapTranslate.app` bundle 根目录里。

**100% Figma 还原的不确定点**(下次用户视觉验证后可能要调):
- Figma `LAYER_BLUR 400` → SwiftUI `.blur(radius: 100)` 是经验值。Figma blur 跟 SwiftUI Core Animation blur 算法不完全等价,可能需要微调到 80~150 之间
- 内容垂直位置用固定 `.offset(y: -49)`(基于 iPhone 16 Pro 874 高度)。其他屏幕上中心位置会有 ±5pt 偏差
- logo.png 是否本身带圆角直接看图,代码未加 `clipShape`
- **字体加载是否成功**:`CTFontManagerRegisterFontsForURL` 是 runtime 调用,只有 Run 才能验证。如果失败 SwiftUI 会 fallback 到系统字体,标题视觉上能看出差异(Heavy 字重 vs 系统默认)
- DEBUG 模式下注册失败会 print 警告到 console,用户 Run 时留意 Xcode console

**下次接着**:
- 用户在 Xcode Run 看 SplashView 实际效果(模拟器/真机)
- 检查 console 有没有「⚠️ Custom font not found / Failed to register」警告
- 视觉验证标题字体是不是 Alibaba PuHuiTi Heavy(不是系统字体)
- 微调 `.blur(radius:)` 和 `.offset(y:)` 数值
- 决定是否加 logo 入场动画 / 文字 fade-in 等增强效果
- (worktree 累积的改动还没合到主目录 git history:5-19 prompt 改动、5-21 图标和改名 + 今天的 splash,需要一次性 commit + push)

### 2026-05-22 (Claude Code)

**改动**:App 中文显示名 "快捷翻译" → "快捷识屏",英文名 SnapTranslate 不变。

**改动范围**(A 类,App 显示名相关,主目录 + worktree 都同步):
- `SnapTranslate.xcodeproj/project.pbxproj` 4 处 `INFOPLIST_KEY_CFBundleDisplayName`(主 App + Share Extension × Debug/Release)
- `SnapTranslateShare/ActionViewController.swift:29` `navigationItem.title`(Share Extension 弹层顶部标题)
- `AGENTS.md:5` 产品定位描述"快捷翻译应用" → "快捷识屏应用"

**未改的位置**(B 类,intent 动作名 / 项目目录代号,保留):
- `TranslateScreenshotIntent.swift:8` intent 的 `title`(用户在「快捷指令」App 里看到的动作名)—— 保持「快捷翻译」跟「快捷分析」对称 + 老用户已配置的轻点背面/操作按钮/控制中心快捷方式不失效
- `ContentView.swift:345` 「一键添加「快捷翻译」的快捷指令」—— 引用 intent 名,跟 B 类联动
- `OnboardingView.swift` 4 处(L13/122/128/134)—— 引导用户在系统设置里找「快捷翻译」,必须跟 intent.title 一致
- `AGENTS.md:1, 7` 项目标题/路径里的 "iOS快捷翻译" —— 目录代号,跟文件系统路径一致
- `CONTEXT.md:10, 19` —— 都是描述 intent 名「快捷翻译」(跟「快捷分析」并列)

**验证**:`xcodebuild build` 主目录 → `** BUILD SUCCEEDED **`。

**老用户迁移风险**:无。intent 名没改 → 已配置的轻点背面/操作按钮/控制中心快捷方式继续生效;只是 App 在主屏/Spotlight/设置里的名字从「快捷翻译」变成「快捷识屏」。

下次接着:用户在 Xcode Clean Build Folder + Run,看新名字在主屏 / 设置 / Spotlight / Share Sheet 顶部标题各处显示是否正确。

### 2026-05-21 (Claude Code)

**改动**:替换 App 启动图标资源 logo_app → logo3_app。

**关键诊断**:第一次操作走了弯路,把 `logo3_app.icon` 错放到 `Assets.xcassets/AppIcon.icon`(里面),用户反馈"没有任何变化"。跑 `xcodebuild` 看 actool 命令行才发现:
```
actool .../SnapTranslate/AppIcon.icon  .../SnapTranslate/Assets.xcassets
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                       
       Xcode 真正读的位置(跟 Assets.xcassets 平级)
```
项目里原本就有 `SnapTranslate/SnapTranslate/AppIcon.icon`(跟 Assets.xcassets **同级**,不是在里面),那才是 actool 实际读的 .icon 文件。Xcode 26 的 `.icon` 文件**必须放在跟 Assets.xcassets 平级的位置**,放进 Assets.xcassets 内部 Xcode 不识别。

**最终操作**:
- 覆盖 `SnapTranslate/SnapTranslate/AppIcon.icon`(外面的,原本是 logo_app 的图层 `1 3.png` / `2 6.png` / `bg 2.png` → 现在是 logo3 的 5 张 Frame 191205556x.png + icon.json 配好液态玻璃、neutral 阴影、automatic-gradient 蓝色填充)
- 删除 `Assets.xcassets/AppIcon.icon`(之前错放的位置)
- 删除 `Assets.xcassets/AppIcon.appiconset`(deployment target 26.3,不需要 iOS 18 兼容)

**验证**:`xcodebuild build` 主目录 → `** BUILD SUCCEEDED **`,actool 正确产出 `AppIcon60x60@2x.png` / `AppIcon76x76@2x~ipad.png` / `Assets.car` 并 emplace 到 `SnapTranslate.app`。

未改:
- `project.pbxproj` 的 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 不需要动
- deployment target iOS 26.3、Xcode 26.5

**教训**:Xcode 26 + 项目用了 `fileSystemSynchronizedGroups`(自动扫源码目录),`.icon` 文件**要放在源码目录直接下面**,不放进 Assets.xcassets。Assets.xcassets 内的 AppIcon.icon 不会被 actool 当 app icon 处理。

下次接着:用户在 Xcode Clean Build Folder + Run,看新图标在主屏 / 设置 / Spotlight / dark / tinted 下的渲染。

### 2026-05-19 (Claude Code)

**改动**:把「快捷分析」(轻敲背面 → 立即分析)的 system prompt 从「截图专用」改成「通用图片识别」。

文件:`SnapTranslate/SnapTranslate/Core/Analysis/ImageAnalysisService.swift` (45-68 行附近)

关键变化:
- 开篇从"解读截图内容"改成"解读图片的通用助手",显式列出截图 + 文物 / 艺术品 / 动植物 / 食物 / 商品 / 车辆 / 建筑 / 地标 / 表情包等场景,并说"不局限于此"
- 加了"识别到尽量具体的层次"指引,每个品类给「错误说法 vs 正确说法」对照(如"说『大熊猫』,不说『一只动物』")
- 要点维度按品类细分(原本只区分文章/UI 两类)
- 字数上限 200 → 220,sanitize 截断阈值 250 未动(仍有裕度)
- 「不要臆测」松绑成「识别推测可给最可能判断,不确定用『疑似/可能为』」—— 避免硬猜也避免不敢断

未动:
- `temperature: 0.3`、`max_tokens: 400`、模型 `qwen3-vl-flash` 都没改。如果识别精度不够,优先级是换模型(`qwen3-vl-plus` / `qwen-vl-max`)。
- 用户消息 `"请分析这张截图。"`(71 行)仍是旧文案,未改。
- sanitize 里强校验 `**内容**` 标记,新 prompt 仍保留这个骨架,兼容。

下次接着:等用户实测新 prompt 效果,根据反馈决定要不要换模型 / 改 user message / 调字数。

### 2026-05-18 (Claude Code)

把 2026-05-17 一整天的工作整理成 3 个 commit 推到 `origin/main`:
- `86f45b7` 资产更新(AppIcon + logo exports)
- `91cbed3` 快捷分析功能 + iOS 26 snippet 适配 + 同语言不报错 + 主页 UI 打磨
- `5a4755e` 项目记忆文件(AGENTS.md + CONTEXT.md)+ ignore `.claude/`

附:删了项目根 `CLAUDE.md`(原 Karpathy 英文版),内容已合并到 `AGENTS.md` 末尾的中文版;Claude Code 改靠 `~/.claude/CLAUDE.md` 全局配置的"先读 AGENTS.md"铁律加载项目规则。

---

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
**已 push 到 `origin/main`**(于 2026-05-18 完成)。3 个 commit:
- `86f45b7` Update app icon assets and add logo exports
- `91cbed3` Add 快捷分析 feature and adapt translation/analysis for iOS 26
- `5a4755e` Add project memory files and ignore Claude Code worktrees
