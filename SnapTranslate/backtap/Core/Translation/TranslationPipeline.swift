import UIKit

/// 封装一整套"image → OCR → 翻译 → 渲染"流程,供 AppIntent / Action Extension 等非 SwiftUI 上下文复用。
enum TranslationPipeline {
    enum PipelineError: LocalizedError {
        case invalidImage
        case noTextRecognized
        case llmNotConfigured
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "无法解析图片"
            case .noTextRecognized: return "未识别到文字"
            case .llmNotConfigured: return "翻译服务未配置"
            }
        }
    }

    /// - Parameters:
    ///   - imageData: 输入图片数据(任意常见格式)
    ///   - llmSettings: LLM 翻译配置;为空 / Key 为空时降级到 mock 译文
    ///   - targetLanguageDisplayName: 目标语言中文名,例如 "简体中文"
    /// - Returns: 保留原版面布局、覆盖译文的 UIImage
    static func run(
        imageData: Data,
        llmSettings: LLMTranslationService.Settings? = nil,
        targetLanguageDisplayName: String = "简体中文"
    ) async throws -> UIImage {
        guard let image = UIImage(data: imageData) else {
            throw PipelineError.invalidImage
        }

        let results = try await VisionOCRService.recognize(in: image)
        guard !results.isEmpty else {
            throw PipelineError.noTextRecognized
        }

        guard let llmSettings, !llmSettings.apiKey.isEmpty else {
            throw PipelineError.llmNotConfigured
        }
        // LLM 失败直接抛错(不再 mock 兜底),让 AppIntent 端外显示明确错误,而不是渲染误导性的"【译】"前缀。
        // 唯一例外:SameLanguageError(源==目标语言)不算失败,直接返原图。
        let translations: [String]
        do {
            translations = try await LLMTranslationService.translate(
                results.map { $0.text },
                targetLanguageDisplayName: targetLanguageDisplayName,
                settings: llmSettings
            )
        } catch is LLMTranslationService.SameLanguageError {
            return image
        }

        let blocks = zip(results, translations).map {
            LayoutPreservingRenderer.Block(normalizedBox: $0.0.boundingBox, translatedText: $0.1)
        }
        return LayoutPreservingRenderer.render(originalImage: image, blocks: blocks)
    }
}
