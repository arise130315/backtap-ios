import Foundation

/// 调用 OpenAI 兼容协议的 Chat Completions API,批量翻译多段文字。
enum LLMTranslationService {
    struct Settings {
        var baseURL: String      // e.g. https://api.openai.com/v1
        var apiKey: String
        var model: String        // e.g. gpt-4o-mini, claude-3-5-sonnet-latest
    }

    struct LLMError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 不是真错误:LLM 返回内容与原文高度一致(通常是源语言==目标语言,或 LLM 拒绝翻译)。
    /// 上层应当静默吞掉,直接给用户看原图,而不是弹"翻译失败"提示。
    struct SameLanguageError: Error {}

    static let defaultSystemPrompt: String = """
        You are a professional translator. Translate every input segment into the user's target language.

        Strict rules:
        1. ALWAYS translate. Never echo the source text. The source may be in any language (Chinese, English, Japanese, Korean, or mixed) — you must always produce output in the target language.
        2. Even if the source is already in the same language as the target, rephrase it in the target language. Do not return identical text.
        3. Keep as-is only: pure numbers (e.g. "5.43"), URLs, emails, pure symbols (•, -, +), and well-known international proper nouns (NVIDIA, iOS, Apple, GDP, Python).
        4. Output ONLY a JSON object: {"translations": ["...", "..."]}. No prose, no markdown.
        """

    static func translate(_ texts: [String], targetLanguageDisplayName: String, settings: Settings) async throws -> [String] {
        guard !settings.apiKey.isEmpty else {
            throw LLMError(message: "API Key 未配置")
        }
        guard let url = URL(string: settings.baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions") else {
            throw LLMError(message: "Base URL 不合法")
        }

        let numbered = texts.enumerated()
            .map { "[\($0.offset)] \($0.element)" }
            .joined(separator: "\n")

        #if DEBUG
        let overridePrompt = UserDefaults.standard.string(forKey: "debugTranslationSystemPrompt") ?? ""
        let systemPrompt = overridePrompt.isEmpty ? Self.defaultSystemPrompt : overridePrompt
        #else
        let systemPrompt = Self.defaultSystemPrompt
        #endif

        let userPrompt = """
        目标语言 / Target language: \(targetLanguageDisplayName)

        请将以下 \(texts.count) 段文本翻译成 \(targetLanguageDisplayName)。
        **无论原文是中文、英文还是混合,都必须翻译成 \(targetLanguageDisplayName),不要保留原文。**

        \(numbered)

        返回 JSON: {"translations": ["译文0", "译文1", ...]},数组长度 = \(texts.count)。
        """

        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError(message: "无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMError(message: "HTTP \(http.statusCode): \(bodyStr.prefix(500))")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = parsed.choices.first?.message.content else {
            throw LLMError(message: "响应无 content")
        }

        struct TranslationsPayload: Decodable { let translations: [String] }
        let payload: TranslationsPayload
        do {
            payload = try JSONDecoder().decode(TranslationsPayload.self, from: Data(content.utf8))
        } catch {
            throw LLMError(message: "解析 LLM JSON 失败: \(content.prefix(300))")
        }

        // 软兜底:LLM 偶尔会合并 / 跳过纯符号段,导致条数不一致。
        // 短了用原文补齐,长了截断,保证调用方拿到 texts.count 段译文。
        var aligned = payload.translations
        if aligned.count < texts.count {
            let missingStart = aligned.count
            print("⚠️ LLM 译文条数(\(aligned.count))少于原文(\(texts.count)),用原文兜底填补 \(texts.count - missingStart) 段")
            aligned.append(contentsOf: texts[missingStart..<texts.count])
        } else if aligned.count > texts.count {
            print("⚠️ LLM 译文条数(\(aligned.count))多于原文(\(texts.count)),截断到 \(texts.count) 段")
            aligned = Array(aligned.prefix(texts.count))
        }

        // 未翻译检测:LLM 偶尔会拒绝翻译,直接原样返回。如果 70% 以上段落与原文完全一致
        // 且至少有 3 段非空文本可比较,认为不需要翻译(源语言==目标语言)或 LLM 拒绝翻译。
        // 抛 SameLanguageError,上层静默吞掉、直接显示原图,避免误以为"翻译失败"。
        let comparable = zip(texts, aligned).filter { !$0.0.isEmpty }
        if comparable.count >= 3 {
            let identicalCount = comparable.filter { $0.0 == $0.1 }.count
            let identicalRate = Double(identicalCount) / Double(comparable.count)
            print("🔍 LLM 翻译率检查: \(identicalCount)/\(comparable.count) 段与原文一致 (\(Int(identicalRate * 100))%)")
            if identicalRate > 0.7 {
                throw SameLanguageError()
            }
        }
        return aligned
    }
}
