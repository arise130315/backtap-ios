import AppIntents
import SwiftUI
import UIKit

/// 让 Shortcuts(操作按钮 / 背面双击 / 控制中心)调用的入口。
/// 系统执行完后会把 SnippetView 以半屏面板叠在用户当前 App 上方,不切走原 App。
struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译截图"
    static let description = IntentDescription("识别截图中的外文,保留原版面布局翻译显示")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "截图")
    var image: IntentFile

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let defaults = UserDefaults.standard
        let engineRaw = defaults.string(forKey: "translationEngine") ?? TranslationEngine.builtin.rawValue
        let engine = TranslationEngine(rawValue: engineRaw) ?? .builtin

        // AppIntent 路径无法用 Apple Translation(SwiftUI Environment 限制),
        // 所以 .builtin / .apple 都走默认模型(DefaultModelConfig);只有 .llm 才用用户填的自定义配置。
        let llmSettings: LLMTranslationService.Settings = {
            switch engine {
            case .llm:
                return LLMTranslationService.Settings(
                    baseURL: defaults.string(forKey: "llmBaseURL") ?? "https://api.openai.com/v1",
                    apiKey: defaults.string(forKey: "llmAPIKey") ?? "",
                    model: defaults.string(forKey: "llmModel") ?? "gpt-4o-mini"
                )
            case .builtin, .apple:
                return DefaultModelConfig.settings
            }
        }()

        let targetRaw = defaults.string(forKey: "targetLanguage") ?? "zh-Hans"
        let targetLangName = TargetLanguage(rawValue: targetRaw)?.displayName ?? "简体中文"

        let translated = try await TranslationPipeline.run(
            imageData: image.data,
            llmSettings: llmSettings,
            targetLanguageDisplayName: targetLangName
        )

        return .result(view: TranslationSnippetView(translatedImage: translated))
    }
}

/// 系统在前台 App 上方叠出的半屏面板。MVP 版只放图 + "保存到相册"按钮。
/// 注意:Snippet 容器会抢复杂手势,且 sheet 高度由系统控制(无法做"滑动放大")。
struct TranslationSnippetView: View {
    let translatedImage: UIImage

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                Image(uiImage: translatedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .padding(.horizontal, 14)
    }
}
