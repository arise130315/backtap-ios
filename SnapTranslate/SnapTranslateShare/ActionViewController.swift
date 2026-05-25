//
//  ActionViewController.swift
//  SnapTranslateShare
//
//  Created by 杨剑峰 on 2026/5/13.
//

import UIKit
import UniformTypeIdentifiers

class ActionViewController: UIViewController {

    // 这两个 outlet 来自 storyboard,保留以匹配既有连接
    @IBOutlet weak var imageView: UIImageView!

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.text = "正在处理截图..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "快捷识屏"

        // 在主视图叠一个 statusLabel,处理过程中显示
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        Task { await processInput() }
    }

    private func processInput() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            await updateStatus("未找到可处理的图片")
            return
        }

        do {
            let image = try await loadImage(from: provider)

            await updateStatus("识别文字中...")
            let results = try await VisionOCRService.recognize(in: image)

            await updateStatus("生成翻译图中...")
            // Extension MVP:先用 mock 译文跑通分享流程,真翻译留待步骤 8 接入
            let translations = results.map { "【译】\($0.text)" }
            let blocks = zip(results, translations).map {
                LayoutPreservingRenderer.Block(normalizedBox: $0.0.boundingBox, translatedText: $0.1)
            }
            let rendered = LayoutPreservingRenderer.render(originalImage: image, blocks: blocks)

            await MainActor.run {
                statusLabel.isHidden = true
                imageView.image = rendered
            }
        } catch {
            await updateStatus("处理失败:\(error.localizedDescription)")
        }
    }

    private func updateStatus(_ text: String) async {
        await MainActor.run {
            statusLabel.text = text
        }
    }

    private func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL,
                   let data = try? Data(contentsOf: url),
                   let img = UIImage(data: data) {
                    continuation.resume(returning: img)
                } else if let img = item as? UIImage {
                    continuation.resume(returning: img)
                } else if let data = item as? Data,
                          let img = UIImage(data: data) {
                    continuation.resume(returning: img)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SnapTranslateShare", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法解析图片数据"]
                    ))
                }
            }
        }
    }

    @IBAction func done() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
