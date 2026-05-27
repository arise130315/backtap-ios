import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HistoryItem.createdAt, order: .reverse) private var items: [HistoryItem]
    @Environment(\.modelContext) private var context

    /// 当前选中的类型 tab —— 翻译 / 分析
    @State private var selectedTab: HistoryItemType = .translation
    /// 自定义 editMode(用中文「编辑」/「完成」按钮替代 SwiftUI 默认 EditButton 的英文)
    @State private var editMode: EditMode = .inactive
    /// 「全部清除」二次确认弹窗
    @State private var showClearAllConfirm = false

    init() {
        // SwiftUI Picker(.segmented) 内的字号由 UISegmentedControl appearance 控制,
        // SwiftUI 没有 modifier 直接改,只能走 UIKit appearance proxy
        let font = UIFont.systemFont(ofSize: 14)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: font], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: font], for: .selected)
    }

    var body: some View {
        // 按 tab 过滤后的列表,内部再按时间段分组
        let filtered = items.filter { $0.type == selectedTab }

        VStack(spacing: 0) {
            // 系统分段控制器:高度 40,字号 14(字号在 init() UIAppearance 里设);宽度跟随父容器
            Picker("类型", selection: $selectedTab) {
                Text("翻译").tag(HistoryItemType.translation)
                Text("分析").tag(HistoryItemType.analysis)
            }
            .pickerStyle(.segmented)
            .frame(height: 40)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if filtered.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "暂无历史",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(selectedTab == .translation
                        ? "只会记录拍照翻译和选图翻译的内容（快捷识屏翻译不会被记录，用完即走）"
                        : "只会记录拍照分析和选图分析的内容（快捷识屏分析不会被记录，用完即走）")
                )
                Spacer()
            } else {
                List {
                    ForEach(TimeGroup.allCases, id: \.self) { group in
                        let sectionItems = filtered.filter { Self.timeGroup(for: $0.createdAt) == group }
                        if !sectionItems.isEmpty {
                            Section(group.title) {
                                ForEach(sectionItems) { item in
                                    NavigationLink {
                                        destination(for: item)
                                    } label: {
                                        row(for: item)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteItems(in: sectionItems, at: offsets)
                                }
                            }
                        }
                    }
                }
                // 隐藏 List 自己的灰色 grouped 背景,统一用外层 systemGroupedBackground
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground)) // 整页底色跟首页一致(浅灰)
        .navigationTitle("历史记录")
        // 导航栏背景跟内容区同色,消除视觉断层
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "完成" : "编辑") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                }
            }
            if editMode == .active && !filtered.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        Text("全部清除")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .alert("清除后，将不能恢复，确认是否清除？", isPresented: $showClearAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearAllInCurrentTab()
            }
        }
    }

    /// 清除当前 tab 下的所有记录(只删翻译,或只删分析)
    private func clearAllInCurrentTab() {
        for item in items where item.type == selectedTab {
            context.delete(item)
        }
    }

    // MARK: - 时间分组

    /// 备忘录式时间梯度,从近到远。
    enum TimeGroup: String, CaseIterable {
        case today
        case past3Days
        case past7Days
        case past30Days
        case earlier

        var title: String {
            switch self {
            case .today:      return "今天"
            case .past3Days:  return "过去 3 天"
            case .past7Days:  return "过去 7 天"
            case .past30Days: return "过去 30 天"
            case .earlier:    return "更早"
            }
        }
    }

    /// 用「跨日数」分组(按日历日,不按 24h 整时长):
    /// - 今天 = 同一日历日
    /// - 过去 3 天 = 1-3 天前(含昨天)
    /// - 过去 7 天 = 4-7 天前
    /// - 过去 30 天 = 8-30 天前
    /// - 更早 = > 30 天
    private static func timeGroup(for date: Date) -> TimeGroup {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days <= 3 { return .past3Days }
        if days <= 7 { return .past7Days }
        if days <= 30 { return .past30Days }
        return .earlier
    }

    // MARK: - Row / Destination

    @ViewBuilder
    private func row(for item: HistoryItem) -> some View {
        HStack(spacing: 12) {
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

    // MARK: - 删除

    /// onDelete 给的 offsets 是 section 内 sectionItems 数组的索引,
    /// 通过 sectionItems[index] 拿到具体 HistoryItem 后,从 SwiftData context 删除。
    private func deleteItems(in sectionItems: [HistoryItem], at offsets: IndexSet) {
        for index in offsets {
            context.delete(sectionItems[index])
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
