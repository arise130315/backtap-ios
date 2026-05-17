import Foundation
import SwiftData
import UIKit

/// 历史记录条目类型。SwiftData 字段用 rawValue String 存储。
enum HistoryItemType: String {
    case translation
    case analysis
}

@Model
final class HistoryItem {
    var createdAt: Date
    /// `translation` 或 `analysis`,用 String 存以兼容 SwiftData。新字段默认值确保 SwiftData
    /// 对旧数据自动迁移(旧条目 typeRaw 缺失时被视为 translation)。
    var typeRaw: String = HistoryItemType.translation.rawValue
    /// 原图 PNG 数据(两种类型都有)
    @Attribute(.externalStorage) var originalImageData: Data
    /// 译图 PNG 数据。translation 类型存译图;analysis 类型存空 Data(为避免 SwiftData
    /// schema migration 风险,字段类型保持非 Optional Data)。
    @Attribute(.externalStorage) var translatedImageData: Data
    /// 识别到的段落数,仅 translation 类型有意义
    var segmentCount: Int
    /// 分析的 Markdown 文字,仅 analysis 类型有
    var analysisText: String?

    /// 翻译条目 init(保留原签名,现有调用方不受影响)
    init(originalImage: UIImage, translatedImage: UIImage, segmentCount: Int) {
        self.createdAt = Date()
        self.typeRaw = HistoryItemType.translation.rawValue
        self.originalImageData = originalImage.pngData() ?? Data()
        self.translatedImageData = translatedImage.pngData() ?? Data()
        self.segmentCount = segmentCount
        self.analysisText = nil
    }

    /// 分析条目 init
    init(originalImage: UIImage, analysisText: String) {
        self.createdAt = Date()
        self.typeRaw = HistoryItemType.analysis.rawValue
        self.originalImageData = originalImage.pngData() ?? Data()
        self.translatedImageData = Data()
        self.segmentCount = 0
        self.analysisText = analysisText
    }

    var type: HistoryItemType {
        HistoryItemType(rawValue: typeRaw) ?? .translation
    }
    var originalImage: UIImage? { UIImage(data: originalImageData) }
    var translatedImage: UIImage? {
        guard !translatedImageData.isEmpty else { return nil }
        return UIImage(data: translatedImageData)
    }
}
