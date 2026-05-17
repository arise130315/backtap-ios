import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HistoryItem.createdAt, order: .reverse) private var items: [HistoryItem]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无历史",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("翻译或分析过的截图会出现在这里")
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            destination(for: item)
                        } label: {
                            row(for: item)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("历史记录")
        .toolbar {
            if !items.isEmpty {
                EditButton()
            }
        }
    }

    @ViewBuilder
    private func row(for item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            // 缩略图统一用原图(两种类型都有)
            if let thumb = item.originalImage {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: item.type == .analysis ? "doc.text.magnifyingglass" : "character.bubble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.createdAt, style: .date)
                        .font(.subheadline)
                }
                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func subtitle(for item: HistoryItem) -> String {
        switch item.type {
        case .translation:
            return "\(item.segmentCount) 段译文 · \(formattedTime(item.createdAt))"
        case .analysis:
            let preview = (item.analysisText ?? "").replacingOccurrences(of: "\n", with: " ")
            return preview.isEmpty ? "分析 · \(formattedTime(item.createdAt))" : preview
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    @ViewBuilder
    private func destination(for item: HistoryItem) -> some View {
        switch item.type {
        case .translation:
            HistoryDetailView(item: item)
        case .analysis:
            AnalysisDetailView(
                originalImage: item.originalImage,
                analysisText: item.analysisText ?? ""
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}

private struct HistoryDetailView: View {
    let item: HistoryItem
    @State private var showingOriginal = false

    var body: some View {
        VStack {
            if let displayImage = showingOriginal ? item.originalImage : item.translatedImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .navigationTitle(showingOriginal ? "原图" : "译图")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showingOriginal ? "看译图" : "看原图") {
                    showingOriginal.toggle()
                }
            }
        }
    }
}
