//
//  SplashView.swift
//  SnapTranslate
//
//  100% 还原自 Figma 设计稿(node 205:161)。设计画板基准 iPhone 16 Pro 尺寸 402×874。
//
//  布局结构(自上而下):
//  - 背景纯白
//  - 两个装饰圆球(模糊光晕),都在屏幕顶部以上,只露下半圈
//    - 右上青色 #00FDED @20% blur 75 / offset (138, -436)
//    - 左上浅蓝 #E1ECFF @100% blur 75 / offset (-161, -438)
//  - 主视觉:品牌标语 SVG (BrandSlogan, 354×170),距屏幕顶 259pt
//  - 底部小标识:36×36 logo + 标题「快捷识屏」18pt Heavy 水平排列,距屏幕底 64pt
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            // 背景:纯白
            Color.white
                .ignoresSafeArea()

            // 装饰圆球 1:右上青色 #00FDED @20%(Figma LAYER_BLUR 300 → SwiftUI .blur 75 经验值)
            Circle()
                .fill(Color(red: 0.0/255, green: 253.0/255, blue: 237.0/255))
                .opacity(0.20)
                .frame(width: 311, height: 311)
                .blur(radius: 75)
                .offset(x: 138, y: -436)

            // 装饰圆球 2:左上浅蓝 #E1ECFF @100%
            Circle()
                .fill(Color(red: 225.0/255, green: 236.0/255, blue: 255.0/255))
                .frame(width: 311, height: 311)
                .blur(radius: 75)
                .offset(x: -161, y: -438)

            // 主内容布局:
            // - 品牌标语 SVG 距屏幕顶 188.5pt,与底部 logo 顶上下间距约 3:7
            // - 底部 logo + 标题距屏幕底 32pt
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 188.5)

                // 品牌标语 SVG 354×170,水平居中
                Image("BrandSlogan")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 354, height: 170)

                Spacer()

                // 底部 logo + 标题(水平排列),距屏幕底 32pt
                HStack(alignment: .center, spacing: 8) {
                    Image("SplashLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)

                    // 「快捷识屏」改用 SVG 资源(70×17),不再依赖 Alibaba PuHuiTi 字体
                    Image("SplashBrandText")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 17)
                }
                .frame(height: 36)

                Spacer()
                    .frame(height: 32)
            }
        }
    }
}

#Preview {
    SplashView()
}
