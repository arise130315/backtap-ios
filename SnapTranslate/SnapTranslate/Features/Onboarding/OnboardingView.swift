import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page: Int = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPageView(data: .init(
                    icon: "doc.text.viewfinder",
                    title: "快捷翻译",
                    description: "对任意外文截图自动识别文字,在保留原版面布局的前提下翻译显示。"
                )).tag(0)

                OnboardingPageView(data: .init(
                    icon: "photo.badge.plus",
                    title: "主 App 内使用",
                    description: "点底部「从相册选图」选一张外文截图,1-3 秒后看到译图。所有翻译记录都会自动存到「历史」里,可随时回看。"
                )).tag(1)

                OnboardingShortcutPage().tag(2)

                OnboardingPageView(data: .init(
                    icon: "checkmark.shield.fill",
                    title: "开箱即用",
                    description: "App 内置「默认模型」翻译服务,选完图就能翻译,无需任何配置。\n\n如需切换,在「设置」里选「自定义」填你自己的 OpenAI 兼容 Key。"
                )).tag(3)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    hasSeenOnboarding = true
                }
            } label: {
                Text(page == pageCount - 1 ? "开始使用" : "下一页")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.tint, in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct OnboardingPageData {
    let icon: String
    let title: String
    let description: String
}

private struct OnboardingPageView: View {
    let data: OnboardingPageData
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: data.icon)
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text(data.title)
                .font(.title.bold())
            Text(data.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

private struct OnboardingShortcutPage: View {
    private let iCloudShortcutURL = URL(string: "https://www.icloud.com/shortcuts/dfe053b90fa349dc96664b485719b3f0")!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                    .padding(.top, 16)

                Text("一键截图翻译")
                    .font(.title.bold())

                Text("在任何外文 App 里按一下触发器,半屏面板就会叠在原 App 上方显示译图,不会被切走。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                Link(destination: iCloudShortcutURL) {
                    Label("一键导入快捷指令", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 14) {
                    Text("第 1 步:点上面按钮,iOS 弹「添加快捷指令」对话框 → 点添加")
                        .font(.subheadline)

                    Divider()

                    Text("第 2 步:任选一种触发方式绑上")
                        .font(.subheadline.bold())

                    triggerRow(
                        icon: "hand.tap.fill",
                        title: "轻点背面 (所有 iPhone)",
                        steps: "设置 → 辅助功能 → 触控 → 轻点背面\n→ 选「轻点两下」或「轻点三下」\n→ 滑到底找「翻译截图」→ 选中"
                    )

                    triggerRow(
                        icon: "button.programmable",
                        title: "操作按钮 (15 Pro / 16 Pro / 17 Pro)",
                        steps: "设置 → 操作按钮 → 滑到「快捷指令」\n→ 选「翻译截图」"
                    )

                    triggerRow(
                        icon: "switch.2",
                        title: "控制中心",
                        steps: "设置 → 控制中心 → 加「快捷指令」\n→ 下拉控制中心 → 选「翻译截图」"
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 16)

                Spacer(minLength: 24)
            }
        }
    }

    private func triggerRow(icon: String, title: String, steps: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(steps)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OnboardingView()
}
