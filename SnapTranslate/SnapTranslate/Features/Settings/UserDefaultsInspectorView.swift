import SwiftUI

struct UserDefaultsInspectorView: View {
    @State private var pairs: [(key: String, value: String)] = []

    var body: some View {
        List(pairs, id: \.key) { pair in
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.key)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(pair.value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("UserDefaults 查看器")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") { load() }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard let domain = Bundle.main.bundleIdentifier,
              let dict = UserDefaults.standard.persistentDomain(forName: domain) else {
            pairs = []
            return
        }
        pairs = dict
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: stringify($0.value)) }
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let s as String:
            // 长字符串截断，避免 Debug prompt 把整个列表撑爆
            return s.count > 120 ? String(s.prefix(120)) + "…" : s
        case let n as NSNumber:
            return n.stringValue
        case let b as Bool:
            return b ? "true" : "false"
        default:
            return String(describing: value)
        }
    }
}
