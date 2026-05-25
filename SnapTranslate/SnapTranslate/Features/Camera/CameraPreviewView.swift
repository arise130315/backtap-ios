//
//  CameraPreviewView.swift
//  SnapTranslate
//
//  SwiftUI 包装 AVCaptureVideoPreviewLayer 的相机预览。
//  通过 UIViewRepresentable 实现,view.layer 直接是 AVCaptureVideoPreviewLayer
//  (覆盖 UIView.layerClass 让根 layer 就是预览 layer,避免嵌套层级。)
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 用户点击预览层时回调,参数是归一化设备坐标(0..1, 0..1),可直接传给 AVCaptureDevice.focusPointOfInterest
    var onTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.setSession(session)
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.onTap = onTap
    }
}

final class PreviewContainerView: UIView {
    var onTap: ((CGPoint) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // 强制转换安全:layerClass 已经指定为 AVCaptureVideoPreviewLayer
        // swiftlint:disable:next force_cast
        return layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // session connection 建立后(input 添加完)设 portrait 旋转角度,
        // 不设的话默认显示传感器横向画面,在竖屏 view 里被压成"偏一侧"的画面
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let layerPoint = gesture.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        onTap?(devicePoint)
    }

    func setSession(_ session: AVCaptureSession) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }
}
