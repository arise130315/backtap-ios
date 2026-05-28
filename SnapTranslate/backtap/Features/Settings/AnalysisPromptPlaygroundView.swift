import SwiftUI
import PhotosUI

struct AnalysisPromptPlaygroundView: View {
    // 存 UserDefaults；空字符串 = 使用代码默认值
    @AppStorage("debugAnalysisSystemPrompt") private var customPrompt: String = ""

    // LLM 配置（与主 App 共用同一组 UserDefaults key）
    @AppStorage("analysisBaseURL") private var baseURL: String = AnalysisDefaults.baseURL
    @AppStorage("analysisAPIKey") private var apiKey: String = ""
    @AppStorage("analysisModel")   private var model: String  = AnalysisDefaults.model

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isRunning = false
    @State private var result: String = ""
    @State private var elapsed: TimeInterval = 0
    @State private var errorMessage: String = ""

    private var effectivePrompt: String {
        customPrompt.isEmpty ? ImageAnalysisService.defaultSystemPrompt : customPrompt
    }

    var body: some View {
        Form {
            // ── 系统提示词 ──────────────────────────────────────────────
            Section {
                ZStack(alignment: .topLeading) {
                    if effectivePrompt.isEmpty {
                        Text("系统提示词…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 4)
                    }
                    TextEditor(text: Binding(
                        get: { customPrompt.isEmpty ? ImageAnalysisService.defaultSystemPrompt : customPrompt },
                        set: { customPrompt = $0 }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 180)
                }
                HStack {
                    Text("\(effectivePrompt.count) 字符")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !customPrompt.isEmpty {
                        Button("恢复默认") { customPrompt = "" }
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("系统提示词")
            } footer: {
                if !customPrompt.isEmpty {
                    Label("已覆盖默认值，运行时将使用上方内容", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // ── 测试图片 ────────────────────────────────────────────────
            Section("测试图片") {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("点击选择图片", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .onChange(of: selectedItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            selectedImage = img
                        }
                    }
                }
            }

            // ── 运行 ────────────────────────────────────────────────────
            Section {
                Button {
                    Task { await runAnalysis() }
                } label: {
                    HStack {
                        Spacer()
                        if isRunning {
                            ProgressView().padding(.trailing, 6)
                            Text("分析中…")
                        } else {
                            Image(systemName: "play.fill")
                            Text("运行分析")
                        }
                        Spacer()
                    }
                }
                .disabled(selectedImage == nil || isRunning)
            } footer: {
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // ── 输出结果 ────────────────────────────────────────────────
            if !result.isEmpty {
                Section {
                    Text(result)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("输出结果")
                        Spacer()
                        Text(String(format: "耗时 %.1fs", elapsed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("清除") { result = ""; elapsed = 0 }
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("分析提示词")
    }

    private func runAnalysis() async {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.85) else { return }
        isRunning = true
        errorMessage = ""
        result = ""
        let start = Date()
        do {
            let settings = ImageAnalysisService.Settings(baseURL: baseURL, apiKey: apiKey, model: model)
            let text = try await ImageAnalysisService.analyze(imageData: imageData, settings: settings, truncate: false)
            result = text
            elapsed = Date().timeIntervalSince(start)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}
