//
//  CameraCaptureSheet.swift
//  SnapTranslate
//
//  全屏自定义相机面板:
//  - 阶段 1(预览):CameraPreviewView 实时预览 + 底部 shutter 圆形按钮
//  - 阶段 2(处理中):显示拍到的原图 + 中间 loading,底部按钮隐藏
//  - 阶段 3(结果):
//    - 翻译模式:显示译图(resultImage),底部"保存"按钮
//    - 分析模式:显示原图 + 底部 ScrollView 叠加分析文本,底部"保存"按钮
//  - 顶部右上 X 关闭按钮始终可见
//
//  数据流:
//  - 拍照后 onCapture(image) 回调,由 ContentView 触发现有 OCR + translate / analyze pipeline
//  - ContentView 处理完后,自己的 state(translatedImage / analysisText / isTranslating / isAnalyzing)
//    通过 binding 反馈给 Sheet,Sheet 据此切换阶段 + 显示结果
//

import SwiftUI
import UIKit
import Photos

struct CameraCaptureSheet: View {
    let mode: ContentMode
    @Binding var resultImage: UIImage?    // 翻译模式:译图;分析模式:原图(用于保存)
    @Binding var resultText: String?       // 分析模式:分析文本
    @Binding var isProcessing: Bool        // ContentView 的 isTranslating / isAnalyzing
    @Binding var targetLanguage: TargetLanguage // 仅翻译模式生效:Menu 切换后 ContentView 的 onChange 会自动重译
    let onClose: () -> Void
    let onCapture: (UIImage) -> Void

    @StateObject private var camera = CameraSessionManager()
    @State private var capturedOriginal: UIImage?
    @State private var saveStatus: SaveStatus = .idle
    @State private var permissionDenied = false

    enum SaveStatus {
        case idle, saving, success, failed
    }

