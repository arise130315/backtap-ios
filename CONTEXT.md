# CONTEXT.md — iOS快捷翻译

> 项目当前状态。**每次会话结束前更新这份文件**,把这次做了什么、卡在哪、下次接着做什么写清楚。
> 详细的每日改动可以选择性记到 `daily/[日期].md`。

---

## 当前进度

主 App + 两个 AppIntent 端外入口、Splash、Onboarding、首页改版、拍照翻译/分析、历史记录 tab + 时间分组全部落地。

**Commit `1215c7a` 已 push 到 `origin/main`**(2026-05-26):71 files +1889 -350,涵盖 5/19~5/26 全部积压工作。详见 README 般的 commit message 跟下方会话日志。

**新增改动(2026-05-26 下午,未 commit)**:CameraCaptureSheet 支持横屏拍摄,修复"横拿手机拍横向显示器,翻译被竖排"问题。

**新增改动(2026-05-26 晚上,未 commit)**:SplashView 适配暗色模式 —— 文字 SVG 提供 dark 版本,背景纯黑,左上光晕换品牌绿。

**新增改动(2026-05-27,未 commit)**:首页两个 tab 的空状态在 img_none 下方各加一句场景文案,降低用户首次认知成本。

**新增改动(2026-05-27,未 commit)**:新增 `SnapTranslateAppShortcuts`(AppShortcutsProvider),把两个 Intent 注册到系统级,用户无需 iCloud 链接也能在快捷指令/Spotlight/Siri 里发现「快捷翻译」「快捷分析」动作。

**新增改动(2026-05-27,未 commit)**:两个 Intent 的 `image` 参数改 Optional + 友好错误引导。修掉用户在快捷指令 App 内直接点动作卡片时看到的冷冰冰"无法解析图片"系统错误,替代为引导回主 App 一键导入完整流程的中文文案。

**新增改动(2026-05-27,未 commit)**:新增 `BackTapTutorialSheet`,把首页「轻点背面 → 绑定」按钮从"跳本 App 设置页(没用)"改成"弹出 3 步图文教学 sheet"。视频占位待真机录制后替换。

**新增改动(2026-05-27,未 commit)**:用户在快捷指令 App 内把两条 Shortcut 改名「翻译截图」→「识屏翻译」、「分析截图」→「识屏分析」并重新分享,`ContentView.swift:94-95` 的两个 iCloud Shortcut URL 已同步更新为新链接。

**Commit `441caeb` 已 push**(2026-05-27 晚):横屏拍摄+Splash 暗色+空状态文案+AppShortcuts+Intent 缺图引导+教学 sheet+Shortcut URL 更新,17 files +1268 -153。

---

## 2026-05-28 会话新增改动(未 commit)

### 开发者选项整套(Debug-only)

为 prompt 调试 + API 配置切换 + 余额查询 + 系统状态查看做的隐藏入口。`SettingsView` 底部 `#if DEBUG` 包了一个「开发者选项」NavigationLink,正式发布版本对用户不可见。

包含 5 个二级页:
- **分析提示词** (`AnalysisPromptPlaygroundView`):TextEditor 改 `debugAnalysisSystemPrompt` UserDefaults 覆盖,PhotosPicker 选图 → 调 `ImageAnalysisService.analyze()` → 显示原始输出 + 耗时
- **翻译提示词** (`TranslationPromptPlaygroundView`):同款交互,改 `debugTranslationSystemPrompt`,测试用文本输入(每行一段) → 直接调 `LLMTranslationService.translate()`
- **API 管理面板** (`APIManagementView`):分析(Qwen)+翻译(DeepSeek)两段,每段四行(当前使用 / Base URL / API Key / 模型)+ 模型选择按钮 + 余额查询
- **UserDefaults 查看器** (`UserDefaultsInspectorView`):列所有持久化 key-value,长字符串截断
- **清除所有 UserDefaults** (按钮,二次 confirmationDialog)

### 配套核心改动

- `ImageAnalysisService`:`systemPrompt` 改成 computed var,DEBUG 时读 `debugAnalysisSystemPrompt`,空字符串回落 `defaultSystemPrompt`(原静态字符串改名暴露给 playground)
- `LLMTranslationService`:同款 pattern,新增 `defaultSystemPrompt` 静态属性 + DEBUG override 逻辑
- `AnalysisDefaults.settings` / `DefaultModelConfig.settings`:DEBUG 时读三个 `debugXxxDefault*` UserDefaults key 做整套覆盖(Base URL / API Key / 模型),空字符串回落代码硬编码
- 这意味着所有调用 `*.settings` 的地方(AppIntent/主 App)**不需要改一行代码**——覆盖逻辑在计算属性里,对外完全透明

### DeepSeek 余额 + 模型列表服务

- `Core/Translation/DeepSeekBalanceService.swift`:`GET /user/balance`,Bearer 同 Chat Completions 用的 Key,解析 `balance_infos` 多币种结构
- `Features/Settings/ModelListService.swift`:`GET /models` OpenAI 兼容协议通用拉模型列表(DeepSeek/OpenAI/OpenRouter 都支持,Qwen DashScope 兼容模式不支持会 4xx)
- `Features/Settings/ModelPickerSheet.swift`:半屏 sheet,自动 `.task` 拉列表,失败显示清晰错误 + 重试按钮,选中即 `selectedModel = id; dismiss()`

### 主 App 改动

