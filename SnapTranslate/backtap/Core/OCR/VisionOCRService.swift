import Foundation
import Vision
import UIKit

struct OCRResult: Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

enum VisionOCRService {
    static func recognize(in image: UIImage) async throws -> [OCRResult] {
        guard let cgImage = image.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let results = observations.compactMap { obs -> OCRResult? in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return OCRResult(
                        text: top.string,
                        boundingBox: obs.boundingBox,
                        confidence: top.confidence
                    )
                }
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Vision Framework 按顺序决定语言优先级。中文用户场景下,zh-Hans 放第一位,
            // 否则 Vision 会把中文当英文识别,产生 "WPS AE" / "ziŽ1E·=Ý" 这类乱码。
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
