import Foundation
import SwiftData
import UIKit

@Model
final class HistoryItem {
    var createdAt: Date
    /// 原图 PNG 数据
    @Attribute(.externalStorage) var originalImageData: Data
    /// 译图 PNG 数据
    @Attribute(.externalStorage) var translatedImageData: Data
    /// 识别到的段落数
    var segmentCount: Int

    init(originalImage: UIImage, translatedImage: UIImage, segmentCount: Int) {
        self.createdAt = Date()
        self.originalImageData = originalImage.pngData() ?? Data()
        self.translatedImageData = translatedImage.pngData() ?? Data()
        self.segmentCount = segmentCount
    }

    var originalImage: UIImage? { UIImage(data: originalImageData) }
    var translatedImage: UIImage? { UIImage(data: translatedImageData) }
}
