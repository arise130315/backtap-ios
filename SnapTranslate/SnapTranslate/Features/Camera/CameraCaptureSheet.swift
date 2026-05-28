//
//  CameraCaptureSheet.swift
//  backtap
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
    /// 分析模式:复制按钮的"已复制"反馈,1.2 秒后还原(跟 ContentView 同款)
    @State private var analysisCopied = false
    /// 对焦框 UI 状态:点击位置 + 唯一 ID(连续点不同位置时用 id 让 transition 重新触发)
    /// nil 表示不显示。1.2 秒后自动清空。
    @State private var focusIndicator: FocusIndicator?

    private struct FocusIndicator: Equatable {
        let id: UUID
        let point: CGPoint
    }

    enum SaveStatus {
        case idle, saving, success, failed
    }

    /// UI 元素需要的视觉旋转角度(顺时针,度)。SwiftUI .rotationEffect 正值是顺时针。
    /// 用户视角看,chrome 应该在视角"上"方,这跟 device 怎么倾斜对应不同的旋转角:
    /// - landscapeLeft(顶向左,home 在右):屏幕"右"在用户视角"上",sheet 顺时针 90°
    /// - landscapeRight(顶向右,home 在左):屏幕"左"在用户视角"上",sheet 逆时针 90°
    /// camera.deviceOrientation 由 CMMotionManager 实时维护(读重力推断),sheet 一打开就有值
    private var uiRotationDegrees: Double {
        switch camera.deviceOrientation {
        case .portraitUpsideDown: return 180
        case .landscapeLeft:      return 90
        case .landscapeRight:     return -90
        default:                  return 0
        }
    }

    private var isLandscape: Bool { camera.deviceOrientation.isLandscape }

    /// Preview videoRotationAngle —— 直接用 CameraSessionManager 静态映射,
    /// 让预览跟拍照用完全相同的 angle,保证 PhotoDisplayView 显示的 UIImage 方向跟预览一致。
    /// 这个映射是 swap 过的(landscape 两个值对调),为了补偿 SwiftUI sheet rotationEffect 的影响。
    private var previewVideoRotationAngle: CGFloat {
        CameraSessionManager.videoRotationAngle(for: camera.deviceOrientation)
    }

    var body: some View {
        // App 是 portrait-only,fullScreenCover 内部 view 真实方向也是 portrait。
        // 通过 GeometryReader + 互换 W/H + rotationEffect 把整个 sheet "视觉上"旋转到 landscape,
        // 用户横拿手机时看起来 sheet 就是横屏铺满。
        // 内部布局按 portrait 画板写(顶部 X、底部 shutter),旋转后自然映射到用户视角的"上/下"。
        GeometryReader { geo in
            let canvasWidth = isLandscape ? geo.size.height : geo.size.width
            let canvasHeight = isLandscape ? geo.size.width : geo.size.height

            sheetContent
                .frame(width: canvasWidth, height: canvasHeight)
                .rotationEffect(.degrees(uiRotationDegrees))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .animation(.easeInOut(duration: 0.25), value: camera.deviceOrientation)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
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

    /// Sheet 真正的内容(在 portrait 画板尺寸内布局)。
    /// 外层 body 拿到这个 view 后 frame + rotationEffect 旋转到对应方向呈现。
    private var sheetContent: some View {
        ZStack(alignment: .center) {
            Color.black

            mainContent

            // 顶部:三段 HStack(左占位 / 中目标语言切换 / 右关闭),底部:shutter / 保存
            // 整个 VStack 强制撑满父容器,避免 wrap-content 把内容挤到一侧
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // 左占位 36×36,跟右侧 closeButton 对称,让中央元素真正水平居中
                    Color.clear.frame(width: 36, height: 36)
                    Spacer(minLength: 0)
                    // 翻译模式:目标语言切换(预览/翻译中/翻译完都显示,翻译完切换会触发重译)
                    if mode == .translate {
                        targetLanguageMenu
                    }
                    Spacer(minLength: 0)
                    // 分析模式 + 文本已就绪:右上角加复制按钮(贴在 closeButton 左边)
                    if mode == .analyze, let text = resultText, !isProcessing {
                        copyButton(text: text)
                    }
                    closeButton
                }
                .padding(.horizontal, 16)
                .padding(.top, isLandscape ? 24 : 60) // portrait 避 Dynamic Island,landscape sheet 的"top"是屏幕侧边,无需大边距

                Spacer()

                // 底部按钮包在全宽容器里居中
                bottomButtonArea
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, isLandscape ? 24 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 处理中 loading,用透明全屏 ZStack 包一层强制居中(processingOverlay 自身 wrap content)
            if isProcessing {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { processingOverlay }
            }
        }
        .clipped()
    }

    // MARK: - Subviews

    @ViewBuilder
    private var mainContent: some View {
        if capturedOriginal == nil {
            // 阶段 1:预览 + 点击对焦,强制撑满父容器
            // videoRotationAngle 固定 90° (portrait), sheet rotationEffect 处理视觉旋转
            ZStack {
                CameraPreviewView(
                    session: camera.session,
                    videoRotationAngle: previewVideoRotationAngle,
                    onTap: { viewPoint, devicePoint in
                        camera.focus(at: devicePoint)
                        triggerFocusIndicator(at: viewPoint)
                    }
                )
                if let indicator = focusIndicator {
                    focusReticle
                        .position(indicator.point)
                        .id(indicator.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.5).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .allowsHitTesting(false)
                }
            }
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
                    // 走 AttributedString(markdown:) 解析 **bold**,而不是直接 Text(text) 让 ** 原样显示。
                    // .inlineOnlyPreservingWhitespace 只处理行内语法,保留换行;bullet 仍以 "- " 形式呈现,可接受。
                    Text(markdownAttributed(text))
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 14))
                .padding(.horizontal, isLandscape ? 72 : 16) // 横屏时两边各 +56 避开横向状态栏(电池/信号/灵动岛)
                .padding(.bottom, 120) // 给底部"保存"按钮留位置
            }
            .ignoresSafeArea()
        }
    }

    /// 把 LLM 返回的 Markdown 文本(含 **bold**)转成 AttributedString,让 SwiftUI Text 渲染粗体。
    /// 解析失败兜底成纯文本,不会崩溃。
    private func markdownAttributed(_ raw: String) -> AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }

    /// 对焦框视觉:80×80 蓝色方框 + 四边中点小刻度。
    /// 用 Color.blue 跟 App 主色保持一致。
    private var focusReticle: some View {
        ZStack {
            Rectangle()
                .stroke(Color.blue, lineWidth: 1.2)
                .frame(width: 80, height: 80)
            // 四个边中点小刻度(向内),让框看起来更"专业"一点
            ForEach(0..<4) { index in
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 1.2, height: 6)
                    .offset(y: -40 + 3)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
    }

    /// 用户点击预览层时调用:记录 view 坐标并启动 1.2 秒后自动消失的定时器。
    /// 通过 UUID 比对保证 —— 中途用户再点别处时,旧定时器到期不会误清掉新指示器。
    private func triggerFocusIndicator(at point: CGPoint) {
        let newID = UUID()
        withAnimation(.easeOut(duration: 0.18)) {
            focusIndicator = FocusIndicator(id: newID, point: point)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if focusIndicator?.id == newID {
                withAnimation(.easeIn(duration: 0.3)) {
                    focusIndicator = nil
                }
            }
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

    /// 分析模式右上角复制按钮(跟 closeButton 视觉风格统一:双色 circle.fill + 内嵌 symbol)。
    /// 跟 ContentView.copyButton 同款逻辑:点击复制 + 1.2s 内 icon 变 ✓ 反馈。
    private func copyButton(text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            analysisCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                analysisCopied = false
            }
        } label: {
            ZStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.black.opacity(0.55))
                Image(systemName: analysisCopied ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel(analysisCopied ? "已复制" : "复制")
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
            // capturePhoto 内部用 camera.deviceOrientation(CMMotionManager 实时维护),
            // 跟 sheet 视觉旋转用同一个真相源,保证 sheet 横屏时拍出来也是横屏 UIImage
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
