import SwiftUI

/// 开发者面板:覆盖「默认模型」的 API 配置(分析走千问 / 翻译走 DeepSeek)。
/// - 三个字段任一非空即视为"已覆盖",`AnalysisDefaults.settings` / `DefaultModelConfig.settings`
///   会读 UserDefaults 拿覆盖值,空字符串自动回落到代码硬编码默认。
/// - 翻译段:支持查 DeepSeek 余额(`/user/balance`)。
/// - 两段都支持点开模型选择 sheet(`/models` 端点;Qwen 不支持会显示错误)。
struct APIManagementView: View {
    // 分析默认模型 - 覆盖值(空字符串 = 使用代码默认)
    @AppStorage("debugAnalysisDefaultBaseURL") private var analysisBaseURL: String = ""
    @AppStorage("debugAnalysisDefaultAPIKey")  private var analysisAPIKey: String  = ""
    @AppStorage("debugAnalysisDefaultModel")   private var analysisModel: String   = ""

    // 翻译默认模型 - 覆盖值
    @AppStorage("debugTranslationDefaultBaseURL") private var translationBaseURL: String = ""
    @AppStorage("debugTranslationDefaultAPIKey")  private var translationAPIKey: String  = ""
    @AppStorage("debugTranslationDefaultModel")   private var translationModel: String   = ""

    // 模型选择 sheet 控制
    @State private var showAnalysisModelPicker = false
    @State private var showTranslationModelPicker = false

    // DeepSeek 余额
    @State private var balanceText: String = ""
    @State private var isLoadingBalance = false
    @State private var balanceError: String = ""

    var body: some View {
        Form {
            // ── 分析默认模型 ────────────────────────────────────────────
            Section {
                LabeledContent("当前使用") {
                    Text(effectiveAnalysisModel)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.purple)
                }
                LabeledContent("Base URL") {
                    TextField(AnalysisDefaults.baseURL, text: $analysisBaseURL)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.callout, design: .monospaced))
                }
                LabeledContent("API Key") {
                    SecureField("使用内置 Key", text: $analysisAPIKey)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.callout, design: .monospaced))
                }
                LabeledContent("模型") {
                    HStack(spacing: 8) {
                        TextField(AnalysisDefaults.model, text: $analysisModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.callout, design: .monospaced))
                        Button {
                            showAnalysisModelPicker = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.callout)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 余额查询:Qwen 兼容模式没有公开余额接口,跳百炼控制台
                Link(destination: URL(string: "https://bailian.console.aliyun.com")!) {
                    HStack {
                        Text("查看余额")
                        Spacer()
                        Text("百炼控制台")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                if hasAnalysisOverride {
                    Button("恢复内置默认值", role: .destructive) {
                        analysisBaseURL = ""
                        analysisAPIKey = ""
                        analysisModel = ""
                    }
                }
            } header: {
                Text("分析默认模型")
            } footer: {
                if hasAnalysisOverride {
                    Label("已覆盖默认值", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // ── 翻译默认模型 ────────────────────────────────────────────
            Section {
                LabeledContent("当前使用") {
                    Text(effectiveTranslationModel)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                LabeledContent("Base URL") {
                    TextField(DefaultModelConfig.baseURL, text: $translationBaseURL)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.callout, design: .monospaced))
                }
                LabeledContent("API Key") {
                    SecureField("使用内置 Key", text: $translationAPIKey)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.callout, design: .monospaced))
                }
                LabeledContent("模型") {
                    HStack(spacing: 8) {
                        TextField(DefaultModelConfig.model, text: $translationModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.callout, design: .monospaced))
                        Button {
                            showTranslationModelPicker = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.callout)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 余额查询:DeepSeek 官方支持 /user/balance
                LabeledContent("账户余额") {
                    HStack(spacing: 8) {
                        if isLoadingBalance {
                            ProgressView().scaleEffect(0.8)
                        } else if !balanceError.isEmpty {
                            Text("查询失败")
                                .font(.callout)
                                .foregroundStyle(.red)
                        } else if !balanceText.isEmpty {
                            Text(balanceText)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.green)
                        } else {
                            Text("未查询")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await refreshBalance() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.callout)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingBalance)
                    }
                }
                if hasTranslationOverride {
                    Button("恢复内置默认值", role: .destructive) {
                        translationBaseURL = ""
                        translationAPIKey = ""
                        translationModel = ""
                    }
                }
            } header: {
                Text("翻译默认模型")
            } footer: {
                if !balanceError.isEmpty {
                    Text(balanceError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("修改后下次调用接口时立即生效。「恢复内置默认值」会清除覆盖，回到代码里的硬编码配置。")
                }
            }
        }
        .navigationTitle("API 管理面板")
        .sheet(isPresented: $showAnalysisModelPicker) {
            ModelPickerSheet(
                baseURL: effectiveAnalysisBaseURL,
                apiKey: effectiveAnalysisAPIKey,
                selectedModel: $analysisModel
            )
        }
        .sheet(isPresented: $showTranslationModelPicker) {
            ModelPickerSheet(
                baseURL: effectiveTranslationBaseURL,
                apiKey: effectiveTranslationAPIKey,
                selectedModel: $translationModel
            )
        }
    }

    // MARK: - 计算属性

    private var effectiveAnalysisBaseURL: String {
        analysisBaseURL.isEmpty ? AnalysisDefaults.baseURL : analysisBaseURL
    }
    private var effectiveAnalysisAPIKey: String {
        analysisAPIKey.isEmpty ? Secrets.qwenAPIKey : analysisAPIKey
    }
    private var effectiveAnalysisModel: String {
        analysisModel.isEmpty ? AnalysisDefaults.model : analysisModel
    }

    private var effectiveTranslationBaseURL: String {
        translationBaseURL.isEmpty ? DefaultModelConfig.baseURL : translationBaseURL
    }
    private var effectiveTranslationAPIKey: String {
        translationAPIKey.isEmpty ? DefaultModelConfig.apiKey : translationAPIKey
    }
    private var effectiveTranslationModel: String {
        translationModel.isEmpty ? DefaultModelConfig.model : translationModel
    }

    private var hasAnalysisOverride: Bool {
        !analysisBaseURL.isEmpty || !analysisAPIKey.isEmpty || !analysisModel.isEmpty
    }
    private var hasTranslationOverride: Bool {
        !translationBaseURL.isEmpty || !translationAPIKey.isEmpty || !translationModel.isEmpty
    }

    // MARK: - 余额查询

    private func refreshBalance() async {
        isLoadingBalance = true
        balanceError = ""
        do {
            let balance = try await DeepSeekBalanceService.fetch(
                baseURL: effectiveTranslationBaseURL,
                apiKey: effectiveTranslationAPIKey
            )
            if let first = balance.balanceInfos.first {
                let prefix = first.currency == "CNY" ? "¥" : "$"
                balanceText = "\(prefix)\(first.totalBalance)"
            } else {
                balanceText = "无余额数据"
            }
        } catch {
            balanceError = error.localizedDescription
        }
        isLoadingBalance = false
    }
}
