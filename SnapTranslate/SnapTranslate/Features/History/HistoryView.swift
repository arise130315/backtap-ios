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
                    description: Text("翻译过的截图会出现在这里")
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            HistoryDetailView(item: item)
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
            if let thumb = item.translatedImage {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.createdAt, style: .date)
                    .font(.subheadline)
                Text("\(item.segmentCount) 段译文 · \(item.createdAt, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
