//
//  ContentView.swift
//  SnapTranslate
//
//  Created by 杨剑峰 on 2026/5/12.
//

import SwiftUI
import SwiftData
import PhotosUI

/// 主页双 tab 切换的模式。
enum ContentMode { case translate, analyze }

struct ContentView: View {
    @Environment(\.modelContext) private var context

    /// 当前 tab。翻译/分析 各自独立状态,切换不清空。
    @State private var mode: ContentMode = .translate

    // MARK: - 翻译相关 state(保持原有,不动)
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var translatedImage: UIImage?
    @State private var ocrResults: [OCRResult] = []
    /// 目标语言。初始化时从 UserDefaults 读上次保存值;onChange 时显式写回。
    /// 不用 @AppStorage 是因为它在 Task 异步上下文里读到 stale value(SwiftUI quirk)。
    @State private var targetLanguage: TargetLanguage = {
        let raw = UserDefaults.standard.string(forKey: "targetLanguage") ?? TargetLanguage.zhHans.rawValue
        return TargetLanguage(rawValue: raw) ?? .zhHans
    }()
    @State private var isTranslating = false
    @State private var showingDetail = false

    // MARK: - 分析相关 state(新增)
    @State private var analysisPickerItem: PhotosPickerItem?
    @State private var analysisImage: UIImage?
    @State private var analysisText: String?
    @State private var isAnalyzing = false
    /// 复制按钮的"已复制"反馈,1.2 秒后还原
    @State private var analysisCopied = false

    // MARK: - 共用
    @State private var errorMessage: String?

    // 翻译引擎配置
    @AppStorage("translationEngine") private var engineRaw: String = TranslationEngine.builtin.rawValue
    @AppStorage("llmBaseURL") private var llmBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("llmAPIKey") private var llmAPIKey: String = ""
    @AppStorage("llmModel") private var llmModel: String = "gpt-4o-mini"

    // 分析引擎配置
    @AppStorage("analysisEngine") private var analysisEngineRaw: String = AnalysisEngine.builtin.rawValue
    @AppStorage("analysisBaseURL") private var analysisBaseURL: String = AnalysisDefaults.baseURL
    @AppStorage("analysisAPIKey") private var analysisAPIKey: String = ""
    @AppStorage("analysisModel") private var analysisModel: String = AnalysisDefaults.model

    // 通知条关闭状态:dismissedAt=0 表示从未关闭;dismissedAppVersion 记录关闭时的 App 版本
    @AppStorage("notificationDismissedAt") private var notificationDismissedAt: Double = 0
    @AppStorage("notificationDismissedAppVersion") private var notificationDismissedAppVersion: String = ""

    // 拍照翻译/分析:全屏相机界面是否显示
    @State private var showCameraCapture = false
    /// 标记本次拍照是否产生了翻译结果 —— 关闭 Sheet 时据此清空首页翻译 state,
    /// 让拍照翻译的结果只进历史记录,不留在首页(分析模式保持原行为,结果落首页)
    @State private var cameraCaptureProducedTranslate = false
    /// 标记本次拍照是否产生了分析结果 —— 跟 translate 一致,关闭 Sheet 时清空首页分析 state,
    /// 拍照分析结果只进历史,不留首页(产品要求跟拍照翻译一致)
    @State private var cameraCaptureProducedAnalyze = false

    /// 保存正在跑的 Task 引用,支持用户在 loading 状态点 X 取消
    @State private var translationTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?