    var body: some View {
        ZStack(alignment: .center) {
            Color.black.ignoresSafeArea()

            mainContent

            // 顶部:三段 HStack(左占位 / 中目标语言切换 / 右关闭),底部:shutter / 保存
            // 整个 VStack 强制撑满父容器,避免 wrap-content 把内容挤到一侧
            VStack(spacing: 0) {
                HStack {
                    // 左占位 36×36,跟右侧 closeButton 对称,让中央元素真正水平居中
                    Color.clear.frame(width: 36, height: 36)
                    Spacer(minLength: 0)
                    // 翻译模式:目标语言切换(预览/翻译中/翻译完都显示,翻译完切换会触发重译)
                    if mode == .translate {
                        targetLanguageMenu
                    }
                    Spacer(minLength: 0)
                    closeButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 60) // 避开 Dynamic Island / 状态栏

                Spacer()

                // 底部按钮包在全宽容器里居中(VStack 在 safe area 内,自然避开 home indicator)
                bottomButtonArea
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 处理中 loading,用透明全屏 ZStack 包一层强制居中(processingOverlay 自身 wrap content)
            if isProcessing {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { processingOverlay }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 强制铺满 fullScreenCover 容器
        // 注:外层不加 .ignoresSafeArea() —— chrome (X / 语言菜单 / 底部按钮 / loading)
        // 在 safe area 内自然居中布局;mainContent 内部自己 .ignoresSafeArea() 突破到全屏
        .task {
            await requestCameraAccessAndConfigure()
        }
        .onDisappear {
            camera.stopSession()
        }
        .onChange(of: camera.capturedImage) { _, newImage in
            guard let image = newImage else { return }
            capturedOriginal = image
            camera.stopSession() // 拍到照片后停止预览,节省电量
            onCapture(image)
        }
        .alert("相机错误", isPresented: cameraErrorAlertBinding) {
            Button("好") { camera.captureError = nil }
        } message: {
            Text(camera.captureError ?? "")
        }
        .alert("无相机权限", isPresented: $permissionDenied) {
            Button("关闭") { onClose() }
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                onClose()
            }
        } message: {
            Text("请在「设置 → 快捷识屏 → 相机」中开启权限。")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var mainContent: some View {
        if capturedOriginal == nil {
            // 阶段 1:预览 + 点击对焦,强制撑满父容器
            CameraPreviewView(session: camera.session, onTap: { devicePoint in
                camera.focus(at: devicePoint)
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        } else if let resultImage {
            // 阶段 3:翻译模式显示译图 —— 用 UIImageView 包装,跟预览层用同一套 CALayer 渲染,
            // 内容居中位置跟预览 100% 一致
            PhotoDisplayView(image: resultImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        } else if let captured = capturedOriginal {
            // 阶段 2-3:显示拍到的原图(分析模式 / 翻译还没出译图时)
            PhotoDisplayView(image: captured)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }

        // 分析模式:文本结果叠加在底部 ScrollView。
        // 用深色高对比背景(black 75%) + 白色文字,避免 .ultraThinMaterial 在白底图上变浅灰,
        // 跟 loading overlay / save 按钮样式统一
        if mode == .analyze, let text = resultText, !isProcessing {
            VStack {
                Spacer()
                ScrollView(showsIndicators: false) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 120) // 给底部"保存"按钮留位置
            }
            .ignoresSafeArea()
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            // 用 xmark.circle.fill + palette 双色(白 X + 半透明黑圆),
            // 在白色/亮色背景下也能保持高对比度可见
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .frame(width: 36, height: 36) // 保持 36×36 hit area,跟左占位对称
        }
        .accessibilityLabel("关闭")
    }

    /// 拍照面板顶部中间的目标语言切换按钮(仅翻译模式)
    private var targetLanguageMenu: some View {
        Menu {
            ForEach(TargetLanguage.allCases) { lang in
                Button {
                    targetLanguage = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if targetLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(targetLanguage.displayName)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4), in: .capsule)
        }
        .accessibilityLabel("切换目标语言")
    }

    @ViewBuilder
    private var bottomButtonArea: some View {
        if capturedOriginal == nil {
            shutterButton
        } else if isProcessing {
            // 处理中不显示按钮,避免误触
            Color.clear.frame(height: 80)
        } else {
            saveButton
        }
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
            }
        }
        .accessibilityLabel(mode == .translate ? "拍照翻译" : "拍照分析")
        .disabled(!camera.isConfigured)
    }

    private var saveButton: some View {
        Button {
            saveImageToLibrary()
        } label: {
            HStack(spacing: 8) {
                if saveStatus == .success {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(saveButtonText)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(saveStatus == .success ? Color.green : Color.accentColor.opacity(0.9), in: .capsule)
        }
        .disabled(saveStatus == .saving)
        .accessibilityLabel(saveButtonText)
    }

    private var saveButtonText: String {
        switch saveStatus {
        case .idle: return "保存到相册"
        case .saving: return "保存中..."
        case .success: return "已保存"
        case .failed: return "保存失败,重试"
        }
    }

    private var processingOverlay: some View {
        // 深色高对比样式:black 75% 背景 + 白色 indicator + 白色文字,
        // 在亮/暗主题任何背景下都清晰可读(原 .ultraThinMaterial + 白字在白底场景里被冲淡看不清)
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text(mode == .translate ? "翻译中..." : "分析中...")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 14))
    }

    // MARK: - Logic

    private var cameraErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { camera.captureError != nil },
            set: { if !$0 { camera.captureError = nil } }
        )
    }

    private func requestCameraAccessAndConfigure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            startCamera()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                startCamera()
            } else {
                permissionDenied = true
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    private func startCamera() {
        camera.configure()
        camera.startSession()
    }

    private func saveImageToLibrary() {
        // 选要保存的图:翻译模式优先 resultImage(译图),没有就保存原图;分析模式直接原图
        let imageToSave: UIImage? = {
            switch mode {
            case .translate:
                return resultImage ?? capturedOriginal
            case .analyze:
                return capturedOriginal
            }
        }()
        guard let image = imageToSave else { return }

        saveStatus = .saving
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                await MainActor.run { saveStatus = .success }
                try? await Task.sleep(for: .seconds(1.4))
                await MainActor.run { onClose() }
            } catch {
                await MainActor.run { saveStatus = .failed }
            }
        }
    }
}
