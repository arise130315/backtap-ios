import SwiftUI
import UIKit

/// 教学半屏 sheet:教用户怎么把已添加的快捷指令绑定到「轻点背面」。
///
/// iOS 不允许 App 用 deeplink 直接跳「设置 → 辅助功能 → 触控 → 轻点背面」子页面
/// (`App-Prefs:` 这种私有 URL 早就被禁,提交会被审核拒),所以只能跳本 App 的
/// 设置页 + 配图文教学,让用户知道接下来该去哪。
///
/// 视频/动图素材后续真机录制后替换,目前用浅灰色 + 播放图标占位。
struct BackTapTutorialSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("敲两下手机背面,任意 App 里都能一键识屏翻译")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    stepCard(
                        index: 1,
                        title: "打开「设置」→「辅助功能」"
                    )
                    stepCard(
                        index: 2,
                        title: "选「触控」→「轻点背面」→「轻点两下」"
                    )
                    stepCard(
                        index: 3,
                        title: "选中你保存的「快捷翻译」或「快捷分析」"
                    )

                    Spacer(minLength: 16)
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("打开系统设置")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accentColor, in: .capsule)
                    }
                    Button("稍后再说") {
                        dismiss()
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(.regularMaterial)
            }
            .navigationTitle("3 步绑定背面双击")
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
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    /// 单个步骤卡:浅灰圆角矩形视频占位(16:9)+ 蓝底步骤数字 + 文字。
    private func stepCard(index: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                Image(systemName: "play.rectangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

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
        .padding(.horizontal, 20)
    }
}

#Preview {
    Color.gray
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            BackTapTutorialSheet()
        }
}
