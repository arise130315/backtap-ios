import Foundation
import UIKit

/// 调多模态 LLM 分析截图内容,返回 Markdown 格式的"内容 + 要点"总结。
/// 接口风格对齐 LLMTranslationService,走 OpenAI 兼容的 chat completions 协议。
///
/// 提供两个方法:
/// - `analyze(...)` 非流式:一次拿到完整结果(AppIntent 端外路径走这条,因 iOS Dialog 渲染管线不支持流式)
/// - `analyzeStream(...)` 流式 SSE:每个 yield 是当前累计全文(主 App 内 ScrollView 走这条,逐字显示)
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

    // MARK: - 公开方法

    /// 非流式分析(端外 AppIntent 用),一把拿完整结果。
    /// - Parameters:
    ///   - imageData: 截图二进制(任何常见格式都行,会被 base64 编码进 data URL)
    ///   - settings: API 配置
    ///   - truncate: true 时 sanitize 会把超过 250 字符的结果截断 + 加 …(给 AppIntent Dialog 用);
    ///     false 时返回完整 LLM 输出(主 App ScrollView 自己滚动展示)
    /// - Returns: Markdown 文字,形如 "**内容**\n...\n\n**要点**\n- ...\n- ..."
    static func analyze(imageData: Data, settings: Settings, truncate: Bool = true) async throws -> String {
        try validate(settings)
        let url = try chatCompletionsURL(from: settings)
        let request = try buildRequest(url: url, settings: settings, imageData: imageData, stream: false)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ensureSuccess(response: response, body: data)

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
        return try sanitize(raw, truncate: truncate)
    }

    /// 流式分析(主 App 用),走 SSE 协议。
    /// **每个 yield 是当前累计的完整文本**(可以直接赋给 SwiftUI @State 让 UI 替换显示)。
    /// 流结束前最后一次 yield 是 sanitize 后的干净文本(去掉 ``` 包裹 / 引导语 / 校验格式)——
    /// 调用方什么都不用做,持续 `analysisText = chunk` 就行,最后一帧会"snap"到干净版本。
    /// - Parameter truncate: 跟非流式同义,主 App 传 false
    static func analyzeStream(
        imageData: Data,
        settings: Settings,
        truncate: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try validate(settings)
                    let url = try chatCompletionsURL(from: settings)
                    let request = try buildRequest(url: url, settings: settings, imageData: imageData, stream: true)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try ensureSuccess(response: response, body: nil)

                    // SSE 增量结构:OpenAI 兼容协议下,每个 chunk choices[0].delta.content 是新增 token
                    struct StreamChunk: Decodable {
                        struct Choice: Decodable {
                            struct Delta: Decodable { let content: String? }
                            let delta: Delta
                        }
                        let choices: [Choice]
                    }

                    var fullText = ""
                    for try await line in bytes.lines {
                        // SSE 每个事件块以 "data: ..." 开头,中间可能有空行,结束有 "data: [DONE]"
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let payloadData = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: payloadData),
                              let delta = chunk.choices.first?.delta.content,
                              !delta.isEmpty else { continue }
                        fullText += delta
                        continuation.yield(fullText) // 累计全文,UI 直接替换
                    }

                    // 流结束:做一次 sanitize(剥 ``` 包裹 / 引导语 / 格式校验 / 可选截断),
                    // 让最后一帧 UI "snap" 到干净版本
                    let clean = try sanitize(fullText, truncate: truncate)
                    continuation.yield(clean)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 私有 helpers(stream / 非 stream 共用)

    private static let systemPrompt: String = """
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

    private static func validate(_ settings: Settings) throws {
        guard !settings.apiKey.isEmpty,
              settings.apiKey != "PASTE_YOUR_QWEN_API_KEY_HERE" else {
            throw AnalysisError(message: "图片分析 API Key 未配置。请在 Secrets.swift 填入,或在「设置 → 图片分析」切换到自定义引擎填写。")
        }
    }

    private static func chatCompletionsURL(from settings: Settings) throws -> URL {
        guard let url = URL(string: settings.baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions") else {
            throw AnalysisError(message: "Base URL 不合法")
        }
        return url
    }

    /// 图片 → data URL。
    /// 关键防御:**降采样到最大边 2048pt + 优先 JPEG 0.85**,避免 LLM API payload 超限报 HTTP 400。
    /// 原 PNG 优先版本对 iPhone 12MP 原图(3024×4032)会编码出 20-50MB,base64 后 1.33x 直接爆。
    /// 所有调用方(主 App / AppIntent 端外)都过这里,不需要在 call site 重复降采样。
    private static func encodeImageDataURL(_ imageData: Data) throws -> String {
        guard let uiImage = UIImage(data: imageData) else {
            throw AnalysisError(message: "图片解码失败")
        }
        // 降采样:相机原图 12MP 直接上传 LLM 又慢又容易超限。
        // 缩到最大边 2048pt 后 ~1.5-2MP,LLM 识别精度仍然足够,体积小 5-10 倍。
        let downsampled = downsample(uiImage, maxDimension: 2048)
        // JPEG 优先(压缩比好,体积小):0.85 质量是常用甜区,LLM 识别看不出差别。
        // 极少数 LLM 只吃 PNG 时可以加 fallback,实测主流 (Qwen/GPT-4o/Claude) 都支持 JPEG。
        if let jpg = downsampled.jpegData(compressionQuality: 0.85) {
            return "data:image/jpeg;base64,\(jpg.base64EncodedString())"
        } else if let png = downsampled.pngData() {
            return "data:image/png;base64,\(png.base64EncodedString())"
        } else {
            throw AnalysisError(message: "图片编码失败")
        }
    }

    /// 降采样到最大边 maxDimension,保持长宽比。原图小于阈值时原图返回(不放大)。
    /// 跟 ContentView.downsample 逻辑一致,这里独立一份让 service 自包含,
    /// 任何调用方(主 App / AppIntent / Share Extension)都不依赖 ContentView 的静态方法。
    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 构 POST 请求,stream=true/false 由调用方决定
    private static func buildRequest(
        url: URL,
        settings: Settings,
        imageData: Data,
        stream: Bool
    ) throws -> URLRequest {
        let dataURL = try encodeImageDataURL(imageData)
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "请分析这张截图。"],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]
        var body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3,
            "max_tokens": 400
        ]
        if stream {
            body["stream"] = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return request
    }

    /// HTTP 状态码校验。`body` 为 nil 表示流式 SSE 模式拿不到完整 body 字符串(只截 statusCode)
    private static func ensureSuccess(response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError(message: "无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body, let bodyStr = String(data: body, encoding: .utf8) {
                throw AnalysisError(message: "HTTP \(http.statusCode): \(bodyStr.prefix(500))")
            } else {
                throw AnalysisError(message: "HTTP \(http.statusCode)")
            }
        }
    }

    /// 清洗 LLM 偶发的格式偏差:剥代码块包裹 / 引导语 / 字数兜底 / 格式校验。
    /// - Parameter truncate: 是否对超过 250 字符截断(AppIntent Dialog 走 true,主 App 走 false)
    private static func sanitize(_ raw: String, truncate: Bool) throws -> String {
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

        // 字数兜底(仅 truncate=true 时启用,主 App 不截断让 ScrollView 完整显示)
        if truncate, s.count > 250 {
            s = String(s.prefix(250)) + "…"
        }

        return s
    }
}
