import UIKit

/// 封装"image → 多模态 LLM 分析 → Markdown 文字"流程,供 AppIntent 端外入口与 ContentView 主页复用。
enum AnalysisPipeline {
    enum PipelineError: LocalizedError {
        case invalidImage
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "无法解析图片"
            }
        }
    }

    /// - Parameters:
    ///   - imageData: 输入图片数据
    ///   - settings: 多模态 LLM 配置(baseURL/apiKey/model)
    ///   - truncate: 见 `ImageAnalysisService.analyze`,AppIntent 默认 true,主 App 传 false
    /// - Returns: Markdown 格式的分析文字 + 渲染好的原图(供历史保存)
    static func run(
        imageData: Data,
        settings: ImageAnalysisService.Settings,
        truncate: Bool = true
    ) async throws -> (image: UIImage, analysisText: String) {
        guard let image = UIImage(data: imageData) else {
            throw PipelineError.invalidImage
        }
        let text = try await ImageAnalysisService.analyze(imageData: imageData, settings: settings, truncate: truncate)
        return (image, text)
    }
}
