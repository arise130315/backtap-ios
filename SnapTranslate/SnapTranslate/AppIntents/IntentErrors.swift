import AppIntents

/// 两个 AppIntent 共用的错误类型。
///
/// 用户在「快捷指令」App 内直接点动作卡片(没拍截图作为输入)会触发 `.missingImage`,
/// 系统会用 `localizedStringResource` 的中文文案展示给用户,替代之前冷冰冰的
/// "无法解析图片"系统错误,引导用户回主 App 完成完整配置。
enum BacktapIntentError: Error, CustomLocalizedStringResourceConvertible {
    case missingImage

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingImage:
            return "需要先添加「拍摄屏幕快照」步骤把截图传给这个动作。请打开「快捷识屏」App,点击「添加快捷指令」一键导入完整流程,再绑到「轻点背面」或「操作按钮」即可使用。"
        }
    }
}
