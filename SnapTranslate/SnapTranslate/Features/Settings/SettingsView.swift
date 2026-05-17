import SwiftUI

/// 翻译引擎枚举的 raw 值,跟 @AppStorage 的 String 对应。
enum TranslationEngine: String, CaseIterable, Identifiable {
    case builtin
    case llm
    nonisolated var id: String { rawValue }
    nonisolated var displayName: String {
        switch self {
        case .builtin: return "默认"
        case .llm: return "自定义"
        }
    }
}

/// 目标语言枚举。
enum TargetLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    nonisolated var id: String { rawValue }
    nonisolated var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }
}

struct SettingsView: View {
    // 翻译
    @AppStorage("translationEngine") private var engineRaw: String = TranslationEngine.builtin.rawValue
    @AppStorage("llmBaseURL") private var llmBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("llmAPIKey") private var llmAPIKey: String = ""
    @AppStorage("llmModel") private var llmModel: String = "gpt-4o-mini"

    // 图片分析
    @AppStorage("analysisEngine") private var analysisEngineRaw: String = AnalysisEngine.builtin.rawValue
    @AppStorage("analysisBaseURL") private var analysisBaseURL: String = AnalysisDefaults.baseURL
    @AppStorage("analysisAPIKey") private var analysisAPIKey: String = ""
    @AppStorage("analysisModel") private var analysisModel: String = AnalysisDefaults.model

    var body: some View {
        Form {
            Section {
                Picker("翻译内容", selection: $engineRaw) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }
                Picker("分析内容", selection: $analysisEngineRaw) {
                    ForEach(AnalysisEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }
            } header: {
                Text("模型")
            } footer: {
                Text("建议常规情况下使用默认模型即可,支持选择自定义其他大模型。")
            }

            if engineRaw == TranslationEngine.llm.rawValue {
                Section {
                    LabeledContent("Base URL") {
                        TextField("https://api.openai.com/v1", text: $llmBaseURL)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $llmAPIKey)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("模型") {
                        TextField("gpt-4o-mini", text: $llmModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("翻译 · LLM 配置")
                } footer: {
                    Text("兼容 OpenAI Chat Completions 协议的服务都可填,例如 OpenRouter、DeepSeek、自部署服务。Key 仅本机存储。")
                }
            }

            if analysisEngineRaw == AnalysisEngine.llm.rawValue {
                Section {
                    LabeledContent("Base URL") {
                        TextField(AnalysisDefaults.baseURL, text: $analysisBaseURL)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $analysisAPIKey)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("模型") {
                        TextField(AnalysisDefaults.model, text: $analysisModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("图片分析 · LLM 配置")
                } footer: {
                    Text("必须填支持图片输入的多模态模型(如 qwen3-vl-plus、gpt-4o-mini、claude-3-5-haiku、glm-4v)。Key 仅本机存储。")
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "v1.0")
            }
        }
        .navigationTitle("设置")
    }
}
