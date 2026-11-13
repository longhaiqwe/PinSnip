import SwiftUI
import PinSnipCore

/// 沿所选屏幕边缘排列，图片始终保持正向。
struct ShelfView: View {
    @ObservedObject var coordinator: ShelfCoordinator

    var body: some View {
        GeometryReader { geo in
            let vertical = coordinator.edge.isVertical
            let contentHeight = max(0, geo.size.height - ShelfLayout.controlsHeight)
            let available = vertical ? contentHeight : geo.size.width
            let layout = ShelfLayout.arrangement(
                originalSizes: coordinator.items.map(\.originalSize),
                availableLength: available,
                edge: coordinator.edge
            )
            let length = layout.contentLength
            let hidden = ShelfLayout.hiddenOffset(edge: coordinator.edge)
            VStack(spacing: 0) {
                ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                    shelfContent(layout: layout, vertical: vertical)
                        .frame(
                            width: vertical ? geo.size.width : length,
                            height: vertical ? length : contentHeight
                        )
                }
                .id(coordinator.edge)
                .frame(height: contentHeight)
                // 横向保留卡片下方的阴影和“已复制”提示，最终由面板边界裁切。
                .scrollClipDisabled(!vertical)

                ShelfClearButton(isEnabled: !coordinator.items.isEmpty && !coordinator.isDragging) {
                    coordinator.clearAll()
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: ShelfControlsRectKey.self,
                        value: geometry.frame(in: .named("shelfPanel"))
                    )
                })
                .frame(maxWidth: .infinity)
                .frame(height: ShelfLayout.controlsHeight)
            }
            .offset(
                x: coordinator.isRevealed ? 0 : hidden.width,
                y: coordinator.isRevealed ? 0 : hidden.height
            )
            .animation(
                coordinator.isRevealed
                    ? .spring(response: 0.42, dampingFraction: 0.82)
                    : .easeIn(duration: 0.22),
                value: coordinator.isRevealed
            )
        }
        .overlay(alignment: .topLeading) {
            if let point = coordinator.dropIndicator {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: coordinator.edge.isVertical ? 120 : 3,
                        height: coordinator.edge.isVertical ? 3 : 120
                    )
                    .position(point)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "shelfPanel")
        .clipped()
        .onPreferenceChange(ShelfSlotRectsKey.self) { rects in
            coordinator.slotRects = rects
        }
        .onPreferenceChange(ShelfControlsRectKey.self) { rect in
            coordinator.controlsRect = rect
        }
        .onPreferenceChange(ShelfHitRectsKey.self) { rects in
            coordinator.hitRects = rects
        }
    }

    private func shelfContent(layout: ShelfLayout.Arrangement, vertical: Bool) -> some View {
        let length = layout.contentLength
        return ZStack(alignment: .topLeading) {
            if vertical {
                // 竖向绳索从夹子后方穿过，缩略图不随方向旋转。
                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 1, height: length)
                    .position(x: ShelfLayout.panelHeight / 2, y: length / 2)
                    .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            } else {
                ShelfRope(width: length)
            }

            if coordinator.items.isEmpty {
                ShelfHint()
                    .frame(maxWidth: vertical ? ShelfLayout.panelHeight - 32 : nil)
                    .position(
                        x: vertical ? ShelfLayout.panelHeight / 2 : length / 2,
                        y: vertical ? length / 2 : ShelfLayout.ropeY(x: length / 2, width: length) + 34
                    )
                    .transition(.opacity)
            }

            ForEach(Array(coordinator.items.enumerated()), id: \.element.id) { index, item in
                let frame = layout.frames[index]
                ShelfCardView(
                    item: item,
                    isCopied: coordinator.copiedID == item.id,
                    isShelfRevealed: coordinator.isRevealed,
                    onCopy: { coordinator.copy(item: item) },
                    onPin: { coordinator.pinToDesktop(item: item) },
                    onMarkup: { coordinator.openMarkup(item: item) },
                    onDiscard: { coordinator.discard(item: item) },
                    onRevealInFinder: { coordinator.revealInFinder(item: item) },
                    onDragStart: { coordinator.beginDragging(item: item) },
                    onDragEnd: { coordinator.endDragging() }
                )
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: ShelfSlotRectsKey.self,
                        value: [item.id: geometry.frame(in: .named("shelfPanel"))]
                    )
                })
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.78), value: coordinator.items.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: coordinator.items.isEmpty)
    }
}

/// 物理下垂的绳索（带高光、阴影与两端透明度渐变）
struct ShelfRope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = ShelfLayout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(
                    x: width / 2,
                    y: top + 2 * ShelfLayout.sag(width: width)
                )
            )
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4)
                .offset(y: 1.2)
                .blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4)
                .offset(y: -0.35)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
    }
}

private struct ShelfHint: View {
    var body: some View {
        Text("截图将悬挂在此处，触手可及")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// 布局槽位跟随照片尺寸，独立于摇摆动效，避免拖动插入点抖动。
struct ShelfSlotRectsKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 图标和文字整体居中，清理后可从菜单栏恢复。
struct ShelfClearButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("一键清理", systemImage: "tray.and.arrow.down")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help("取下全部截图与动图，原文件保留，可从菜单栏恢复")
    }
}

private struct ShelfControlsRectKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
