//
//  SplashView.swift
//  SnapTranslate
//
//  100% 还原自 Figma 设计稿(node 205:161 / 2085:13600 暗色)。设计画板基准 iPhone 16 Pro 尺寸 402×874。
//
//  布局结构(自上而下):
//  - 背景:浅色模式纯白,暗色模式纯黑
//  - 两个装饰圆球(模糊光晕),都在屏幕顶部以上,只露下半圈
//    - 右上青色:浅色 #00FDED @20% / 暗色 @8%(暗色下几乎不可见)
//    - 左上:浅色 #E1ECFF @100% / 暗色品牌绿 #5BAA68 @18%(呼应底部 logo 的绿色)
//  - 主视觉:品牌标语 SVG (BrandSlogan, 354×170),距屏幕顶 259pt
//    - SVG 内的文字色根据外观自动从 #0B0B0D / #FFFFFF 切换(走 Assets appearances)
//  - 底部小标识:36×36 logo + 标题「快捷识屏」18pt Heavy 水平排列,距屏幕底 64pt
//    - 「快捷识屏」SVG 同样有暗色版本
//

import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // 背景:浅色纯白,暗色纯黑
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            // 装饰圆球 1:右上青色 #00FDED(暗色下大幅降低透明度)
            Circle()
                .fill(Color(red: 0.0/255, green: 253.0/255, blue: 237.0/255))
                .opacity(colorScheme == .dark ? 0.08 : 0.20)
                .frame(width: 311, height: 311)
                .blur(radius: 75)
                .offset(x: 138, y: -436)

            // 装饰圆球 2:浅色浅蓝 #E1ECFF / 暗色品牌绿 #5BAA68(呼应 logo 色)
            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 91.0/255, green: 170.0/255, blue: 104.0/255)
                        : Color(red: 225.0/255, green: 236.0/255, blue: 255.0/255)
                )
                .opacity(colorScheme == .dark ? 0.18 : 1.0)
                .frame(width: 311, height: 311)
                .blur(radius: 75)
                .offset(x: -161, y: -438)

            // 主内容布局:
            // - 品牌标语 SVG 距屏幕顶 188.5pt,与底部 logo 顶上下间距约 3:7
            // - 底部 logo + 标题距屏幕底 32pt
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 188.5)

                // 品牌标语 SVG 354×170,水平居中。Assets 内含 light/dark 两份资源
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

                    // 「快捷识屏」SVG 资源(70×17),Assets 内含 light/dark 两份资源
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

#Preview("Light") {
    SplashView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SplashView()
        .preferredColorScheme(.dark)
}
