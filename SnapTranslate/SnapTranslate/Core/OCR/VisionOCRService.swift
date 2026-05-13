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
            request.recognitionLanguages = ["en-US", "ja-JP", "ko-KR", "zh-Hans", "zh-Hant"]

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
