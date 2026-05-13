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
        let prompt = """
        把下面 \(texts.count) 段文字翻译成\(targetLanguageDisplayName)。严格规则:
        1. 必须返回正好 \(texts.count) 段译文,与原文一一对应,顺序不变。
        2. 不要合并多段,不要省略任何一段(即使是空字符串、纯符号如"•""-"或单字符,也要保留对应位置原样输出)。
        3. 数组长度必须等于 \(texts.count)。

        \(numbered)

        只返回 JSON,格式: {"translations": ["译文0", "译文1", ...]}
        不要任何额外文字、说明或 markdown 标记。
        """

        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0
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
        return aligned
    }
}
