import Foundation
import UIKit

/// 调多模态 LLM 分析截图内容,返回 Markdown 格式的"内容 + 要点"总结。
/// 接口风格对齐 LLMTranslationService,走 OpenAI 兼容的 chat completions 协议。
enum ImageAnalysisService {
    struct Settings {
        var baseURL: String      // e.g. https://dashscope.aliyuncs.com/compatible-mode/v1
        var apiKey: String
        var model: String        // e.g. qwen3-vl-flash, gpt-4o-mini, claude-3-5-haiku
    }

    struct AnalysisError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// - Parameters:
    ///   - imageData: 截图二进制(任何常见格式都行,会被 base64 编码进 data URL)
    ///   - settings: API 配置
    /// - Returns: Markdown 文字,形如 "**内容**\n...\n\n**要点**\n- ...\n- ..."
    static func analyze(imageData: Data, settings: Settings) async throws -> String {
        guard !settings.apiKey.isEmpty,
              settings.apiKey != "PASTE_YOUR_QWEN_API_KEY_HERE" else {
            throw AnalysisError(message: "图片分析 API Key 未配置。请在 Secrets.swift 填入,或在「设置 → 图片分析」切换到自定义引擎填写。")
        }
        guard let url = URL(string: settings.baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions") else {
            throw AnalysisError(message: "Base URL 不合法")
        }

        // PNG 通用性最好;失败兜底为 JPEG。
        let imageMimeType: String
        let imageBase64: String
        if let png = UIImage(data: imageData)?.pngData() {
            imageMimeType = "image/png"
            imageBase64 = png.base64EncodedString()
        } else if let jpg = UIImage(data: imageData)?.jpegData(compressionQuality: 0.85) {
            imageMimeType = "image/jpeg"
            imageBase64 = jpg.base64EncodedString()
        } else {
            throw AnalysisError(message: "图片编码失败")
        }
        let dataURL = "data:\(imageMimeType);base64,\(imageBase64)"

        let systemPrompt = """
        你是一位擅长解读截图内容的助手。用户会发来手机或电脑的截图,你需要用简洁中文回答两件事:
        1. 这是什么 —— 截图的类型、来源 App 或主题(一句话)
        2. 关键要点 —— 3 至 5 条,每条不超过 30 字

        严格输出格式(Markdown):

        **内容**
        {一句话描述截图类型与主题,40 字以内}

        **要点**
        - {要点 1}
        - {要点 2}
        - {要点 3}
        - {要点 4(可选)}
        - {要点 5(可选)}

        强制规则:
        - 全程使用简体中文,即使截图原文是其他语言也用中文总结。
        - 全部输出加起来不超过 200 字。
        - 不要臆测画面之外的信息。
        - 不输出格式之外的任何内容(没有开场白、没有结束语)。
        - 如果截图主要是文章/对话/邮件,要点是内容要点;如果主要是 UI/产品页,要点是界面用途与功能。
        """

        let userContent: [[String: Any]] = [
            ["type": "text", "text": "请分析这张截图。"],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]

        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3,
            "max_tokens": 400
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError(message: "无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AnalysisError(message: "HTTP \(http.statusCode): \(bodyStr.prefix(500))")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let raw = parsed.choices.first?.message.content else {
            throw AnalysisError(message: "响应无 content")
        }

        return try sanitize(raw)
    }

    /// 清洗 LLM 偶发的格式偏差:剥代码块包裹 / 引导语 / 字数兜底 / 格式校验。
    private static func sanitize(_ raw: String) throws -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 剥 ```markdown 或 ``` 代码块包裹
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 剥常见引导句(行首)
        let leadInPatterns = ["好的,", "好的,", "以下是分析:", "以下是分析:", "分析如下:", "分析如下:"]
        for pat in leadInPatterns {
            if s.hasPrefix(pat) {
                s = String(s.dropFirst(pat.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 格式校验:必须包含 **内容** 标记
        guard s.contains("**内容**") else {
            throw AnalysisError(message: "分析结果格式异常,请重试或更换图片。")
        }

        // 字数兜底
        if s.count > 250 {
            s = String(s.prefix(250)) + "…"
        }

        return s
    }
}
