import AppIntents

/// 把两个 Intent 注册成系统级 App Shortcut。安装本 App 后,用户无需导入 iCloud 链接,
/// 在「快捷指令」App 的「应用」分类、Spotlight 搜索、Siri 里就能直接发现并使用这两个动作。
///
/// 注意:
/// - 每条 phrase 必须包含 `\(.applicationName)` 占位符,这是 AppIntents 框架的硬性要求,
///   缺了编译器会报错。运行时 `applicationName` 会被替换成 App 显示名「快捷识屏」。
/// - 两个 Intent 都有 `image: IntentFile` 必传参数,所以 Siri 直接喊触发会失败
///   (Siri 没办法自动拍当前屏幕的截图)。phrases 主要作用是:
///     1. 让动作出现在「快捷指令 → 应用 → 快捷识屏」分类下,用户拼复合 Shortcut 时能搜到
///     2. Spotlight 搜索时显示动作卡片
/// - 保留 ContentView 里的 iCloud Shortcut 链接,作为新手"一键导入完整复合 Shortcut
///   (含拍摄屏幕快照 + 调用本 Intent)"的最短路径。
struct BacktapAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateScreenshotIntent(),
            phrases: [
                "用\(.applicationName)翻译屏幕",
                "用\(.applicationName)翻译截图",
                "用\(.applicationName)快捷翻译"
            ],
            shortTitle: "快捷翻译",
            systemImageName: "text.viewfinder"
        )

        AppShortcut(
            intent: AnalyzeScreenshotIntent(),
            phrases: [
                "用\(.applicationName)分析屏幕",
                "用\(.applicationName)分析截图",
                "用\(.applicationName)快捷分析"
            ],
            shortTitle: "快捷分析",
            systemImageName: "wand.and.sparkles"
        )
    }
}
