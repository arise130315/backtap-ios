//
//  BacktapApp.swift
//  backtap
//
//  Created by 杨剑峰 on 2026/5/12.
//

import SwiftUI
import SwiftData

@main
struct BacktapApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 主界面
                ContentView()

                // Onboarding:改用 ZStack 叠加 + 自定义 transition,
                // 解除时向左滑出(替代 fullScreenCover 默认"向下收起")
                if !hasSeenOnboarding && !showSplash {
                    OnboardingView()
                        .transition(.asymmetric(
                            insertion: .opacity, // splash 渐隐完淡入显示
                            removal: .move(edge: .leading) // 用户左滑触发关闭时,整页向左滑出
                        ))
                        .zIndex(2)
                }

                // 启动页:每次冷启动显示 2.5 秒,渐隐消失
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation(.easeOut(duration: 0.4)) {
                                showSplash = false
                            }
                        }
                }
            }
        }
        .modelContainer(for: HistoryItem.self)
    }
}
