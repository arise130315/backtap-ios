import SwiftUI

/// 教学半屏 sheet:教用户怎么把已添加的快捷指令绑定到「轻点背面」。
///
/// 设计取舍:iOS 不允许 App deeplink 到设置 App 的根目录或任意子页面
/// (`UIApplication.openSettingsURLString` 只能跳本 App 的设置页;`App-Prefs:` 私有 URL 审核会拒)。
/// 跳到本 App 设置页对用户是"跳错地方"的失望感,反而比不跳更差,所以直接不放跳转按钮 ——
/// 用户看完视频教学自己开设置 App 搜索更可控。
///
/// 排版:两条步骤文字在上,一个循环视频在下。用户先读懂"要做什么",再看怎么做。
/// 视频 `backtap-tutorial.mp4` 已压缩到 245 KB(540×720 H.264 baseline 静音),内嵌 bundle 直接播放。
struct BackTapTutorialSheet: View {
    /// 当前 tab —— 决定描述文案、步骤 2 选哪个快捷指令名。
    let mode: ContentMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(subtitleText)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        stepRow(
                            index: 1,
                            title: "在「设置」顶部搜索框搜「轻点背面」并选中「轻点两下」"
                        )
                        stepRow(
                            index: 2,
                            title: step2Text
                        )
                    }
                    .padding(.horizontal, 20)

                    LoopingVideoPlayer(resourceName: "backtap-tutorial")
                        .aspectRatio(540.0 / 720.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .padding(.horizontal, 20)

                    Spacer(minLength: 16)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("绑定轻点背面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        // 不用 xmark.circle.fill ——它自带填充圆,跟 iOS 26 toolbar 自动加的
                        // capsule 背景叠在一起会看起来像"2 层圆"。用裸 xmark 让系统自己的
                        // toolbar capsule 撑底,跟 Safari/邮件等系统 App 的关闭按钮一致。
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDetents([.fraction(0.88)])
        .presentationDragIndicator(.hidden)
    }

    /// 副文案,跟随当前 tab 切换。
    private var subtitleText: String {
        switch mode {
        case .translate: return "敲两下手机背面，在任意APP里都能一键识屏翻译"
        case .analyze:   return "绑定轻敲背面，在任意APP里都能一键识屏分析"
        }
    }

    /// 步骤 2 文案,跟随当前 tab 切换要选的快捷指令名。
    private var step2Text: String {
        switch mode {
        case .translate: return "滚动到列表底部，选中「识屏翻译」"
        case .analyze:   return "滚动到列表底部，选中「识屏分析」"
        }
    }

    /// 单行步骤:蓝底圆形数字 + 文字。不再带视频占位 —— 视频现在是 sheet 底部独立一段。
    private func stepRow(index: Int, title: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: .circle)

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
        }
    }
}

#Preview("翻译 tab") {
    Color.gray
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            BackTapTutorialSheet(mode: .translate)
        }
}

#Preview("分析 tab") {
    Color.gray
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            BackTapTutorialSheet(mode: .analyze)
        }
}
