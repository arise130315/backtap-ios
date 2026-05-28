import AppIntents

/// 让 Shortcuts(操作按钮 / 背面三连击 / 控制中心)调用的入口:分析截图内容。
/// 用 ProvidesDialog 返回纯文字结果——iOS 26 对所有 ShowsSnippetView 都加了
/// 黄底+禁用图标的"未经验证第三方 UI"警告,只有 Dialog 走系统原生渲染管道不会被加警告。
struct AnalyzeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "快捷分析"
    static let description = IntentDescription("识别截图内容,生成简洁的中文总结")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "截图")
    var image: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 用户在「快捷指令」App 内直接点动作卡片(没拍截图作为输入)会走到这里——
        // 给一个引导文案,替代系统默认的"无法解析图片"错误。
        guard let image else {
            throw BacktapIntentError.missingImage
        }

        let defaults = UserDefaults.standard
        let engineRaw = defaults.string(forKey: "analysisEngine") ?? AnalysisEngine.builtin.rawValue
        let engine = AnalysisEngine(rawValue: engineRaw) ?? .builtin

        let settings: ImageAnalysisService.Settings = {
            switch engine {
            case .llm:
                return ImageAnalysisService.Settings(
                    baseURL: defaults.string(forKey: "analysisBaseURL") ?? AnalysisDefaults.baseURL,
                    apiKey: defaults.string(forKey: "analysisAPIKey") ?? "",
                    model: defaults.string(forKey: "analysisModel") ?? AnalysisDefaults.model
                )
            case .builtin:
                return AnalysisDefaults.settings
            }
        }()

        let result = try await AnalysisPipeline.run(imageData: image.data, settings: settings)
        return .result(dialog: IntentDialog(stringLiteral: formatForDialog(result.analysisText)))
    }

    /// iOS Dialog 渲染会把 Markdown `**...**` 原样显示,且把 `\n` 折叠成空格——
    /// 简单的字符替换搞不定 LLM 把一个 bullet 写成两行的情况(continuation 行没有 `- ` 前缀)。
    /// 这里按行解析重组:把每一行归到 header / paragraph / bullet,bullet 的 continuation
    /// 直接拼到当前 bullet 内部。最后用 U+2028 / U+2029 重新插入显式的行/段分隔符。
    private func formatForDialog(_ raw: String) -> String {
        enum Block {
            case header(String)
            case paragraph(String)
            case bullet(String)
        }

        var blocks: [Block] = []
        var pendingParagraph: String?
        var pendingBullet: String?

        func flush() {
            if let p = pendingParagraph {
                blocks.append(.paragraph(p))
                pendingParagraph = nil
            }
            if let b = pendingBullet {
                blocks.append(.bullet(b))
                pendingBullet = nil
            }
        }

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                flush()
                let title = String(trimmed.dropFirst(2).dropLast(2))
                blocks.append(.header("【\(title)】"))
            } else if trimmed.hasPrefix("- ") {
                flush()
                pendingBullet = String(trimmed.dropFirst(2))
            } else if pendingBullet != nil {
                // bullet 的 continuation 行:直接拼接,不换行
                pendingBullet! += trimmed
            } else {
                pendingParagraph = (pendingParagraph ?? "") + trimmed
            }
        }
        flush()

        var result = ""
        for block in blocks {
            if !result.isEmpty {
                switch block {
                case .header:
                    // 段落分隔 + 一个 NBSP 占位的空段落 + 再一个段落分隔 = 视觉上一行空行。
                    // 不用纯空格,会被 iOS 当 trim 掉,渲染不出空行。
                    result += "\u{2029}\u{00A0}\u{2029}"
                case .bullet, .paragraph: result += "\u{2028}"
                }
            }
            switch block {
            case .header(let s): result += s
            case .paragraph(let s): result += s
            case .bullet(let s):
                // 不加段首符号 + 空格;bullet 用 LINE SEPARATOR 连入 【要点】 这一段,
                // 让 iOS 把所有要点当成"一段很长的文本",触发贪婪 wrap,每行填满。
                result += s
            }
        }
        // 兜底把没识别到的 ** inline 粗体标记清掉
        return result.replacingOccurrences(of: "**", with: "")
    }
}
