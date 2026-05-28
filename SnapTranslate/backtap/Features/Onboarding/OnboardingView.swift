//
//  OnboardingView.swift
//  backtap
//
//  启动引导页。改版后只有「快捷翻译」「快捷分析」两页。
//  Figma:232:2763(翻译) / 232:2871(分析),画板 402×874。
//  布局:顶部 92pt → 视频 338×496 → 间距 40 → 标题 28pt SemiBold → 间距 12 → 副标题 16pt @50% 透明。
//  交互:滑动翻页(TabView .page),最后一页继续向左滑动 → 进入主页(hasSeenOnboarding = true)。
//

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page: Int = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            videoName: "onboarding-translate",
            title: "快捷翻译",
            description: "轻敲背面,对当前屏幕的外文进行识别,保留原版面布局的前提下翻译显示。"
        ),
        OnboardingPage(
            videoName: "onboarding-analyze",
            title: "快捷分析",
            description: "轻敲背面,支持对当前屏幕内容进行快速智能分析解读。"
        )
    ]

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    OnboardingPageView(page: pages[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(
                // 最后一页继续左滑 → 进入主页
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if page == pages.count - 1 && value.translation.width < -50 {
                            withAnimation(.easeOut(duration: 0.3)) {
                                hasSeenOnboarding = true
                            }
                        }
                    }
            )

            // 自定义底部翻页器(Figma:58×24 胶囊 #F5F5F5,8×8 圆点,active 白 / inactive #B7B7B7)
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, 4) // 原 16,翻页器下移 12pt → 4
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 10) {
            ForEach(pages.indices, id: \.self) { idx in
                Circle()
                    .fill(idx == page
                          ? Color.white
                          : Color(red: 0xB7 / 255.0, green: 0xB7 / 255.0, blue: 0xB7 / 255.0))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF5 / 255.0), in: .capsule)
    }
}

// MARK: - Page model

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let videoName: String
    let title: String
    let description: String
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage

    /// 视频原始尺寸 1108×1864,宽高比 ≈ 0.594
    private static let videoAspectRatio: CGFloat = 1108.0 / 1864.0

    var body: some View {
        // 视频高度 = 屏幕高度 × 64%,宽度按视频原始比例等比缩放
        let videoHeight = UIScreen.main.bounds.height * 0.64
        let videoWidth = videoHeight * Self.videoAspectRatio

        return VStack(spacing: 0) {
            Spacer()
                .frame(height: 32) // 顶部 Spacer

            // 视频区:循环播放 / 静音 / 无 controls
            LoopingVideoPlayer(resourceName: page.videoName, videoGravity: .resizeAspect)
                .frame(width: videoWidth, height: videoHeight)

            Spacer()
                .frame(height: 4) // 视频 → 标题间距

            // 标题:PingFang SC SemiBold 28 / lh 36 / 黑色
            Text(page.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.black)

            Spacer()
                .frame(height: 12)

            // 副标题:PingFang SC Regular 16 / lh 24 / 黑色 @50%
            Text(page.description)
                .font(.system(size: 16))
                .foregroundColor(.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4) // size 16 默认 lh ≈ 19,加 4 ≈ 23 接近 Figma 24
                .frame(width: 338)

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
