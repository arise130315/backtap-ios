import UIKit
import CoreImage

/// 估算 bbox 四周的平均背景色，用于覆盖原文。
enum BackgroundColorSampler {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameters:
    ///   - image: 原图
    ///   - pixelRect: bbox 在像素坐标系下的矩形（UIKit 左上原点）
    ///   - expand: 向外扩出多少像素作为采样带
    static func sample(image: UIImage, around pixelRect: CGRect, expand: CGFloat = 8) -> UIColor {
        guard let cgImage = image.cgImage else { return .white }

        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let outer = pixelRect.insetBy(dx: -expand, dy: -expand).intersection(imageBounds)
        guard !outer.isNull, outer.width > 0, outer.height > 0 else { return .white }

        // UIKit 左上原点 → CoreImage 左下原点
        let h = CGFloat(cgImage.height)
        func toCIRect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
        }

        let ciImage = CIImage(cgImage: cgImage)

        // 四条外圈边带（顶/底/左/右），各采均值，最后再平均
        let strips: [CGRect] = [
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: expand),
            CGRect(x: outer.minX, y: outer.maxY - expand, width: outer.width, height: expand),
            CGRect(x: outer.minX, y: outer.minY, width: expand, height: outer.height),
            CGRect(x: outer.maxX - expand, y: outer.minY, width: expand, height: outer.height)
        ]

        var sumR: CGFloat = 0, sumG: CGFloat = 0, sumB: CGFloat = 0
        var count = 0
        for strip in strips {
            let clipped = strip.intersection(imageBounds)
            guard clipped.width > 0, clipped.height > 0 else { continue }
            if let (r, g, b) = averageRGB(of: ciImage, in: toCIRect(clipped)) {
                sumR += r
                sumG += g
                sumB += b
                count += 1
            }
        }
        guard count > 0 else { return .white }
        return UIColor(
            red: sumR / CGFloat(count),
            green: sumG / CGFloat(count),
            blue: sumB / CGFloat(count),
            alpha: 1
        )
    }

    private static func averageRGB(of ciImage: CIImage, in rect: CGRect) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: rect)
        ]),
              let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (
            CGFloat(bitmap[0]) / 255,
            CGFloat(bitmap[1]) / 255,
            CGFloat(bitmap[2]) / 255
        )
    }
}
