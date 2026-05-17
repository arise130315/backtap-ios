import Foundation

/// 图片分析引擎枚举,raw 跟 @AppStorage 的 String 对应。
enum AnalysisEngine: String, CaseIterable, Identifiable {
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

/// 「默认模型」配置:固定走阿里千问 qwen3-vl-flash,Key 从 Secrets.swift 读取(已 .gitignore)。
///
/// ⚠️ Secrets.swift 不入库。要让默认模型可用,必须先复制 Secrets.swift.example 为 Secrets.swift
/// 并填入你在 https://bailian.console.aliyun.com 创建的 API Key。
enum AnalysisDefaults {
    nonisolated static let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    nonisolated static let model = "qwen3-vl-flash"

    nonisolated static var settings: ImageAnalysisService.Settings {
        ImageAnalysisService.Settings(baseURL: baseURL, apiKey: Secrets.qwenAPIKey, model: model)
    }
}
