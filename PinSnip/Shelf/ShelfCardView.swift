import SwiftUI
import PinSnipCore

/// 单张卡片在屏幕上的绝对命中范围 Key，用于告知面板仅在卡片区域响应鼠标
struct ShelfHitRectsKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 晾衣架单张卡片：金属夹子 + 毛玻璃画框 + 物理轻微摇曳动效
struct ShelfCardView: View {
    @ObservedObject var item: ShelfItem
    let isCopied: Bool
    let isShelfRevealed: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onMarkup: () -> Void
    let onDiscard: () -> Void
    let onRevealInFinder: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void

    @State private var swing: Double = 0
    @State private var arrived: Bool = false
    @State private var isHovering: Bool = false

    private static let cardCornerRadius: CGFloat = 16
    private static let cardInset: CGFloat = 4

    var body: some View {
        VStack(spacing: -12) {
            ShelfClothespin()
                .zIndex(1)
            cardContent
        }
        .rotationEffect(.degrees(swing + item.tilt), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        .opacity(item.isFalling ? 0 : (arrived ? 1 : 0))
        .onAppear {
            arrive()
        }
        .onChange(of: isCopied) { _, copied in
            if copied {
                nudge(3.5)
            }
        }
    }

    private var photoSize: CGSize {
        ShelfLayout.photoSize(for: item.originalSize)
    }

    @ViewBuilder
    private var preview: some View {
        if item.isAnimated {
            ShelfGIFPreview(
                url: item.url,
                placeholder: item.thumb,
                isPlaying: isShelfRevealed && !item.isFalling
            )
            .allowsHitTesting(false)
        } else {
            Image(nsImage: item.thumb)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private var cardContent: some View {
        preview
            .frame(width: photoSize.width, height: photoSize.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Self.cardCornerRadius - Self.cardInset,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: Self.cardCornerRadius - Self.cardInset,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .padding(Self.cardInset)
            .shelfGlassFrame(cornerRadius: Self.cardCornerRadius)
            .shadow(
                color: Color.black.opacity(isHovering ? 0.28 : 0.16),
                radius: isHovering ? 14 : 8,
                y: isHovering ? 8 : 4
            )
            .scaleEffect(isHovering ? 1.03 : 1.0, anchor: .top)
            .overlay(alignment: .bottomTrailing) {
                if item.isAnimated {
                    Text("GIF")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .padding(7)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
            .overlay(alignment: .topLeading) {
                // 左上角关闭按钮
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 18, height: 18)
                    .shelfGlassFrame(circle: true)
                    .padding(4)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(
                ShelfGrabArea(
                    item: item,
                    onCopy: onCopy,
                    onPin: onPin,
                    onMarkup: onMarkup,
                    onDiscard: {
                        withAnimation(.easeIn(duration: 0.4)) {
                            item.isFalling = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onDiscard()
                        }
                    },
                    onRevealInFinder: onRevealInFinder,
                    onDragStart: onDragStart,
                    onDragEnd: onDragEnd
                )
            )
            .overlay(alignment: .bottom) {
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已复制")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .shelfGlassFrame(capsule: true)
                    .offset(y: 14)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .onHover { isHovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: ShelfHitRectsKey.self,
                        value: item.isFalling ? [:] : [item.id: g.frame(in: .named("shelfPanel"))]
                    )
                }
            )
    }

    private func arrive() {
        swing = 14
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            arrived = true
        }
        withAnimation(.interpolatingSpring(stiffness: 45, damping: 2.8)) {
            swing = 0
        }
    }

    private func nudge(_ degrees: Double) {
        withAnimation(.easeOut(duration: 0.25)) {
            swing = degrees
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) {
                swing = 0
            }
        }
    }
}

/// 拟物金属夹子（铝合金质感与线槽）
struct ShelfClothespin: View {
    private let metalGradient = LinearGradient(
        stops: [
            .init(color: Color(white: 0.70), location: 0),
            .init(color: Color(white: 0.94), location: 0.35),
            .init(color: Color(white: 0.82), location: 0.65),
            .init(color: Color(white: 0.62), location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(metalGradient)
            .frame(width: 9, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.black.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            )
            .overlay(alignment: .top) {
                // 绳索穿孔凹槽
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 5, height: 1.4)
                    .padding(.top, 8.5)
            }
            .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}

extension View {
    /// 带有超薄材质与细腻高光描边的毛玻璃画框
    func shelfGlassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle())
            : capsule ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        return background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
            .overlay(
                shape.stroke(Color.black.opacity(0.08), lineWidth: 0.5).padding(-0.5)
            )
    }
}
