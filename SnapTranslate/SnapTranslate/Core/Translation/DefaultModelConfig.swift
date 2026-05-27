import Foundation

/// 「默认模型」配置:固定走 DeepSeek chat,App 内置无需用户配置。
///
/// ⚠️ 安全提示
/// API Key 硬编码进 App 会随 IPA 一起分发,任何人反编译都能拿到。
/// 当前为「自用/调试」方案;若计划上架 App Store,必须改成调用自己搭的代理服务器(如 Cloudflare Workers)。
enum DefaultModelConfig {
    nonisolated static let baseURL = "https://api.deepseek.com"

    /// ⬇️ 用 Xcode 打开本文件,把下面这行的 PASTE_YOUR_DEEPSEEK_API_KEY_HERE 替换成你的真实 Key
    /// 不要 commit 这个文件到公共仓库(建议加入 .gitignore 或使用 build setting 注入)
    nonisolated static let apiKey = "sk-cd3e1358b98e4a3fa3ec2a2adec9799b"

    nonisolated static let model = "deepseek-chat"

    nonisolated static var settings: LLMTranslationService.Settings {
        #if DEBUG
        let d = UserDefaults.standard
        let urlOverride = d.string(forKey: "debugTranslationDefaultBaseURL") ?? ""
        let keyOverride = d.string(forKey: "debugTranslationDefaultAPIKey") ?? ""
        let modelOverride = d.string(forKey: "debugTranslationDefaultModel") ?? ""
        return LLMTranslationService.Settings(
            baseURL: urlOverride.isEmpty ? baseURL : urlOverride,
            apiKey: keyOverride.isEmpty ? apiKey : keyOverride,
            model: modelOverride.isEmpty ? model : modelOverride
        )
        #else
        return LLMTranslationService.Settings(baseURL: baseURL, apiKey: apiKey, model: model)
        #endif
    }
}