1. **拍照分析 Markdown 渲染修复** (`CameraCaptureSheet.swift:197`):原 `Text(text)` 直接展示 LLM 输出,`**内容**` 星号原样显示。改为 `Text(AttributedString(markdown: ...))` + `inlineOnlyPreservingWhitespace` 选项,粗体正确渲染。不复用 `SelectableMarkdownText` 是因为它前景色写死 `.label`,跟相机黑底冲突
2. **历史记录「全部清除」**:`HistoryView` 编辑模式下底部工具栏多一个红色「全部清除」按钮,二次系统 alert 确认。**作用域:只清当前 tab**(在翻译 tab 就只清翻译,分析 tab 就只清分析),避免一次手滑两边都丢
3. **历史空状态文案**:翻译/分析两 tab 的空状态描述改为「只会记录拍照X和选图X的内容(快捷识屏X不会被记录,用完即走)」——明确告诉用户端外 Shortcut 调用不入库,跟产品决策一致(见下方决策记录)
4. **翻译 tab 空状态文案**:`翻译外文 App，海外网页，游戏菜单` → `翻译外文APP、海外网页等`
5. **拍图按钮文案**:翻译 tab 改「选图翻译」,分析 tab 改「选图分析」(原都是「选择图片」)
6. **轻点背面教学 sheet 改版**:
   - 3 步 → **2 步**(用 iOS 设置搜索框跳过菜单层级):① 在「设置」顶部搜索框搜「轻点背面」并选中「轻点两下」 ② 滚动到列表底部,选中「识屏翻译/识屏分析」
   - **去掉**「打开系统设置」+「稍后再说」按钮(iOS 不允许 deeplink 到设置 App 根目录或子页面,跳本 App 设置页反而是"跳错地方"的失望感)
   - **加入真机录的 mp4 视频**:原视频 1.84MB(1080×1440)用 ffmpeg 压到 **245 KB**(540×720 H.264 baseline 无音轨),内嵌 bundle 直接播。复用现有 `LoopingVideoPlayer`,3:4 比例,圆角 30
   - 标题「2 步绑定背面双击」→「绑定轻点背面」,副文案精修
   - **mode-aware**:`BackTapTutorialSheet(mode: ContentMode)` 根据当前 tab 切换副文案和步骤 2 的快捷指令名;`ContentView.swift:140` 传当前 `mode` 进去
   - sheet detent: `.large` → `.fraction(0.88)`

---

## 重要产品决策记录

### 端外(轻点背面)调用不入库,坚持"用后即焚"

讨论结论:**不做** AppIntent 端外路径写历史。理由:
- 端外路径用户的心理预期是"快、临时、不留痕",写库破坏"敲一下就走"的轻量感
- 主 App 历史已经服务"主动打开 App、选图、看完整版"这类心智,两条路径应有不同形态
- 端外有误触风险(误敲背面/误按操作按钮),写库会留下莫名其妙的截图
- 工程成本不小(要加 App Group capability + 改 SwiftData 容器路径 + 老用户数据迁移)
- 真有"误关后悔"场景,可用 snippet 加"保存到相册"按钮解决,不需要数据库

后续如果用户反馈"主 App 历史空空看不出价值",再考虑加 opt-in 开关。

### 是否做登录账号系统

讨论结论:**不做**。理由:
- 工具型 App 加登录漏斗损失 30-60% 用户
- 付费走 StoreKit/IAP(Apple ID 即身份),云同步走 iCloud/CloudKit(零代码)
- 用户真正面临的不是"要不要登录",而是"API Key 硬编码进 IPA 会被盗刷"
- 解法是中间层(自建 Cloudflare Workers 代理 + 设备 ID 限频 + StoreKit 收据验证)

参考成功工具 App(CleanShot/Bear/Things/Reeder…)无一有账号系统。

### 国内合规风险

讨论结论:**先海外、后国内**。
- 千问/DeepSeek 底层 API 已备案,但 App 自己作为"服务方"按现行口径也应独立备案(国区上架)
- 当前路线建议:先 App Store 美区/港台/东南亚,业务起量再考虑国区合规流程
- 海外发布前必补:隐私政策(明确写图片传给阿里云)、首次使用分析功能的单独同意弹窗(PIPL+GDPR 通用)、Privacy Manifest

---

## 正在做什么

开发者选项 5 个二级页全部落地,DeepSeek 余额查询接通,模型列表自动拉取做完。
拍照分析 markdown 修复完成。教学 sheet 改成 2 步 + 真机视频。各种文案精修。

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

### 2026-05-27 (Claude Code - 新增轻点背面教学半屏 sheet)

**背景**:首页底部 `actionsGroup` 的「轻点背面 → 绑定」按钮之前直接跳 `UIApplication.openSettingsURLString` —— 这个 API 只能跳到本 App 自己的设置页(权限/隐私),**跳不到「辅助功能 → 触控 → 轻点背面」子页面**。iOS 不允许 deeplink 到系统设置任意子页面(`App-Prefs:` 私有 URL 早就被禁,审核会拒)。用户点了"绑定"看到本 App 设置页会一脸懵。

**改动**:
- 新增文件 `Features/Onboarding/BackTapTutorialSheet.swift`(~110 行):
  - NavigationStack + ScrollView 撑 3 个步骤卡
  - 每个步骤卡:浅灰圆角矩形 16:9 视频占位(`secondarySystemGroupedBackground` + `play.rectangle` 图标) + 蓝底圆形数字 ①②③ + 文字
  - 步骤文案:
    - ① 打开「设置」→「辅助功能」
    - ② 选「触控」→「轻点背面」→「轻点两下」
    - ③ 选中你保存的「快捷翻译」或「快捷分析」
  - 底部 `safeAreaInset` 挂主按钮「打开系统设置」(蓝色 capsule, 50pt 高,跳 `openSettingsURLString`) + 次按钮「稍后再说」
  - 顶栏右上 `xmark` 关闭按钮(裸 xmark + iOS 26 自动 toolbar capsule,跟 Safari/邮件系统 App 一致 —— 之前用 `xmark.circle.fill` 会跟系统 toolbar 背景叠成"2 层圆",已修)
  - `.presentationDetents([.large])` 全屏 sheet,内容多用滚动看
- 改 `ContentView.swift`:
  - 加 `@State private var showBackTapTutorial = false`
  - body 末尾追加 `.sheet(isPresented: $showBackTapTutorial) { BackTapTutorialSheet() }`(挂在 `.sheet(isPresented: $showingDetail)` 后面)
  - `backTapRow` 内 Button action 从 `UIApplication.shared.open(openSettingsURLString)` 改成 `showBackTapTutorial = true`