    // iCloud Shortcut 链接
    private let translateShortcutURL = URL(string: "https://www.icloud.com/shortcuts/e3fc991c188f4c658f364ff663d796b7")!
    private let analyzeShortcutURL = URL(string: "https://www.icloud.com/shortcuts/6bc1d736d070469c99eed8b46f737830")!

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                // titleTabs 固定在顶部不参与翻页;TabView 只包卡片 + 快捷卡片(bottomGroup)
                VStack(spacing: 16) {
                    titleTabs
                        .padding(.horizontal)
                        .padding(.top, 8)

                    TabView(selection: $mode) {
                        pageView(for: .translate).tag(ContentMode.translate)
                        pageView(for: .analyze).tag(ContentMode.analyze)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { topToolbar }
        }
        .onChange(of: targetLanguage) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "targetLanguage")
            if let original = image, !ocrResults.isEmpty {
                Task { await dispatchTranslation(original: original, results: ocrResults) }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            translationTask?.cancel()
            translationTask = Task { await loadImageForTranslate(from: newItem) }
        }
        .onChange(of: analysisPickerItem) { _, newItem in
            analysisTask?.cancel()
            analysisTask = Task { await loadImageForAnalyze(from: newItem) }
        }
        .sheet(isPresented: $showingDetail) {
            if let img = translatedImage ?? image {
                ImageDetailView(image: img)
            }
        }
        .fullScreenCover(isPresented: $showCameraCapture) {
            CameraCaptureSheet(
                mode: mode,
                resultImage: cameraResultImageBinding,
                resultText: $analysisText,
                isProcessing: cameraIsProcessingBinding,
                targetLanguage: $targetLanguage,
                onClose: {
                    showCameraCapture = false
                    // 拍照翻译/分析:关闭 Sheet 后清空首页对应 state(结果已经在历史记录里),
                    // 两种模式都不留首页,首页只显示从 PhotosPicker 选的图
                    if cameraCaptureProducedTranslate {
                        image = nil
                        translatedImage = nil
                        ocrResults = []
                        cameraCaptureProducedTranslate = false
                    }
                    if cameraCaptureProducedAnalyze {
                        analysisImage = nil
                        analysisText = nil
                        cameraCaptureProducedAnalyze = false
                    }
                },
                onCapture: { image in
                    // 取消之前正在跑的 task,新拍的图启动新流程
                    if mode == .translate {
                        translationTask?.cancel()
                        translationTask = Task { await processCapturedImage(image) }
                    } else {
                        analysisTask?.cancel()
                        analysisTask = Task { await processCapturedImage(image) }
                    }
                }
            )
            .ignoresSafeArea()
        }
        .alert("出错了", isPresented: errorAlertBinding) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - 顶部双 tab 大标题

