import SwiftUI

struct DeveloperOptionsView: View {
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section("提示词调试") {
                NavigationLink("分析提示词") {
                    AnalysisPromptPlaygroundView()
                }
                NavigationLink("翻译提示词") {
                    TranslationPromptPlaygroundView()
                }
            }

            Section("API 配置") {
                NavigationLink("API 管理面板") {
                    APIManagementView()
                }
            }

            Section("工具") {
                NavigationLink("UserDefaults 查看器") {
                    UserDefaultsInspectorView()
                }
                Button("清除所有 UserDefaults", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
        .navigationTitle("开发者选项")
        .confirmationDialog(
            "确认清除全部 UserDefaults？设置项将全部还原为默认值，此操作不可恢复。",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
            }
        }
    }
}
