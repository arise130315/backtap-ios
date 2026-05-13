//
//  ContentView.swift
//  SnapTranslate
//
//  Created by 杨剑峰 on 2026/5/12.
//

import SwiftUI
import SwiftData
import PhotosUI
import Translation

struct ContentView: View {
    @Environment(\.modelContext) private var context

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var translatedImage: UIImage?
    @State private var ocrResults: [OCRResult] = []
    @State private var translationConfig: TranslationSession.Configuration?
    /// session 内的目标语言,每次启动 App 重置为简体中文;同步写入 UserDefaults 供 AppIntent 读取
    @State private var targetLanguage: TargetLanguage = .zhHans
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var showingDetail = false

    @AppStorage("translationEngine") private var engineRaw: String = TranslationEngine.builtin.rawValue
    @AppStorage("llmBaseURL") private var llmBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("llmAPIKey") private var llmAPIKey: String = ""
    @AppStorage("llmModel") private var llmModel: String = "gpt-4o-mini"

    private let iCloudShortcutURL = URL(string: "https://www.icloud.com/shortcuts/dfe053b90fa349dc96664b485719b3f0")!

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    imageArea

                    actionsGroup

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从相册选图", systemImage: "photo.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
            }
            .navigationTitle("识图翻译")
            .toolbar {
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
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    targetLanguageMenu
                }
            }
        }
        .onAppear {
            targetLanguage = .zhHans
            UserDefaults.standard.set(TargetLanguage.zhHans.rawValue, forKey: "targetLanguage")
        }
        .onChange(of: targetLanguage) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "targetLanguage")
            // 如果当前已有图片和 OCR 结果,用新目标语言重新翻译并渲染
            if let original = image, !ocrResults.isEmpty {
                Task { await dispatchTranslation(original: original, results: ocrResults) }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadImage(from: newItem) }
        }
        .translationTask(translationConfig) { session in
            await translate(using: session)
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

    // MARK: - 图片区域(含清空按钮 + 翻译中 loading + 点击进详情)

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
                ContentUnavailableView(
                    "还没有图片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("从相册选一张外文截图开始翻译")
                )
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
                    Color.black.opacity(0.25)
                    ProgressView("翻译中…")
                        .tint(.white)
                        .foregroundStyle(.white)
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

    // MARK: - iOS 设置样式的快捷操作组

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
                Text("一键添加「截图翻译」的快捷指令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Link(destination: iCloudShortcutURL) {
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

    // MARK: - 目标语言 Menu(放在 toolbar 右侧)

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

    // MARK: - 主流程

    private func loadImage(from item: PhotosPickerItem?) async {
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
            isTranslating = false
        case .apple:
            #if targetEnvironment(simulator)
            let mockTranslations = results.map { "【译】\($0.text)" }
            print("【翻译·模拟器 mock】")
            for (r, t) in zip(results, mockTranslations) {
                print("  原: \(r.text)")
                print("  译: \(t)")
            }
            renderTranslatedImage(original: original, translations: mockTranslations)
            isTranslating = false
            #else
            translationConfig = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: targetLanguage.rawValue)
            )
            // 真机 apple 翻译异步,留给 translate(using:) 关 isTranslating
            #endif
        case .llm:
            await runLLMTranslation(original: original, results: results)
            isTranslating = false
        }
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
        } catch {
            print("【默认模型翻译】失败: \(error.localizedDescription)")
            errorMessage = "默认模型翻译失败: \(error.localizedDescription)"
        }
    }

    private func translate(using session: TranslationSession) async {
        guard !ocrResults.isEmpty, let original = image else {
            isTranslating = false
            return
        }
        let requests = ocrResults.enumerated().map { i, r in
            TranslationSession.Request(sourceText: r.text, clientIdentifier: "\(i)")
        }
        do {
            let responses = try await session.translations(from: requests)
            let translations = responses.map { $0.targetText }
            print("【翻译】完成 \(responses.count) 段")
            for response in responses {
                print("  原: \(response.sourceText)")
                print("  译: \(response.targetText)")
            }
            renderTranslatedImage(original: original, translations: translations)
        } catch {
            print("【翻译】失败: \(error)")
            errorMessage = "Apple 翻译失败: \(error.localizedDescription)"
        }
        isTranslating = false
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
}

#Preview {
    ContentView()
        .modelContainer(for: HistoryItem.self, inMemory: true)
}
