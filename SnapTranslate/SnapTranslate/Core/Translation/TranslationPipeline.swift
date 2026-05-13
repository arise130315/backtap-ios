import UIKit

/// 封装一整套"image → OCR → 翻译 → 渲染"流程,供 AppIntent / Action Extension 等非 SwiftUI 上下文复用。
enum TranslationPipeline {
    enum PipelineError: LocalizedError {
        case invalidImage
        case noTextRecognized
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "无法解析图片"
            case .noTextRecognized: return "未识别到文字"
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

        let translations: [String]
        if let llmSettings, !llmSettings.apiKey.isEmpty {
            do {
                translations = try await LLMTranslationService.translate(
                    results.map { $0.text },
                    targetLanguageDisplayName: targetLanguageDisplayName,
                    settings: llmSettings
                )
            } catch {
                // LLM 失败,降级 mock 译文以保证 Snippet 仍能展示
                print("【Pipeline】LLM 失败,降级 mock: \(error.localizedDescription)")
                translations = results.map { "【译】\($0.text)" }
            }
        } else {
            translations = results.map { "【译】\($0.text)" }
        }

        let blocks = zip(results, translations).map {
            LayoutPreservingRenderer.Block(normalizedBox: $0.0.boundingBox, translatedText: $0.1)
        }
        return LayoutPreservingRenderer.render(originalImage: image, blocks: blocks)
    }
}
