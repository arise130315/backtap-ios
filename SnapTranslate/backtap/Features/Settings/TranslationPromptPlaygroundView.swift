import SwiftUI

struct TranslationPromptPlaygroundView: View {
    @AppStorage("debugTranslationSystemPrompt") private var customPrompt: String = ""

    // LLM 配置
    @AppStorage("llmBaseURL") private var baseURL: String = "https://api.openai.com/v1"
    @AppStorage("llmAPIKey")  private var apiKey: String  = ""
    @AppStorage("llmModel")   private var model: String   = "gpt-4o-mini"
    @AppStorage("targetLanguage") private var targetLangRaw: String = "zh-Hans"

    // 测试输入：每行一段文本
    @State private var inputText: String = "Hello, world!\nThis is a test sentence.\nClick Run to translate."
    @State private var isRunning = false
    @State private var result: String = ""
    @State private var elapsed: TimeInterval = 0
    @State private var errorMessage: String = ""

    private var targetLangName: String {
        TargetLanguage(rawValue: targetLangRaw)?.displayName ?? "简体中文"
    }

    var body: some View {
        Form {
            // ── 系统提示词 ──────────────────────────────────────────────
            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { customPrompt.isEmpty ? LLMTranslationService.defaultSystemPrompt : customPrompt },
                        set: { customPrompt = $0 }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 160)
                }
                HStack {
                    Text("\((customPrompt.isEmpty ? LLMTranslationService.defaultSystemPrompt : customPrompt).count) 字符")
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
                    Label("已覆盖默认值", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // ── 测试文本 ────────────────────────────────────────────────
            Section {
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .frame(minHeight: 100)
            } header: {
                Text("测试文本（每行一段）")
            } footer: {
                Text("目标语言：\(targetLangName)（在「设置」里修改）")
                    .font(.caption)
            }

            // ── 运行 ────────────────────────────────────────────────────
            Section {
                Button {
                    Task { await runTranslation() }
                } label: {
                    HStack {
                        Spacer()
                        if isRunning {
                            ProgressView().padding(.trailing, 6)
                            Text("翻译中…")
                        } else {
                            Image(systemName: "play.fill")
                            Text("运行翻译")
                        }
                        Spacer()
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
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
        .navigationTitle("翻译提示词")
    }

    private func runTranslation() async {
        let segments = inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return }
        isRunning = true
        errorMessage = ""
        result = ""
        let start = Date()
        do {
            let settings = LLMTranslationService.Settings(baseURL: baseURL, apiKey: apiKey, model: model)
            let translations = try await LLMTranslationService.translate(segments, targetLanguageDisplayName: targetLangName, settings: settings)
            result = zip(segments, translations)
                .map { "[\($0.0)]\n→ \($0.1)" }
                .joined(separator: "\n\n")
            elapsed = Date().timeIntervalSince(start)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}