**为什么 sheet 里仍保留「打开系统设置」按钮**:虽然 deeplink 只能跳本 App 设置页,但用户先看完 3 步图文教学后**已经知道接下来要去辅助功能 → 触控 → 轻点背面**,跳过去不再懵。从认知断层变成认知传递。

**视频占位待替换**:目前是浅灰圆角矩形 + 播放图标。下次真机录 3 段 GIF/MP4(每段 5-8 秒,各演示一步)后替换 `Image(systemName: "play.rectangle")` 为 `LoopingVideoPlayer` 或 `VideoPlayer`。可以复用现有的 `LoopingVideoPlayer.swift`。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,无新增 warning(只有原有的 AppIntents metadata + UIScreen.main deprecated 两条历史 warning)。

**下次接着**:用户真机验证 ——
1. 主页底部「轻点背面 → 绑定」按钮 → 应该弹半屏 sheet 而不是跳设置页
2. sheet 内 3 个步骤卡视觉(浅灰 + 数字 + 文字)是否舒服
3. 「打开系统设置」按钮跳出去后能否手动找到「辅助功能 → 触控 → 轻点背面」
4. 验证完决定:开始准备视频素材,还是先做 UserDefaults flag + 首次成功庆祝(需要 App Group capability)

### 2026-05-27 (Claude Code - Intent 缺图引导,修掉"无法解析图片"劝退)

**背景**:AppShortcutsProvider 生效后,「快捷翻译」「快捷分析」两个动作卡片出现在快捷指令 App 内,但用户在快捷指令 App 内**直接点**这些卡片时,会触发系统错误"无法解析图片"——因为两个 Intent 都要求 `image: IntentFile` 必传参数,直接点没有截图输入。这个错误对新用户是劝退的,看不懂、像 bug。

**真实约束**:iOS 不允许第三方 App 在 Intent 内主动截屏(隐私限制)。所以这两个动作**本来就只能**配合系统动作"拍摄屏幕快照"组成复合 Shortcut 用,不是给用户直接点的。但快捷指令 App 没办法阻止用户点,所以我们要把这个意外路径的错误体验做好。

**改动**:
- 新增 `AppIntents/IntentErrors.swift`(~20 行):
  - `enum SnapTranslateIntentError: Error, CustomLocalizedStringResourceConvertible`
  - case `.missingImage`,localizedStringResource 中文文案引导用户回主 App 一键导入
- 改 `TranslateScreenshotIntent.swift`:
  - `@Parameter(title: "截图") var image: IntentFile?`(从必填改 Optional)
  - perform() 开头加 `guard let image else { throw SnapTranslateIntentError.missingImage }`
- 改 `AnalyzeScreenshotIntent.swift`:同样改动

**为什么用 throw 而不是返回带引导的 Snippet/Dialog**:
- `ShowsSnippetView` 的返回类型固定,nil 时返回别的类型会破坏方法签名兼容性
- iOS 对 `CustomLocalizedStringResourceConvertible` 错误的 throw 有标准处理:系统 alert 直接显示中文描述,体验跟 Dialog 接近
- 代码改动最小

**兼容性**:
- 既有 iCloud Shortcut 是 [拍摄屏幕快照 → 我们的 Intent],会把真实截图传进来,走 guard let 之后的原逻辑,**无破坏**
- 新建的 Shortcut 没填 image 参数的情况,系统会自动用上游步骤输出填充。如果用户**手动跳过**这一步,就会走到 throw 路径,看到引导文案

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**下次接着**:用户真机验证 ——
1. 打开「快捷指令」App,资料库找到「快捷识屏」分组下的动作卡片
2. 直接点「快捷翻译」或「快捷分析」 → 应该看到中文引导文案,而不是"无法解析图片"
3. 用之前 iCloud 导入的完整 Shortcut(含拍摄屏幕快照)触发 → 应该跟之前一样正常翻译/分析
4. 验证完决定下一步:第 3 步(教学半屏 sheet)还是第 2 步(UserDefaults flag + 首次成功庆祝)

### 2026-05-27 (Claude Code - 新增 AppShortcutsProvider 系统级注册)

**背景**:之前用户必须点 iCloud Shortcut 链接才能在快捷指令 App 里看到本 App 的两个动作。门槛高、流失大。iOS 16+ 提供 `AppShortcutsProvider` 协议,把 Intent 注册到系统级后,用户安装 App 即可在「快捷指令」App 的「应用」分类、Spotlight 搜索、Siri 里直接发现。

**新增文件**:`AppIntents/SnapTranslateAppShortcuts.swift`(~40 行)
- `struct SnapTranslateAppShortcuts: AppShortcutsProvider`
- 注册 `TranslateScreenshotIntent` (shortTitle "快捷翻译", systemImage `text.viewfinder`)
- 注册 `AnalyzeScreenshotIntent` (shortTitle "快捷分析", systemImage `wand.and.sparkles`)
- 每个 Intent 给 3 条 phrase,全部含 `\(.applicationName)` 占位符(框架硬要求,缺了编译报错)
- 运行时 `applicationName` 会被替换成 App 显示名「快捷识屏」

**为什么 phrases 不能直接对 Siri 喊**:两个 Intent 都有 `image: IntentFile` 必传参数,Siri 没法自动拍当前屏幕截图。所以 phrases 主要服务:
1. 用户拼复合 Shortcut 时在「快捷指令 → 应用 → 快捷识屏」分类下能搜到
2. Spotlight 搜索时显示动作卡片

**iCloud 链接保留**:作为新手"一键导入完整复合 Shortcut(含拍摄屏幕快照 + 调用本 Intent)"的最短路径。AppShortcutsProvider 没法预填"拍摄屏幕快照"这个上游步骤,所以两者并存。

**未改动 pbxproj**:项目用 Xcode 16+ 的 `PBXFileSystemSynchronizedRootGroup`,AppIntents/ 目录下新增 .swift 自动入主 App target 编译,Share Extension target 通过 `membershipExceptions` 没引用(也不需要)。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,无 warning。

