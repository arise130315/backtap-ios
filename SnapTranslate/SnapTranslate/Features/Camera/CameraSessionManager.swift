//
//  CameraSessionManager.swift
//  SnapTranslate
//
//  封装 AVCaptureSession + 后置相机 + AVCapturePhotoOutput 的拍照流程。
//  - configure() 在后台 queue 配置 session(只调一次)
//  - startSession() / stopSession() 控制运行
//  - capturePhoto() 触发拍照,完成后通过 @Published capturedImage 传出 UIImage
//  - 错误通过 @Published captureError 传出
//

import AVFoundation
import Combine
import UIKit

// 注:不用 @MainActor 标 class —— ObservableObject 协议要求成员 nonisolated,跟 @MainActor 冲突。
// 改用 `Task { @MainActor in ... }` 在 background queue 回调里手动 hop 回 main actor 更新 @Published。
final class CameraSessionManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var captureError: String?
    @Published var isConfigured: Bool = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.snaptranslate.camera.session")

    func configure() {
        // 启动 device orientation 通知,让 UIDevice.current.orientation 能返回准确值
        // (系统通常自动生成,但显式启动更稳)
        if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // 后置广角相机
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.captureError = "无法访问相机"
                }
                return
            }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()

            Task { @MainActor in
                self.isConfigured = true
            }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        // 从 main thread 拿设备物理方向(SwiftUI Button 触发 capturePhoto 时一定在 main)。
        // App 是 portrait-only,interface 永远竖直,但相机要按设备物理方向拍:
        // 横拿时输出横屏图(imageOrientation=.up + raw 横向),OCR 才能正确识别横向文字。
        let angle = Self.videoRotationAngle(for: UIDevice.current.orientation)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 拍照前根据 device orientation 设 connection rotation,
            // AVCapturePhotoOutput 输出图就会是 imageOrientation=.up + raw 已按物理方向旋转
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// 用户点击预览层某点 → 让相机对焦 + 测光到该点
    /// - Parameter devicePoint: 归一化设备坐标(0..1, 0..1),由 AVCaptureVideoPreviewLayer 转换得到
    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                device.unlockForConfiguration()
            } catch {
                // 锁定失败时静默忽略(对焦不是关键路径)
            }
        }
    }

    /// 设备物理方向 → AVCaptureConnection videoRotationAngle(degrees,顺时针)。
    /// 系统未生成 device orientation 通知时 fallback 到 portrait(90°)。
    private static func videoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft:      return 180 // home button 在右(顶向左)
        case .landscapeRight:     return 0   // home button 在左(顶向右)
        default:                  return 90  // faceUp/faceDown/unknown
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSessionManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        if let error {
            Task { @MainActor in
                self.captureError = "拍照失败:\(error.localizedDescription)"
            }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.captureError = "图片解析失败"
            }
            return
        }
        // 标准化 orientation 为 .up:AVCapturePhotoOutput 拍出的 UIImage 默认 imageOrientation=.right
        // (传感器物理方向),如果后续 pipeline(LayoutPreservingRenderer / JPEG 编码)用 CGImage,
        // 会丢失 orientation 信息导致译图旋转 90 度。这里实际旋转像素 buffer,后续处理一致。
        let normalized = Self.normalizedOrientation(image)
        Task { @MainActor in
            self.capturedImage = normalized
        }
    }

    private static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size, format: image.imageRendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