    private var titleTabs: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            tabButton(title: "翻译", target: .translate)
            tabButton(title: "分析", target: .analyze)
            Spacer()
        }
        .padding(.top, 4)
        // 让 swipe 翻页时 tab 文字 foreground 过渡(选中/未选中色)跟点击切换一致;
        // .font 是离散切换无法 animate,但颜色淡入淡出已经有视觉过渡感
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func tabButton(title: String, target: ContentMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = target
            }
        } label: {
            Text(title)
                .font(mode == target ? .largeTitle.bold() : .title3.bold())
                .foregroundStyle(mode == target ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容区(根据 mode 分发)

    // contentArea 不再用嵌套 TabView,改回简单 switch —— 外层 body 的 TabView 已经处理 page swipe。
    // 每个 page 接收自己的 pageMode 参数,swipe 过渡期两 page 同屏时各显各的内容,不会因读 self.mode 错位。
    @ViewBuilder
    private func contentArea(for pageMode: ContentMode) -> some View {
        switch pageMode {
        case .translate: imageArea
        case .analyze: analysisArea
        }
    }

    /// 单个 tab 的完整页面(标题 + 卡片 + 底部组),供外层 TabView 当 page 使用
    private func pageView(for pageMode: ContentMode) -> some View {
        // titleTabs 已提到 TabView 外面固定,pageView 只包翻页时跟随的卡片 + 快捷卡片
        VStack(spacing: 16) {
            contentCard(for: pageMode)
            bottomGroup
        }
        .padding(.horizontal)
        .padding(.bottom, 4) // 卡片到底部 4pt
    }

    // MARK: - 翻译模式 - 图片区

    private var imageArea: some View {
        Group {
            if let translatedImage {
                Image(uiImage: translatedImage)
                    .resizable()
                    .scaledToFit()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("img_none")
                    .opacity(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            if image != nil && !isTranslating {
                showingDetail = true
            }
        }
        // 去掉浮在图片上的语言切换菜单 —— 跟顶部导航栏 toolbar 的"简体中文"重复;
        // X 关闭按钮保留(翻译中→取消,完成→清空)。
        // 拍照翻译走 CameraCaptureSheet 是独立 chrome,不受此影响。
        .overlay(alignment: .topTrailing) {
            if image != nil {
                Button {
                    if isTranslating {
                        cancelTranslation()
                    } else {
                        clearImage()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .gray)
                        .padding(8)
                }
                .accessibilityLabel(isTranslating ? "取消翻译" : "清空图片")
            }
        }
        .overlay {
            if isTranslating {
                // 深色高对比 loading,跟 CameraCaptureSheet 统一样式,
                // 避免 .ultraThinMaterial + primary 文字在白底图片上被冲淡看不清
                ProgressView {
                    Text("翻译中…").foregroundStyle(.white)
                }
                .tint(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 14))
            }
        }
    }

    /// 翻译卡片顶部中间的目标语言切换菜单(image != nil 时通过 overlay 显示)
    private var imageAreaTargetLanguageMenu: some View {
        Menu {
            ForEach(TargetLanguage.allCases) { lang in
                Button {
                    targetLanguage = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if targetLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(targetLanguage.displayName)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
        }
        .accessibilityLabel("切换目标语言")
    }

    private func clearImage() {
        image = nil
        translatedImage = nil
        ocrResults = []
        pickerItem = nil
        isTranslating = false
    }

    // MARK: - 分析模式 - 结果区

    private var analysisArea: some View {
        VStack(spacing: 0) {
            Group {
                if let text = analysisText {
                    ScrollView(showsIndicators: false) {
                        // 用 UITextView 包装以获得正确的"长按选词 + 跟随手指的选区菜单"
                        SelectableMarkdownText(text: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16) // 分析文本距卡片左右各 16pt
                            .padding(.top, 32) // 上方 32pt:避开右上角 X 按钮,视觉更舒展
                            .padding(.bottom, 4)
                    }
                } else if analysisImage != nil {
                    // 选了图但还没结果(分析中)。loading overlay 会盖住。
                    Color.clear
                } else {
                    Image("img_none")
                        .opacity(0.9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .overlay(alignment: .topTrailing) {
            // 分析中/分析完都显示:分析中触发取消,完成后触发清空 + 复制
            if analysisText != nil || analysisImage != nil {
                HStack(spacing: 4) {
                    if let text = analysisText, !isAnalyzing {
                        copyButton(text: text)
                    }
                    Button {
                        if isAnalyzing {
                            cancelAnalysis()
                        } else {
                            clearAnalysis()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .gray)
                            .padding(8)
                    }
                    .accessibilityLabel(isAnalyzing ? "取消分析" : "清空")
                }
                .padding(.trailing, 8)
            }
        }
        .overlay {
            if isAnalyzing {
                // 深色高对比 loading,跟 imageArea / CameraCaptureSheet 统一样式
                ProgressView {
                    Text("分析中…").foregroundStyle(.white)
                }
                .tint(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 14))
            }
        }
    }

    private func clearAnalysis() {
        analysisImage = nil
        analysisText = nil
        analysisPickerItem = nil
        isAnalyzing = false
    }

    /// 翻译中/分析中遮罩的背景色 + 圆角:浅色 5% 黑、深色 10% 白,24pt 圆角。
    private var loadingBackground: some View {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor.black.withAlphaComponent(0.05)
        })
        .clipShape(.rect(cornerRadius: 24))
    }

    /// 复制按钮(分析模式右上角,和 xmark.circle.fill 关闭按钮视觉尺寸保持一致)。
    /// 用 ZStack 叠 circle.fill 与 doc.on.doc.fill,确保外圆直径与 xmark.circle.fill 完全一致。
    private func copyButton(text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            analysisCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                analysisCopied = false
            }
        } label: {
            ZStack {
                Image(systemName: "circle.fill")
                    .font(.title)
                    .foregroundStyle(.gray)
                Image(systemName: analysisCopied ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(8)
        }
        .accessibilityLabel(analysisCopied ? "已复制" : "复制")
    }

    // MARK: - 快捷指令 + 轻点背面 两个 row(文案随 mode 切换)

    private var actionsGroup: some View {
        VStack(spacing: 0) {
            shortcutRow.frame(height: 62)
            Divider().padding(.leading, 58)
            backTapRow.frame(height: 62)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var shortcutRow: some View {
        HStack(spacing: 12) {
            iconBlock(
                systemName: "bolt.fill",
                background: LinearGradient(
                    colors: [
                        Color(red: 0x81 / 255.0, green: 0x7E / 255.0, blue: 0xFB / 255.0), // #817EFB
                        Color(red: 0x91 / 255.0, green: 0x93 / 255.0, blue: 0xFA / 255.0)  // #9193FA
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("快捷指令")
                    .font(.body)
                Text(mode == .translate
                     ? "一键添加「快捷翻译」的快捷指令"
                     : "一键添加「快捷分析」的快捷指令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Link(destination: mode == .translate ? translateShortcutURL : analyzeShortcutURL) {
                Text("添加")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
    }

    private var backTapRow: some View {
        HStack(spacing: 12) {
            iconBlock(
                systemName: "hand.tap.fill",
                background: LinearGradient(
                    colors: [
                        Color(red: 0x50 / 255.0, green: 0xA4 / 255.0, blue: 0x5D / 255.0), // #50A45D
                        Color(red: 0x64 / 255.0, green: 0xB3 / 255.0, blue: 0x71 / 255.0)  // #64B371
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("轻点背面")
                    .font(.body)
                Text("设置里绑定「轻点背面」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("绑定")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
    }

    private func iconBlock(systemName: String, background: some ShapeStyle) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - 内容卡片(白色圆角卡片包 contentArea + 底部 2 按钮行)
    // Figma:卡片 r=24 fill #FFFFFF,底部 60pt 内含 2 个 163×44 胶囊按钮,中间间距 12pt

    private func contentCard(for pageMode: ContentMode) -> some View {
        VStack(spacing: 0) {
            contentArea(for: pageMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 分割线:1px 系统 separator 色(跟 actionsGroup 内同款 Divider 一致),贯穿卡片全宽
            Divider()

            // 底部按钮行
            HStack(spacing: 12) {
                captureButton(for: pageMode)
                photoSelectButton(for: pageMode)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }


    private func captureButton(for pageMode: ContentMode) -> some View {
        Button {
            showCameraCapture = true
        } label: {
            cardBottomButtonLabel(
                icon: "IconCamera",
                text: pageMode == .translate ? "拍照翻译" : "拍照分析"
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func photoSelectButton(for pageMode: ContentMode) -> some View {
        switch pageMode {
        case .translate:
            PhotosPicker(selection: $pickerItem, matching: .images) {
                cardBottomButtonLabel(icon: "IconPhoto", text: "选择图片")
            }
            .buttonStyle(.plain)
        case .analyze:
            PhotosPicker(selection: $analysisPickerItem, matching: .images) {
                cardBottomButtonLabel(icon: "IconPhoto", text: "选择图片")
            }
            .buttonStyle(.plain)
        }
    }

    private func cardBottomButtonLabel(icon: String, text: String) -> some View {
        // 按 Figma 7376:48554:163×44 fill #FFFFFF(跟卡片融合,无可见背景),内部图标+文字居中
        HStack(spacing: 8) {
            Image(icon)
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundColor(.primary)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.primary.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 44)
        .contentShape(.rect) // 整个 frame 作为 hit area
    }

    // MARK: - 底部组(通知条 + 快捷指令卡片,内部间距 8pt)

    private var bottomGroup: some View {
        VStack(spacing: 8) {
            if shouldShowNotification {
                NotificationBar(
                    onLearnMore: {
                        // TODO: 跳转教程页面,先占位
                    },
                    onDismiss: dismissNotification
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            actionsGroup
        }
        .padding(.top, 12) // 整体下移 12pt
    }

    // MARK: - 通知条显示逻辑
    // 规则:默认显示 → 关闭后,跨 App 版本立即恢复;同版本下隔 1 天恢复。

    private var shouldShowNotification: Bool {
        if notificationDismissedAt == 0 { return true }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if notificationDismissedAppVersion != current { return true }
        let dismissedDate = Date(timeIntervalSince1970: notificationDismissedAt)
        return Date().timeIntervalSince(dismissedDate) > 86_400 // 24h
    }

    private func dismissNotification() {
        withAnimation(.easeInOut) {
            notificationDismissedAt = Date().timeIntervalSince1970
            notificationDismissedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                HistoryView()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
        // 目标语言菜单仅翻译模式显示
        if mode == .translate {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                targetLanguageMenu
            }
        }
    }

    private var targetLanguageMenu: some View {
        Menu {
            ForEach(TargetLanguage.allCases) { lang in
                Button {
                    targetLanguage = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if targetLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(targetLanguage.displayName)
        }
    }

    // MARK: - 翻译主流程(原有逻辑,不动)

    private func loadImageForTranslate(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        translatedImage = nil
        ocrResults = []
        image = uiImage
        isTranslating = true
        await runOCR(on: uiImage)
    }

    private func runOCR(on image: UIImage) async {
        do {
            let results = try await VisionOCRService.recognize(in: image)
            ocrResults = results
            print("【OCR】共识别 \(results.count) 段")
            for (i, r) in results.enumerated() {
                print("  [\(i)] \"\(r.text)\" box=\(r.boundingBox) conf=\(String(format: "%.2f", r.confidence))")
            }
            await dispatchTranslation(original: image, results: results)
        } catch {
            print("【OCR】失败: \(error)")
            errorMessage = "OCR 失败: \(error.localizedDescription)"
            isTranslating = false
        }
    }

    private func dispatchTranslation(original: UIImage, results: [OCRResult]) async {
        isTranslating = true
        let engine = TranslationEngine(rawValue: engineRaw) ?? .builtin
        switch engine {
        case .builtin:
            await runBuiltinTranslation(original: original, results: results)
        case .llm:
            await runLLMTranslation(original: original, results: results)
        }
        isTranslating = false
    }

    private func runBuiltinTranslation(original: UIImage, results: [OCRResult]) async {
        let texts = results.map { $0.text }
        do {
            let translations = try await LLMTranslationService.translate(
                texts,
                targetLanguageDisplayName: targetLanguage.displayName,
                settings: DefaultModelConfig.settings
            )
            print("【默认模型翻译】完成 \(translations.count) 段")
            for (orig, trans) in zip(texts, translations) {
                print("  原: \(orig)")
                print("  译: \(trans)")
            }
            renderTranslatedImage(original: original, translations: translations)
        } catch is LLMTranslationService.SameLanguageError {
            // 源语言==目标语言(或 LLM 没翻译):不报错,translatedImage 保持 nil,用户看到原图。
            print("【默认模型翻译】源语言与目标语言一致,直接显示原图")
        } catch {
            print("【默认模型翻译】失败: \(error.localizedDescription)")
            errorMessage = "默认模型翻译失败: \(error.localizedDescription)"
        }
    }

    private func runLLMTranslation(original: UIImage, results: [OCRResult]) async {
        let texts = results.map { $0.text }
        do {
            let translations = try await LLMTranslationService.translate(
                texts,
                targetLanguageDisplayName: targetLanguage.displayName,
                settings: .init(baseURL: llmBaseURL, apiKey: llmAPIKey, model: llmModel)
            )
            print("【LLM 翻译】完成 \(translations.count) 段")
            for (orig, trans) in zip(texts, translations) {
                print("  原: \(orig)")
                print("  译: \(trans)")
            }
            renderTranslatedImage(original: original, translations: translations)
        } catch is LLMTranslationService.SameLanguageError {
            // 源语言==目标语言(或 LLM 没翻译):不报错,translatedImage 保持 nil,用户看到原图。
            print("【LLM 翻译】源语言与目标语言一致,直接显示原图")
        } catch {
            print("【LLM 翻译】失败: \(error.localizedDescription)")
            errorMessage = "自定义模型翻译失败: \(error.localizedDescription)"
        }
    }

    private func renderTranslatedImage(original: UIImage, translations: [String]) {
        let blocks = zip(ocrResults, translations).map { r, t in
            LayoutPreservingRenderer.Block(normalizedBox: r.boundingBox, translatedText: t)
        }
        let rendered = LayoutPreservingRenderer.render(originalImage: original, blocks: blocks)
        translatedImage = rendered
        let item = HistoryItem(originalImage: original, translatedImage: rendered, segmentCount: ocrResults.count)
        context.insert(item)
    }

    // MARK: - 图片降采样(分析模式拍照原图太大,LLM 上传慢)

    /// 等比缩放到 max 边 ≤ maxDimension。原图已经小于阈值直接返回。
    /// `format.scale = 1` 让渲染 logical=pixel,不被 retina 放大,生成的 UIImage 实际像素就是 newSize。
    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let maxSide = max(originalSize.width, originalSize.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: floor(originalSize.width * scale),
            height: floor(originalSize.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - 取消正在跑的翻译/分析(供 loading 状态右上角的 X 按钮使用)

    private func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        isTranslating = false
        image = nil
        translatedImage = nil
        ocrResults = []
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisImage = nil
        analysisText = nil
    }

    // MARK: - CameraCaptureSheet 绑定 helper(read-only 把 ContentView state 传给 Sheet)

    /// 翻译模式返回译图(translatedImage),分析模式返回 nil(让 Sheet fallback 显示原图 + 分析文本)
    private var cameraResultImageBinding: Binding<UIImage?> {
        Binding(
            get: { mode == .translate ? translatedImage : nil },
            set: { _ in }
        )
    }

    /// 翻译模式 isTranslating,分析模式 isAnalyzing
    private var cameraIsProcessingBinding: Binding<Bool> {
        Binding(
            get: { mode == .translate ? isTranslating : isAnalyzing },
            set: { _ in }
        )
    }

    // MARK: - 拍照翻译/分析:处理相机拍到的 UIImage(复用现有 OCR + translate / analyze pipeline)

    private func processCapturedImage(_ uiImage: UIImage) async {
        switch mode {
        case .translate:
            translatedImage = nil
            ocrResults = []
            // 降采样到 max 2048pt:相机原图 12MP 对 Vision OCR 是过度精度,
            // 缩到 ~2MP 后 OCR 速度大幅提升(几百 ms → 一两百 ms),且 LLM 文本翻译只看识别后的字符串,
            // 不受图分辨率影响。LayoutPreservingRenderer 用降采样图渲染译图,体感秒出。
            let downsampled = Self.downsample(uiImage, maxDimension: 2048)
            image = downsampled
            cameraCaptureProducedTranslate = true // 标记:关闭 Sheet 时要清空首页翻译 state
            isTranslating = true
            await runOCR(on: downsampled)
        case .analyze:
            analysisText = nil
            analysisImage = uiImage
            cameraCaptureProducedAnalyze = true // 标记:关闭 Sheet 时要清空首页分析 state
            isAnalyzing = true
            // 降采样到 max 2048pt:相机原图 12MP(~4032x3024)直接上传 LLM 太大太慢
            // (vs 截屏只有 ~3MP)。降到 2048 后约 1.5-2MP,LLM 上传+处理速度大幅提升,
            // 视觉精度仍然足够 LLM 识别图中文字/物体/场景。
            let downsampled = Self.downsample(uiImage, maxDimension: 2048)
            guard let data = downsampled.jpegData(compressionQuality: 0.85) else {
                errorMessage = "图片编码失败"
                isAnalyzing = false
                return
            }
            let engine = AnalysisEngine(rawValue: analysisEngineRaw) ?? .builtin
            let settings: ImageAnalysisService.Settings = {
                switch engine {
                case .llm:
                    return ImageAnalysisService.Settings(
                        baseURL: analysisBaseURL.isEmpty ? AnalysisDefaults.baseURL : analysisBaseURL,
                        apiKey: analysisAPIKey,
                        model: analysisModel.isEmpty ? AnalysisDefaults.model : analysisModel
                    )
                case .builtin:
                    return AnalysisDefaults.settings
                }
            }()
            do {
                // truncate: false → 主 App 不截断分析文本,让 imageArea / 相机面板的 ScrollView 完整显示
let result = try await AnalysisPipeline.run(imageData: data, settings: settings, truncate: false)
                analysisText = result.analysisText
                let historyItem = HistoryItem(originalImage: result.image, analysisText: result.analysisText)
                context.insert(historyItem)
            } catch {
                errorMessage = "图片分析失败: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }

    // MARK: - 分析主流程(新增)

    private func loadImageForAnalyze(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        analysisText = nil
        analysisImage = uiImage
        isAnalyzing = true

        let engine = AnalysisEngine(rawValue: analysisEngineRaw) ?? .builtin
        let settings: ImageAnalysisService.Settings = {
            switch engine {
            case .llm:
                return ImageAnalysisService.Settings(
                    baseURL: analysisBaseURL.isEmpty ? AnalysisDefaults.baseURL : analysisBaseURL,
                    apiKey: analysisAPIKey,
                    model: analysisModel.isEmpty ? AnalysisDefaults.model : analysisModel
                )
            case .builtin:
                return AnalysisDefaults.settings
            }
        }()

        do {
            // truncate: false → 主 App 不截断分析文本,让 imageArea / 相机面板的 ScrollView 完整显示
let result = try await AnalysisPipeline.run(imageData: data, settings: settings, truncate: false)
            print("【图片分析】完成,长度 \(result.analysisText.count) 字")
            analysisText = result.analysisText
            // 写历史
            let historyItem = HistoryItem(originalImage: result.image, analysisText: result.analysisText)
            context.insert(historyItem)
        } catch {
            print("【图片分析】失败: \(error.localizedDescription)")
            errorMessage = "图片分析失败: \(error.localizedDescription)"
        }
        isAnalyzing = false
    }
}

/// 用 UITextView 渲染 Markdown 文本,以获得正确的"长按选词 + 跟随手指的选区菜单"。
/// SwiftUI 的 Text + .textSelection(.enabled) 在 ScrollView 里渲染 Markdown 时无法做到这一点。
private struct SelectableMarkdownText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // 没有 sizeThatFits 时,UITextView 的 intrinsicContentSize 会按"不换行"算出超宽尺寸,把整页撑大。
        // 这里以 SwiftUI 给的宽度为准,再让 UITextView 自己算高度。
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let textColor = UIColor.label
        let attributed: NSAttributedString

        if let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            let ns = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
            let fullRange = NSRange(location: 0, length: ns.length)
            ns.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                let traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
                ns.addAttribute(
                    .font,
                    value: UIFont(descriptor: descriptor, size: baseFont.pointSize),
                    range: range
                )
            }
            ns.addAttribute(.foregroundColor, value: textColor, range: fullRange)
            attributed = ns
        } else {
            attributed = NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: textColor
            ])
        }
        uiView.attributedText = attributed
    }
}

#Preview {
    ContentView()
        .modelContainer(for: HistoryItem.self, inMemory: true)
}