**下次接着**:用户真机测试 ——
1. 卸载重装本 App,打开「快捷指令」App → 应用 → 应该能找到「快捷识屏」分类,展开看到两个动作
2. Spotlight 搜「快捷翻译」/「快捷分析」应该能直接看到动作卡片
3. 对 Siri 说「用快捷识屏翻译屏幕」会进入 Intent,但因为缺 image 参数会失败(预期行为,这是 phrases 提升发现度的副作用)
4. 验证完决定下一步:是否还要做方案 B(配置进度卡片 + UserDefaults flag 检测首次成功)

### 2026-05-27 (Claude Code - 首页空状态加场景文案)

**需求**:用户希望首页两个 tab 的空状态(img_none 占位图)下方各加一句具体场景文案,降低用户首次进入时"这个 tab 用来干嘛"的认知成本。文案灰色、字号 14。
- 翻译:"翻译外文 App,海外网页,游戏菜单"(中文逗号分隔)
- 分析:"解题、读截图、识万物"(顿号分隔)

**改动文件 `ContentView.swift`**:
- `imageArea`(翻译空状态,L255 附近):原来直接是 `Image("img_none").opacity(0.9)`,改成 `VStack(spacing: 12) { Image + Text }`。Text 用 `.font(.system(size: 14))` + `.foregroundStyle(.secondary)`(系统次要灰,自适应深浅色)。
- `analysisArea`(分析空状态,L358 附近):同样改造。原来 Image 自身带 `.frame(maxWidth: .infinity, maxHeight: .infinity)`,改造后 frame 移到外层 VStack 上,保留撑满空间的语义。

**选择 `.secondary` 而非 `Color.gray`**:`.secondary` 在深色模式自动反相成浅灰,纯 `.gray` 在深色背景下偏暗看不清。SwiftUI 标准做法。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**下次接着**:用户真机看视觉效果,如果字距/颜色/Spacing 要调再回来微调。

### 2026-05-26 晚上 第 2 轮 (Claude Code - SplashView 适配暗色模式)

**需求**:启动页 100% 还原 Figma 暗色稿(node 2085-13600)。设计稿两张:亮色保持原有,暗色背景反黑、主标语文字反白、底部「快捷识屏」文字反白,装饰彩色(粉、蓝、绿)保持不变。

**方案**:不动 SwiftUI 代码逻辑,通过 Assets.xcassets 的 appearances 字段提供 dark 资源 + 在 SplashView 里用 `@Environment(\.colorScheme)` 切换背景色和光晕色。

