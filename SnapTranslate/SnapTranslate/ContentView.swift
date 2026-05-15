//
//  ContentView.swift
//  SnapTranslate
//
//  Created by 杨剑峰 on 2026/5/12.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var context

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
            .navigationTitle("快捷翻译")
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
        .onChange(of: targetLanguage) { _, newValue in
            // 同步写回 UserDefaults,供 AppIntent 端外入口读取
            UserDefaults.standard.set(newValue.rawValue, forKey: "targetLanguage")
            // 如果当前已有图片和 OCR 结果,用新目标语言重新翻译并渲染
            if let original = image, !ocrResults.isEmpty {
                Task { await dispatchTranslation(original: original, results: ocrResults) }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadImage(from: newItem) }
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
