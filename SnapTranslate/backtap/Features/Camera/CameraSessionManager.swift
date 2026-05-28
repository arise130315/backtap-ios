//
//  CameraSessionManager.swift
//  backtap
//
//  封装 AVCaptureSession + 后置相机 + AVCapturePhotoOutput 的拍照流程。
//  - configure() 在后台 queue 配置 session(只调一次)
//  - startSession() / stopSession() 控制运行
//  - capturePhoto() 触发拍照,完成后通过 @Published capturedImage 传出 UIImage
//  - 错误通过 @Published captureError 传出
//

import AVFoundation
import Combine
import CoreMotion
import UIKit

// 注:不用 @MainActor 标 class —— ObservableObject 协议要求成员 nonisolated,跟 @MainActor 冲突。
// 改用 `Task { @MainActor in ... }` 在 background queue 回调里手动 hop 回 main actor 更新 @Published。
final class CameraSessionManager: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var captureError: String?
    @Published var isConfigured: Bool = false
    /// 实时设备物理方向,用 CoreMotion 重力向量判断。
    /// 为什么不用 UIDevice.orientationDidChangeNotification:
    /// 那个通知只在"方向变化"时发,用户进入 sheet 前已经横拿手机不动,
    /// 系统不会发新通知,SwiftUI .onReceive 永远收不到,UI 卡在 portrait 初值。
    /// CoreMotion 重力是连续读取,sheet 一打开 200~300ms 内就能拿到真实方向。
    @Published var deviceOrientation: UIDeviceOrientation = .portrait

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.snaptranslate.camera.session")
    /// CMMotionManager 持续读重力 → 推断 device orientation,跟 iOS 系统相机做法一致
    private let motionManager = CMMotionManager()

    func configure() {
        // CoreMotion 启动 device motion updates,持续读重力向量
        startOrientationUpdates()

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
        stopOrientationUpdates()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// 拍照。直接用 self.deviceOrientation(CoreMotion 实时维护的值),
    /// 保证拍照角度跟 sheet 视觉方向同源 —— 都是 CMMotionManager 读重力推断出来的。
    func capturePhoto() {
        let orientation = self.deviceOrientation
        let angle = Self.videoRotationAngle(for: orientation)

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

    // MARK: - CoreMotion 方向追踪

    /// 启动 device motion updates,持续读重力向量推断设备方向。
    /// 跟 iOS 系统相机做法一致 —— 不依赖 UIDevice.orientationDidChangeNotification
    /// (那个只在方向变化时才发,sheet 打开时手机已经横拿不动就收不到)。
    private func startOrientationUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            // 模拟器或无 motion sensor 设备 fallback portrait
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let newOrientation = Self.orientation(fromGravity: gravity)
            if newOrientation != self.deviceOrientation {
                self.deviceOrientation = newOrientation
            }
        }
    }

    private func stopOrientationUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    /// 根据 CoreMotion 重力向量推断 UIDeviceOrientation。
    /// 设备坐标系:x = 设备左→右,y = 设备底→顶(positive 向上),z = 屏幕外→里。
    /// 重力始终指地心,根据 gravity 在设备坐标系的分量判断设备相对地心的姿态:
    /// - portrait(顶向上):gravity ≈ (0, -1, 0),y < 0 → portrait
    /// - portraitUpsideDown(顶向下):gravity ≈ (0, 1, 0),y > 0 → upsideDown
    /// - landscapeLeft(顶向左,home 在右):gravity ≈ (-1, 0, 0),x < 0 → landscapeLeft
    /// - landscapeRight(顶向右,home 在左):gravity ≈ (1, 0, 0),x > 0 → landscapeRight
    private static func orientation(fromGravity gravity: CMAcceleration) -> UIDeviceOrientation {
        // 设一个 deadband 阈值,避免设备接近水平(平躺)时频繁抖动方向
        // |x|, |y| 都很小时(<0.6,大约小于 37° 倾角),保留上次 orientation
        if abs(gravity.x) < 0.3 && abs(gravity.y) < 0.3 {
            return .portrait // faceUp/faceDown fallback
        }
        if abs(gravity.y) > abs(gravity.x) {
            return gravity.y > 0 ? .portraitUpsideDown : .portrait
        } else {
            return gravity.x > 0 ? .landscapeRight : .landscapeLeft
        }
    }

    /// 设备物理方向 → AVCaptureConnection videoRotationAngle(degrees,顺时针)。
    /// 这套映射 = Apple 标准 + landscape 两个值对调,跟 CameraCaptureSheet.previewVideoRotationAngle 保持一致。
    /// 为什么不用 Apple 标准的 landscapeLeft=180 / landscapeRight=0:
    /// 实证发现 sheet rotationEffect transform 跟 AVCapturePhotoOutput 的 angle 叠加后,
    /// 用 Apple 标准值时拍出来的 UIImage 跟预览差 180°(预览正、拍照颠倒)。
    /// 用 swap 值后预览跟拍照方向一致。
    static func videoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft:      return 0   // home button 在右(顶向左) — 跟预览 swap 一致
        case .landscapeRight:     return 180 // home button 在左(顶向右) — 跟预览 swap 一致
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