**改动文件**:
- 新增 `Assets.xcassets/BrandSlogan.imageset/brand-slogan-dark.svg`:复制亮色版本,把所有 `#0B0B0D`(文字黑)替换为 `#FFFFFF`,装饰色全保留(粉 #F2A1C1 / 蓝系 #466EB9 #5877C0 #5E7CC0 / 绿系 #5BAA68 #D2E08D 等)。
- 新增 `Assets.xcassets/SplashBrandText.imageset/splash-brand-text-dark.svg`:同样把「快捷识屏」4 个字的 `#0B0B0D` 替换为 `#FFFFFF`。
- 改 `BrandSlogan.imageset/Contents.json` 和 `SplashBrandText.imageset/Contents.json`:加 `appearances: [{appearance: luminosity, value: dark}]` 第二份 image 引用 dark 资源。
- 改 `Features/Splash/SplashView.swift`:
  - 加 `@Environment(\.colorScheme) private var colorScheme`
  - 背景:浅色 `.white` / 暗色 `.black`
  - 右上青色光晕 #00FDED:浅色 opacity 0.20 / 暗色 0.08(暗色下几乎不可见,符合截图观察)
  - 左上光晕:浅色保留浅蓝 #E1ECFF @100% / 暗色换成品牌绿 #5BAA68 @18%(呼应底部 logo)
  - `#Preview` 加 Light/Dark 两份方便预览。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**注意/留尾**:
- Figma 插件连接当前不可用(`connection.create` 报 "Not connected to relay"),暗色版光晕的精确色值是根据用户提供的截图肉眼推测的(深绿+品牌绿低透明度)。如果跟 Figma 设计稿差距明显,可再调 `SplashView.swift` 内的两个 opacity / 颜色常量,改动很小。
- 未跑模拟器视觉对比,只过了编译。下次可以打开模拟器切深色模式实测。

**下次接着**:用户真机切深浅外观看看 Splash 效果是否符合预期,有偏差再调光晕参数。

### 2026-05-26 晚上 (Claude Code - 端内翻译改用 Apple Translation Framework)

**需求**:把端内翻译(拍照翻译、选图翻译)默认模型从 DeepSeek LLM 改成 **Apple Translation Framework**(iOS 17.4+,本地翻译,免费/离线)。端外 AppIntent(轻点背面)继续走 LLM 不动。

**实现思路(实证后的最终方案)**:
Apple Translation API 不是普通函数调用,必须在 SwiftUI view 里通过 `.translationTask(_:perform:)` 触发。设计成:
1. `@State translationConfiguration: TranslationSession.Configuration?` 控制触发
2. `@State pendingTranslation: PendingTranslation?` 暂存待翻译数据(view 闭包跟 dispatch 之间中转)
3. body 末尾 `.translationTask(translationConfiguration) { session in await performAppleTranslation(session:) }`
4. dispatch 时:builtin 走 `triggerAppleTranslation` 设 config 触发 task;llm 不变

**改动文件 `ContentView.swift`**:
- `import Translation`
- 新增 3 个 state:`translationConfiguration` / `pendingTranslation` / 私有 `PendingTranslation` struct(`original` / `results` / `target`)
- body 末尾加 `.translationTask(translationConfiguration) { session in await performAppleTranslation(session: session) }`
- `dispatchTranslation` 的 `.builtin` 分支改成调 `triggerAppleTranslation(...)`(不 await,通过 @State 触发);`.llm` 分支不变
- 新增 `triggerAppleTranslation(original:results:)`:把数据塞 pendingTranslation,根据 target 是否变化决定 set 新 config 还是 `invalidate()` 旧 config 重跑
- 新增 `performAppleTranslation(session:)`:enumerate OCRResults 构造 `TranslationSession.Request`(`clientIdentifier` 用 index),`session.translations(from:)` batch 翻译,按 clientIdentifier 排序还原顺序,渲染译图;失败时回退到原 `runBuiltinTranslation`(DeepSeek)

**端外路径完全没动**:
- `AppIntents/TranslateScreenshotIntent.swift` 继续 `LLMTranslationService.Settings`
- `Core/Translation/TranslationPipeline.swift` 继续 `LLMTranslationService.translate`
- 端外 Dialog 渲染管线复杂,不引入 Apple Translation 风险

**回退策略**:Apple Translation `throw` 时(用户拒绝下载语言包 / 网络问题 / 不支持的语言对)→ 自动调 `runBuiltinTranslation`(原 builtin LLM 路径,DefaultModelConfig.settings = DeepSeek),保证用户体验不中断。

**首次体验**:用户第一次拍照翻译时,Apple Translation 会弹系统对话框"下载 English 翻译?",允许后下载几秒,之后离线秒翻。我们没做预热,用户首次有一次系统弹窗,可接受。

**设置 UI 不变**:翻译引擎 Picker 仍是「默认模型 / 自定义」,「默认模型」底层从 DeepSeek 透明切换到 Apple Translation。

**踩坑(已修)**:`Configuration.invalidate()` 是 mutating method,不能在 `let current` 上调,要直接在 @State 上 optional chain:`translationConfiguration?.invalidate()`。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**下次接着**:用户真机测试:
- 第一次拍照翻译 → 看系统下载语言包弹窗 + 允许后翻译速度
- 后续翻译 → 应该完全离线秒出
- 切换目标语言 → 走新 configuration,可能再次触发下载弹窗(目标语言变了)
- 拒绝下载语言包 → 应该回退到 DeepSeek
- 自定义引擎(.llm)→ 不动,继续 LLM

### 2026-05-26 下午 第 7 轮 (Claude Code - 修复选图分析 HTTP 400 + 卡片图片留白)

#### 1. 选图分析 HTTP 400 慢 + 失败

**用户反馈**:从相册选图分析特别慢、最后 HTTP 400 报错。翻译模式正常(因为翻译用本地 OCR 不发图给 API)。

**根因**:两条分析路径处理不一致:
- **拍照分析** `processCapturedImage`:有降采样 + JPEG(`downsample(maxDimension: 2048)` + `jpegData(0.85)`)→ ~1.5-2MP ✓
- **相册选图** `loadImageForAnalyze`:直接把原始 `Data` 传给 `AnalysisPipeline.runStream`,**没有降采样**

进入 `ImageAnalysisService.encodeImageDataURL` 后又**优先用 PNG**(无损,iPhone 12MP 原图 PNG 编码 20-50MB,base64 1.33x = 30-65MB)。超过 LLM API payload 限制(Qwen3-VL 通常 5-10MB,GPT-4o 20MB)→ HTTP 400。

**修复**:把降采样 + JPEG 兜底放在 `ImageAnalysisService.encodeImageDataURL` 内部,让所有 call site(主 App / AppIntent / Share Extension)无脑安全。

**改动文件 `Core/Analysis/ImageAnalysisService.swift`**:
- `encodeImageDataURL(_:)` 内部新增:
  1. `UIImage(data:)` 解码
  2. `downsample(_, maxDimension: 2048)` 缩到最大边 2048pt
  3. `jpegData(compressionQuality: 0.85)` 优先(PNG 改成 fallback)
- 新增 private static `downsample(_:maxDimension:)`,跟 ContentView 里那个逻辑一致,service 自包含不依赖 ContentView

**好处**:
- 选图分析也安全(本来的 bug)
- 拍照分析多一次 short-circuit downsample(原图已经 ≤2048 直接返回,无 perf 影响)
- AppIntent 端外路径也安全
- ContentView 的两处 downsample 可以保留(double 处理无害,做防御性深度)

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

#### 2. 卡片图片四周留 16pt

**用户反馈**:卡片里的图片贴到卡片左/右边缘。

**改动 `ContentView.swift` `imageArea`**:Group 后面、`.frame` 之前加 `.padding(16)`。X 按钮 overlay 在 padding 外层,仍贴卡片右上角(不跟图片内移)。

**未动 analysisArea**:它的 SelectableMarkdownText 已经有 `padding(.horizontal, 16)`,img_none 空状态没 padding,如果用户希望两个 tab 一致再加。

### 2026-05-26 下午 第 6 轮 (Claude Code - 修复拍照 UIImage 180° 颠倒)

**用户反馈**:第 5 轮预览方向对了,但**点击拍照后显示的 UIImage 顺时针 180° 颠倒**("上方间距太大了"中文 upside down)。

**根因**:第 5 轮只让 preview 用 swap mapping(landscapeLeft=0),capture 仍用 Apple 标准映射(landscapeLeft=180)。两者差 180° → preview 跟 capture 输出 UIImage 方向不一致。

PhotoDisplayView 显示 capturePhoto 输出的 UIImage,UIImage 内容方向取决于 capture angle。若用 Apple 标准 180,UIImage 顶在 image y=large(底);经 PhotoDisplayView aspectFill(顶 align view y=0)+ sheet rotation 90° CW,image 顶最终对应 user 视角"下" → 颠倒。

**修复**:让 capture 用跟 preview 一样的 swap mapping。`CameraSessionManager.videoRotationAngle(for:)` 静态映射直接改成 swap 值,preview 跟 capture 都通过它读 angle。

**改动文件**:
1. **`CameraSessionManager.swift:131`** `videoRotationAngle(for:)` static:
   - landscapeLeft: 180 → **0**
   - landscapeRight: 0 → **180**
   - portrait / upsideDown 不变
2. **`CameraCaptureSheet.swift`** `previewVideoRotationAngle` 简化成直接调 `CameraSessionManager.videoRotationAngle(for: camera.deviceOrientation)`,删除重复的 switch

**为什么 swap 跟 Apple 标准相反**:实证。SwiftUI rotationEffect 把 sheet 整个 view(包括 preview layer)transform,Apple 标准 angle 是"interface rotation 跟 device 同步"时的取值,我们 portrait-only + 手动 rotationEffect 跟它差了 180°。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**风险点**:UIImage 方向变了,OCR / 渲染链路理论上仍 work(Vision 自动 detect image orientation),但需要真机验证横拿翻译是否正确(boundingBox 水平 + 译文水平)。

**下次接着**:用户横拿真机测试:
1. 预览方向 ✓(上轮验证)
2. 拍照后 UIImage 方向 → 跟预览一致(本轮修复)
3. OCR 识别 + 翻译显示 → 水平译文(待验证)

### 2026-05-26 下午 第 5 轮 (Claude Code - 修复预览 90° 偏移)

**用户反馈**:第 4 轮 chrome 方向已经对(debug overlay 确认 `3 landscapeLeft rot=90°`),但**预览内容顺时针 90° 偏移**(显示器横向文字在预览里变成垂直)。

**根因**:`AVCaptureVideoPreviewLayer` 是 view 的 root layer,跟 view 一起被 SwiftUI rotationEffect transform。`videoRotationAngle = 90`(fixed)在 sheet rotate 90° CW 之后,两者叠加 90+90=180° → preview 显示方向跟用户视角差 90° CW。

**修复**:`previewVideoRotationAngle` 按 device orientation 给一个**补偿值**,让 video angle + sheet rotation 后净 effect 跟用户视角正立:
- portrait:    sheet 0°  + video 90 = 90 (portrait 正立 baseline)
- landscapeLeft:  sheet +90° CW + video 0 = 90 ✓
- landscapeRight: sheet -90° CW + video 180 = 90 ✓
- upsideDown:  sheet 180° + video 270 = 90 ✓

简化记忆:相对原 `CameraSessionManager.videoRotationAngle(for:)` 的 landscape 两个值**对调**(landscapeLeft 用 landscapeRight 的 video angle,反之亦然)。

**为什么 capturePhoto 不需要这个补偿**:capturePhoto 输出的 UIImage 不经过 sheet rotation transform(直接从 photo output 拿 raw pixel buffer),所以 angle 仍按 `CameraSessionManager.videoRotationAngle(for:)` 的标准映射,产出 properly-oriented UIImage 给 OCR 用。

**改动文件**:
- **`CameraCaptureSheet.swift`** `previewVideoRotationAngle` 从 `{ 90 }`(固定)改成 switch(按 device orientation 返回补偿值)

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**踩坑反思(写给下次自己)**:`AVCaptureVideoPreviewLayer` 跟普通 CALayer 一样被 SwiftUI rotationEffect transform。`videoRotationAngle` 是 layer 内 video frame 的 rotation,这两个 rotation 叠加。设计 sheet rotation + preview rotation 时必须把它们当成乘法叠加而不是两个独立 rotation。这一轮反复试错(第 1-5 轮)主要因为对 SwiftUI rotationEffect 跟 AVCaptureVideoPreviewLayer 交互理解不够,推导多次出错。**结论**:涉及 SwiftUI transform + UIKit/AVFoundation layer 的场景,优先信任**实证测试反馈**(用户截图描述),少做理论推导。

### 2026-05-26 下午 第 4 轮 (Claude Code - 修复预览内容颠倒 + 对调旋转符号)

**用户第 3 轮反馈 1**:横拿手机后 sheet 没旋转方向不对,要"反过来"。
**用户第 3 轮反馈 2**:对调符号后 chrome 方向对了,但预览内容上下颠倒(显示器内容在 preview 里是 upside-down)。

**Debug overlay 截图证实**:landscapeLeft 时 CoreMotion 推断正确(显示 "3 landscapeLeft rot=90°"),chrome 旋转方向也正确。**唯一问题是 preview 内容颠倒**。

**根因**:Preview 的 `videoRotationAngle` 跟 device orientation 同步(landscapeLeft = 180°)→ AVCaptureVideoPreviewLayer 内部把视频流旋转 180°。**同时** sheet 用 SwiftUI rotationEffect 旋转了 90°(顺时针)。两个旋转叠加:180° + 90° = 270° = -90°,视觉上 preview 内容相对用户视角"颠倒"。

**正解**:
- **Preview videoRotationAngle 固定 90°**(portrait 方向,video "顶"对齐 sheet 内坐标 y=0),让 sheet 的 rotationEffect 处理**所有**视觉旋转。preview view 跟着 sheet rotate,内容自然朝向用户视角"上"。
- **拍照(capturePhoto)的 angle 仍按 device orientation**(landscapeLeft = 180°),因为拍出来的 UIImage 不经过 sheet rotation,需要按物理方向 normalize → properly-oriented UIImage → 后续 OCR / 渲染 / 显示链路全部正确。

**uiRotationDegrees 角度对调**(第 3 轮符号反了):
- landscapeLeft:  -90 → **90**(顺时针,sheet "顶"转到屏幕"右",对应用户视角"上")
- landscapeRight: 90 → **-90**(逆时针,sheet "顶"转到屏幕"左",对应用户视角"上")
- (SwiftUI .rotationEffect 正值是顺时针,我之前推导反了 SwiftUI 的约定)

**改动文件**:
1. **`CameraCaptureSheet.swift`**:
   - `videoRotationAngle` 计算属性 → `previewVideoRotationAngle: CGFloat { 90 }`(固定)
   - `uiRotationDegrees` switch 里 landscape 两个 case 角度对调
   - CameraPreviewView 调用传 `previewVideoRotationAngle`(总是 90)
   - 删除临时 debug overlay 跟 `debugOrientationLabel` 计算属性

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**预期效果(真机横拿)**:
- sheet 旋转方向正确(chrome 在用户视角"上") ✓ (上一轮已经验证)
- preview 内容方向正确(显示器内容跟用户实际视觉一致) ✓ (本轮修复)
- 拍照后 UIImage 是 properly-oriented landscape ✓
- OCR 识别水平 boundingBox ✓
- 渲染水平译文 ✓

**下次接着**:用户真机横拿验证预览方向 + 拍照翻译方向。如果都对,这轮横屏支持就收尾了。

### 2026-05-26 下午 第 3 轮 (Claude Code - CoreMotion 真正修复横屏)

**用户第 2 次反馈**:第 2 轮改完后,sheet **完全没旋转**。截图里 X 按钮在屏幕左上(用户视角的左下)、状态栏在屏幕左侧(用户视角下方)、"保存到相册"在屏幕右侧(用户视角右侧) —— 是典型"portrait UI 在 landscape 视角下"的样子。文字方向是横排,只是因为拍照那一瞬间手机角度让 `UIDevice.current.orientation` 偶然返回了 landscape,**侥幸不稳定**。

**真正根因**:`UIDevice.orientationDidChangeNotification` **只在方向变化时发**。用户进入 sheet **前**就已经横拿手机不动了,sheet 出现后系统**没有方向变化事件**,`.onReceive` 永远收不到通知,本地 `@State deviceOrientation` 卡在 `.portrait` 初值,sheet 永不旋转。

把"启动 begin notifications"放在 `camera.configure()` 里也没用 —— begin 这个 API 只是让系统**之后开始发通知**,不会立即推一次"当前值"。如果用户进入 sheet 后保持不动,永远等不到第一次通知。

**修复方案**:废弃 `UIDevice.orientationDidChangeNotification`,改用 **CoreMotion 直接读重力向量推断设备方向**。这是 iOS 系统相机的做法 —— 不依赖 UIDevice 事件,sheet 一打开 200ms 内就拿到真实方向。

**改动文件**:
1. **`CameraSessionManager.swift`**:
   - `import CoreMotion`
   - 新增 `@Published var deviceOrientation: UIDeviceOrientation = .portrait`(自己维护,不再让 Sheet 持有)
   - 新增 `private let motionManager = CMMotionManager()`
   - 新增 `startOrientationUpdates()`:`motionManager.startDeviceMotionUpdates(to: .main)` 每 0.2s 回调,读 `motion.gravity` 调用 `orientation(fromGravity:)` 推断方向,变了就更新 @Published
   - 新增 `stopOrientationUpdates()`:`stopSession()` 里同步调用
   - 新增 `orientation(fromGravity:)`:重力 (x, y, z) → UIDeviceOrientation
     - `|x| < 0.3 && |y| < 0.3` (设备接近水平平躺) → fallback `.portrait`,避免抖动
     - `|y| > |x|`:`y > 0` 是 upsideDown,`y < 0` 是 portrait
     - `|x| > |y|`:`x > 0` 是 landscapeRight,`x < 0` 是 landscapeLeft
   - `configure()` 函数体开头调 `startOrientationUpdates()`(main thread 同步执行,在 sessionQueue.async 之前)
   - `capturePhoto(orientation:)` → `capturePhoto()`(参数移除),内部直接读 `self.deviceOrientation`,跟 sheet 视觉同源
   - 删除 `UIDevice.beginGeneratingDeviceOrientationNotifications` 调用

2. **`CameraCaptureSheet.swift`**:
   - 删除本地 `@State private var deviceOrientation` 跟它的初始化闭包
   - 删除 `.onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification))` 监听
   - `uiRotationDegrees` / `isLandscape` / `videoRotationAngle` 三个计算属性全部改成读 `camera.deviceOrientation`
   - GeometryReader 外加 `.animation(.easeInOut(duration: 0.25), value: camera.deviceOrientation)` 让旋转有动画
   - shutter Button 改回 `camera.capturePhoto()`(不传参数)

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**预期效果**:
- 用户横拿手机进入 sheet → 200ms 内 CoreMotion 第一次回调 → camera.deviceOrientation 更新到 `.landscapeXxx` → SwiftUI 自动 re-render → sheet 旋转到 landscape(带 0.25s 动画)
- 预览跟拍照都用 `camera.deviceOrientation` 这个唯一真相源,角度一致
- 用户旋转手机 → CoreMotion 持续推送新重力向量 → sheet 跟着旋转

**模拟器注意**:`motionManager.isDeviceMotionAvailable` 为 false → fallback portrait,模拟器永远是竖屏。**必须真机测试**。

### 2026-05-26 下午 第 2 轮 (Claude Code - 横屏拍摄真因修复 — 已被第 3 轮覆盖,只解决了一半)

**用户反馈**:第 1 轮改动后真机测试,sheet chrome 确实旋转了(English / X / 保存到相册按钮位置正确),但**拍出来的译图文字仍然是竖排**(每行一字符)。

**根因**:`CameraSessionManager.capturePhoto()` 内部直接读 `UIDevice.current.orientation`。这个值在拍照那一瞬间手机略微倾斜/平放就会变成 `.faceUp` / `.faceDown` / `.unknown`,`videoRotationAngle(for:)` 的 `default` 分支 fallback 到 90°(portrait) → AVCapturePhotoOutput 输出的 pixel buffer 实际是 portrait 方向 → 横向显示器内容被竖向入图 → OCR 出来 boundingBox 是窄竖列 → LayoutPreservingRenderer 在窄列里画水平译文 → 文字被换行成"每行一字符"竖排。

第 1 轮做的 sheet rotation 只解决了"chrome 视觉位置",没解决"拍出来的 UIImage 方向"。两件事用了**不同的 orientation 来源**:
- Sheet rotation 用的是 `@State deviceOrientation`(NotificationCenter 监听 + `isValidInterfaceOrientation` 过滤)
- 拍照用的是 `UIDevice.current.orientation`(直接读,不过滤)

**修复**:把 sheet 监听维护的 `deviceOrientation` 作为唯一真相源,传给 `capturePhoto`。

**改动文件**:
1. **`CameraSessionManager.swift`** `capturePhoto()` → `capturePhoto(orientation: UIDeviceOrientation)`,内部 `resolved = orientation.isValidInterfaceOrientation ? orientation : .portrait`,然后算 angle
2. **`CameraCaptureSheet.swift:273`** shutter Button action 改 `camera.capturePhoto(orientation: deviceOrientation)`

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`。

**下次接着**:用户真机横拿拍照,看译图文字是不是横排了。如果还不对,继续排查:可能是 OCR / 渲染器对 imageOrientation 处理有问题。

---

### 2026-05-26 下午 第 1 轮 (Claude Code - 横屏拍摄支持)

**用户反馈**:横拿手机拍横向显示器,翻译结果被绘成竖排(每个英文单词竖向一列字符)。原因:相机预览强制 portrait 旋转(`videoRotationAngle = 90` hardcode),但 `CameraSessionManager.capturePhoto()` 按 device orientation 输出 UIImage——预览跟拍照方向不一致;同时 sheet UI 始终 portrait,横拿时即使图片是 landscape,显示在 portrait view 里 aspectFill 会裁剪很多。

**根因深一层**:用户实际看到的竖排翻译,推测是用户**竖拿手机**拍横向内容时——portrait UIImage 里横向文字被旋转 90° 入图,OCR 出来的 boundingBox 是竖向细长矩形,LayoutPreservingRenderer 在窄矩形里水平绘制译文 → 文字被自动换行成"每行一字符"竖排。彻底修法就是让用户能横拿拍照,得到真正 landscape 的 UIImage,OCR/渲染全链路方向才正确。

**方案选择**:维持 App portrait-only(整体 UI 不动),仅 CameraCaptureSheet 内部"视觉上"支持 landscape。不去动 SceneDelegate / supportedInterfaceOrientations,改动小:
- 监听 `UIDevice.orientationDidChangeNotification`
- 外层用 `GeometryReader` + 互换 W/H + `rotationEffect(.degrees(uiRotationDegrees))` 把整个 sheet 旋转
- 内部布局按 portrait 画板写(顶 X / 底 shutter),旋转后自然映射到用户横拿视角的"上/下"
- 相机预览的 `videoRotationAngle` 跟 device orientation 同步(用 `CameraSessionManager.videoRotationAngle(for:)`),预览跟拍照用同一套角度

**改动文件**:
1. **`CameraSessionManager.swift:131`** `videoRotationAngle(for:)` private → static internal,让 CameraPreviewView 复用
2. **`CameraPreviewView.swift`** 完全重写:加 `let videoRotationAngle: CGFloat` 参数,删除 `layoutSubviews` 里 hardcode 90 的旧逻辑,改成 `setVideoRotationAngle(_:)` + 缓存 `pendingVideoRotationAngle` + `applyPendingRotation()`(layoutSubviews 里兜底再调一次,避免 connection 还没准备好时第一次设置被 skip)
3. **`CameraCaptureSheet.swift`**:
   - 新增 `@State private var deviceOrientation: UIDeviceOrientation`(初值取 `UIDevice.current.orientation`,无效时 fallback `.portrait`)
   - 新增计算属性 `uiRotationDegrees`(portrait=0 / landscapeLeft=-90 / landscapeRight=90 / upsideDown=180,顺时针)、`isLandscape`、`videoRotationAngle`
   - body 改成 `GeometryReader { geo in sheetContent.frame(...).rotationEffect(...).position(geo.center) }`
   - 新增 `private var sheetContent: some View`,把原 ZStack 内容(背景/mainContent/chrome VStack/loading overlay)挪进去,外加 `.clipped()` 防止旋转后画板溢出
   - chrome top padding 改为 `isLandscape ? 24 : 60`(portrait 避 Dynamic Island,landscape 时 sheet 的"top"对应屏幕侧边,无 Island)
   - bottom padding 同理 16 → 24
   - 新增 `.onReceive(NotificationCenter ... UIDevice.orientationDidChangeNotification)` 过滤 `isValidInterfaceOrientation` 后 `withAnimation` 更新 state
   - CameraPreviewView 调用补 `videoRotationAngle: videoRotationAngle` 参数

**为什么不动 PhotoDisplayView**:它接受 UIImage 后用 UIImageView aspectFill 显示。当 sheet 旋转到 landscape 后,PhotoDisplayView 的 frame 也是 landscape(互换了 W/H),aspectFill landscape UIImage 在 landscape view 里就是完美填满,无需改 contentMode。

**`UIDevice.beginGeneratingDeviceOrientationNotifications`**:CameraSessionManager.configure() 已经调用过,所以 orientation 通知正常发。

**Build 验证**:`xcodebuild build` → `** BUILD SUCCEEDED **`,无新警告(只有原有的 `normalizedOrientation` main-actor 警告)。

**预期效果**:
- 用户横拿手机进入相机面板 → 整个 sheet 自动旋转到 landscape,预览充满,chrome 在用户视角的"上/下"
- 拍照 → UIImage 是 landscape,内容方向正确
- OCR → 水平 boundingBox
- 渲染器 → 水平译文 ✅
- 结果 sheet 也是 landscape,PhotoDisplayView aspectFill 填满,看到正常的横向译图

**未解决/可能要继续打磨**:
- chrome 元素的具体位置在 landscape 下没专门重排(顶 X / 底 shutter 直接旋转过来),如果用户嫌位置怪可以做 landscape 专属布局(左右两侧而不是上下)
- 拍照后用户突然转回竖屏:sheet 会跟着旋转回 portrait,landscape UIImage 在 portrait view 里 aspectFill 会被裁剪。这种 edge case 暂不处理
- 分析模式底部 ScrollView 文本面板在 landscape 下高度限制 `maxHeight: 280` 没特别调,可能撑得偏高,真机看效果再决定要不要按 isLandscape 切换数值

**下次接着**:用户真机横拿测试:
1. 进入相机面板 → sheet 是否旋转 + 预览是否横向铺满
2. 拍照 → UIImage 方向是否正确
3. 翻译结果 → 文字是否横向排列
4. chrome(X / 语言菜单 / shutter / 保存) → 是否在用户视角"正立"
5. 反馈后决定要不要做 chrome 重排或者 PhotoDisplayView contentMode 切换

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
