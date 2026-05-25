//
//  NotificationBar.swift
//  SnapTranslate
//
//  首页快捷指令卡片上方的一条胶囊形彩色提示。
//  Figma 节点:221:526(浅色) / 227:2524(深色)。
//  整体高 56pt:胶囊本体 40pt(从 y=16 开始) + 左侧 60×56 图标从 y=0 开始(向上突出 16pt)。
//  显示/关闭逻辑由父视图通过 @AppStorage 控制。
//

import SwiftUI

struct NotificationBar: View {
    var onLearnMore: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 主体:胶囊背景 + 内容,从 y=16 开始(给图标突出 16pt 空间)
            HStack(spacing: 0) {
                // 左侧 60pt 让位给突出的图标(图标用 overlay 平面叠加)
                Color.clear
                    .frame(width: 60)

                Text("可在下方设置「快捷识屏」功能哦~")
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Button(action: onLearnMore) {
                    Text("了解功能")
                        .font(.custom("PingFangSC-Regular", size: 12))
                        .foregroundColor(.white)
                        .underline() // 加下划线
                        .fixedSize(horizontal: true, vertical: false) // 不折行
                        .padding(.leading, 8) // 文字左 8pt 内边距(去掉右 8 让按钮跟关闭图标更近)
                        .frame(height: 40)
                        .contentShape(.rect)
                }
                .padding(.leading, 8) // 整体在原基础上向右 8pt
                .buttonStyle(.plain)
                .accessibilityLabel("了解功能")

                Button(action: onDismiss) {
                    Image("NotificationClose")
                        .resizable()
                        .frame(width: 14, height: 14)
                        .frame(width: 40, height: 40) // 40×40 点击区
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭通知")
            }
            .frame(height: 40)
            .background {
                capsuleBackground
                    .clipShape(.capsule)
            }
            .offset(y: 16)

            // 左侧图标(NotificationIcon imageset 自带浅/深色 SVG 切换)
            Image("NotificationIcon")
                .resizable()
                .frame(width: 60, height: 56)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }

    /// 胶囊背景:设计师导出的 PNG(NotificationBackground @3x,1134×165 原图)。
    /// 用 .resizable() 不加 aspect ratio,让 image 直接拉伸到父 background frame(40 高),
    /// 避免 scaledToFill 因 PNG 比例偏胖(6.87:1 vs 胶囊 9.25:1)导致父视图被撑高。
    /// 渐变 + 光晕是模糊视觉,纵向压缩 4x 视觉差异微弱。
    private var capsuleBackground: some View {
        Image("NotificationBackground")
            .resizable()
    }
}

#Preview("浅色") {
    VStack(spacing: 20) {
        NotificationBar(onLearnMore: {}, onDismiss: {})
        Spacer()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("深色") {
    VStack(spacing: 20) {
        NotificationBar(onLearnMore: {}, onDismiss: {})
        Spacer()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
