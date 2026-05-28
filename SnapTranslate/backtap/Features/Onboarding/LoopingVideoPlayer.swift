//
//  LoopingVideoPlayer.swift
//  backtap
//
//  纯视频循环播放控件:无 controls / 自动播放 / 静音 / 无缝循环。
//  实现走 UIViewRepresentable + AVQueuePlayer + AVPlayerLooper(Apple 推荐的无缝循环方案)。
//  视频文件需放在 bundle 内,通过 resourceName + resourceExt 找。
//

import SwiftUI
import AVFoundation

struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String
    var resourceExt: String = "mp4"
    /// 视频在容器内的填充方式。默认 .resizeAspect(完整显示,可能有黑边/白边)。
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(resourceName: resourceName, resourceExt: resourceExt, gravity: videoGravity)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}
}

/// 内部 UIView 容器:管 AVPlayerLayer 的生命周期 + 视频 layer frame 跟随 view bounds 变化。
final class PlayerContainerView: UIView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper? // 持有引用,否则会被释放循环就停了

    override var backgroundColor: UIColor? {
        get { super.backgroundColor }
        set { super.backgroundColor = newValue }
    }

    func configure(resourceName: String, resourceExt: String, gravity: AVLayerVideoGravity) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExt) else {
            #if DEBUG
            print("⚠️ LoopingVideoPlayer: video not found in bundle: \(resourceName).\(resourceExt)")
            #endif
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none // 不停止,looper 接管

        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = gravity
        self.layer.addSublayer(layer)

        self.queuePlayer = player
        self.playerLayer = layer
        self.playerLooper = looper

        player.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
