//
//  PhotoDisplayView.swift
//  SnapTranslate
//
//  UIViewRepresentable 包 UIImageView,跟 CameraPreviewView 行为对称。
//
//  为什么不直接用 SwiftUI Image + .scaledToFill:
//  - CameraPreviewView 是 UIView + AVCaptureVideoPreviewLayer(.resizeAspectFill)
//  - SwiftUI Image + .scaledToFill 跟 UIView .scaleAspectFill 是不同的 layout 机制,
//    在 ZStack 内 sizing/centering 行为微妙不一致 —— 实测表现:预览居中、Image 偏移
//  - 改用 UIImageView(.scaleAspectFill)后,跟预览层 100% 同一套 CALayer 渲染,
//    view frame 一致 → 内容居中位置必然一致
//

import SwiftUI
import UIKit

/// 自定义 UIImageView 子类,override intrinsicContentSize 返回 noIntrinsicMetric
/// —— 默认 UIImageView 把 image.size(像素 size,比如 3024×4032)当 intrinsic,
/// SwiftUI 会优先用它而不是 .frame(.infinity),导致 view 被撑成巨大 size。
final class FlexibleImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

struct PhotoDisplayView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> FlexibleImageView {
        let view = FlexibleImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        // 双重保险:同时降低 content hugging / compression resistance,
        // 让 SwiftUI auto layout 完全控制 size
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: FlexibleImageView, context: Context) {
        uiView.image = image
    }

    /// iOS 16+ SwiftUI API:显式告诉 SwiftUI 接受 proposal size,
    /// 不要用 UIView 的 intrinsicContentSize
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FlexibleImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
