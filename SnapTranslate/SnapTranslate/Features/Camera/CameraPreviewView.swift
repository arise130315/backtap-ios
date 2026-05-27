//
//  CameraPreviewView.swift
//  SnapTranslate
//
//  SwiftUI 包装 AVCaptureVideoPreviewLayer 的相机预览。
//  通过 UIViewRepresentable 实现,view.layer 直接是 AVCaptureVideoPreviewLayer
//  (覆盖 UIView.layerClass 让根 layer 就是预览 layer,避免嵌套层级。)
//
//  videoRotationAngle 由父 view 按 device orientation 算好传入,
//  让预览方向跟拍照(CameraSessionManager.capturePhoto)用同一套角度——
//  横拿手机时预览跟拍出来的图都是 landscape,翻译方向才能正确。
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 由父 view 按 UIDevice.current.orientation 算好,见 CameraSessionManager.videoRotationAngle(for:)
    let videoRotationAngle: CGFloat
    /// 用户点击预览层时回调,参数是归一化设备坐标(0..1, 0..1),可直接传给 AVCaptureDevice.focusPointOfInterest
    var onTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.setSession(session)
        view.onTap = onTap
        view.setVideoRotationAngle(videoRotationAngle)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.onTap = onTap
        uiView.setVideoRotationAngle(videoRotationAngle)
    }
}

final class PreviewContainerView: UIView {
    var onTap: ((CGPoint) -> Void)?
    /// 缓存待应用的旋转角度。makeUIView/updateUIView 调用 setVideoRotationAngle 时,
    /// session.connection 可能还没准备好(input 没添加完),layoutSubviews 兜底再设一次。
    private var pendingVideoRotationAngle: CGFloat = 90

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
        applyPendingRotation()
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

    func setVideoRotationAngle(_ angle: CGFloat) {
        pendingVideoRotationAngle = angle
        applyPendingRotation()
    }

    private func applyPendingRotation() {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(pendingVideoRotationAngle),
              connection.videoRotationAngle != pendingVideoRotationAngle else { return }
        connection.videoRotationAngle = pendingVideoRotationAngle
    }
}
