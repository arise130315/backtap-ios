import UIKit

/// 在原图上覆盖译文，保留原版面布局。
enum LayoutPreservingRenderer {
    struct Block {
        /// Vision OCR 归一化坐标（左下原点，0..1）
        let normalizedBox: CGRect
        let translatedText: String
    }

    static func render(originalImage: UIImage, blocks: [Block]) -> UIImage {
        guard let cgImage = originalImage.cgImage else { return originalImage }
        let size = CGSize(width: cgImage.width, height: cgImage.height)

        // 强制 1x scale,直接按像素绘制,避免 retina 放大导致坐标错位
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            // 1. 底图:原图
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))

            for block in blocks {
                // 2. Vision 归一化坐标 → UIKit 像素坐标(左上原点)
                let rect = CGRect(
                    x: block.normalizedBox.minX * size.width,
                    y: (1 - block.normalizedBox.maxY) * size.height,
                    width: block.normalizedBox.width * size.width,
                    height: block.normalizedBox.height * size.height
                )
                guard rect.width > 0, rect.height > 0 else { continue }

                // 3. 采样背景色
                let bgColor = BackgroundColorSampler.sample(image: originalImage, around: rect)

                // 4. 用背景色盖掉原文(向外扩 2px 防漏边)
                bgColor.setFill()
                UIRectFill(rect.insetBy(dx: -2, dy: -2))

                // 5. 选前景色(按背景亮度反色)
                let fgColor = foregroundColor(forBackground: bgColor)

                // 6. 绘译文(字号从 height*0.75 起,放不下则递减)
                drawText(
                    block.translatedText,
                    in: rect,
                    initialFontSize: rect.height * 0.75,
                    color: fgColor
                )
            }
        }
    }

    private static func foregroundColor(forBackground bg: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bg.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.55 ? .black : .white
    }

    private static func drawText(_ text: String, in rect: CGRect, initialFontSize: CGFloat, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping

        var fontSize = max(initialFontSize, 6)
        let minFontSize: CGFloat = 6

        while fontSize >= minFontSize {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: color,
                .paragraphStyle: style
            ]
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            if bounding.height <= rect.height && bounding.width <= rect.width + 1 {
                // 放得下,垂直居中绘制
                let drawRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + (rect.height - bounding.height) / 2,
                    width: rect.width,
                    height: bounding.height
                )
                (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                return
            }
            fontSize -= 1
        }

        // 实在放不下,按 minFontSize 截断绘制
        let truncStyle = NSMutableParagraphStyle()
        truncStyle.alignment = .left
        truncStyle.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: minFontSize),
            .foregroundColor: color,
            .paragraphStyle: truncStyle
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}
