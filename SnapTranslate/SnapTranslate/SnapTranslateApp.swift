//
//  SnapTranslateApp.swift
//  SnapTranslate
//
//  Created by 杨剑峰 on 2026/5/12.
//

import SwiftUI
import SwiftData

@main
struct SnapTranslateApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView()
                        .interactiveDismissDisabled()
                }
        }
        .modelContainer(for: HistoryItem.self)
    }
}
