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

    // iCloud Shortcut 链接
    private let translateShortcutURL = URL(string: "https://www.icloud.com/shortcuts/e3fc991c188f4c658f364ff663d796b7")!
    private let analyzeShortcutURL = URL(string: "https://www.icloud.com/shortcuts/6bc1d736d070469c99eed8b46f737830")!

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    titleTabs

                    contentArea

                    actionsGroup

                    primaryPickerButton
                }
                .padding()
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
            Task { await loadImageForTranslate(from: newItem) }
        }
        .onChange(of: analysisPickerItem) { _, newItem in
            Task { await loadImageForAnalyze(from: newItem) }
        }
        .sheet(isPresented: $showingDetail) {
            if let img = translatedImage ?? image {
                ImageDetailView(image: img)
            }
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

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .translate: imageArea
        case .analyze: analysisArea
        }
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
                VStack(spacing: 16) {
                    Image("img_none")
                    Text("从相册中选择图片开始翻译")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            if image != nil && !isTranslating {
                showingDetail = true
            }
        }
        .overlay(alignment: .topTrailing) {
            if image != nil && !isTranslating {
                Button {
                    clearImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .gray)
                        .padding(8)
                }
                .accessibilityLabel("清空图片")
            }
        }
        .overlay {
            if isTranslating {
                ZStack {
                    loadingBackground
                    ProgressView("翻译中…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
            }
        }
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
            // 顶部操作行(仅在已有结果/图、未在分析时显示),让按钮独占一行避免盖住文字
            if (analysisText != nil || analysisImage != nil) && !isAnalyzing {
                HStack(spacing: 4) {
                    Spacer()
                    if let text = analysisText {
                        copyButton(text: text)
                    }
                    Button {
                        clearAnalysis()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .gray)
                            .padding(8)
                    }
                    .accessibilityLabel("清空")
                }
                .padding(.top, -16)
            }

            Group {
                if let text = analysisText {
                    ScrollView(showsIndicators: false) {
                        // 用 UITextView 包装以获得正确的"长按选词 + 跟随手指的选区菜单"。
                        // 不加 horizontal padding,让文字两边距屏幕 = 外层 VStack.padding 默认值(16),
                        // 与下方 actionsGroup 卡片两边对齐。
                        SelectableMarkdownText(text: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .overlay(alignment: .bottom) {
                        // 底部渐变遮罩:让 ScrollView 底部文字淡出到背景色,暗示下方还有更多内容可滑动。
                        LinearGradient(
                            colors: [
                                Color(.systemGroupedBackground).opacity(0),
                                Color(.systemGroupedBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 32)
                        .allowsHitTesting(false)
                    }
                } else if analysisImage != nil {
                    // 选了图但还没结果(分析中)。loading overlay 会盖住。
                    Color.clear
                } else {
                    VStack(spacing: 16) {
                        Image("img_none")
                        Text("从相册中选择图片开始分析")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .overlay {
            if isAnalyzing {
                ZStack {
                    loadingBackground
                    ProgressView("分析中…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
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
            iconBlock(systemName: "bolt.fill", background: Color.blue.gradient)

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
            iconBlock(systemName: "hand.tap.fill", background: Color.green.gradient)

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

    // MARK: - 主操作按钮(根据 mode 绑不同 PhotosPicker)

    @ViewBuilder
    private var primaryPickerButton: some View {
        switch mode {
        case .translate:
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选图", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint, in: .capsule)
                    .foregroundStyle(.white)
            }
        case .analyze:
            PhotosPicker(selection: $analysisPickerItem, matching: .images) {
                Label("从相册选图", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint, in: .capsule)
                    .foregroundStyle(.white)
            }
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
            let result = try await AnalysisPipeline.run(imageData: data, settings: settings)
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
