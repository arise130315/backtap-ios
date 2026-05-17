import SwiftUI
import UIKit

/// 历史记录里 analysis 类型条目的详情页:顶部原图缩略图 + Markdown 分析文字 + 次级"复制"按钮。
struct AnalysisDetailView: View {
    let originalImage: UIImage?
    let analysisText: String
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let img = originalImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(.rect(cornerRadius: 12))
                }
                // SwiftUI Text via LocalizedStringKey 渲染 Markdown(粗体/bullet 列表等)
                Text(LocalizedStringKey(analysisText))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = analysisText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding()
        }
        .navigationTitle("分析详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
