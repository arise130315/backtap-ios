import SwiftUI

/// 半屏 sheet:从服务商 `/models` 端点拉可用模型列表,用户选中即写回 binding。
/// 失败时(Qwen 等不支持)显示错误 + 让用户回去手动输入。
struct ModelPickerSheet: View {
    let baseURL: String
    let apiKey: String
    @Binding var selectedModel: String

    @Environment(\.dismiss) private var dismiss
    @State private var models: [String] = []
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载模型列表…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("无法加载模型列表")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Text("可能是此服务商不支持 `/models` 端点，请回上一页手动输入。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("重试") { Task { await load() } }
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(models, id: \.self) { id in
                            Button {
                                selectedModel = id
                                dismiss()
                            } label: {
                                HStack {
                                    Text(id)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if id == selectedModel {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                if !models.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        isLoading = true
        errorMessage = ""
        do {
            models = try await ModelListService.fetch(baseURL: baseURL, apiKey: apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
