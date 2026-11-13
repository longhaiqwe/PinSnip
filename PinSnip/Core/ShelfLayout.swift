import Foundation

public enum ShelfEdge: String, CaseIterable, Sendable {
    case top, bottom, left, right

    public var isVertical: Bool { self == .left || self == .right }

    public var title: String {
        switch self {
        case .top: return "上方"
        case .bottom: return "下方"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
}

public final class ShelfEdgeStore {
    private let defaults: UserDefaults
    private let key = "PinSnip.ShelfEdge.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ShelfEdge {
        defaults.string(forKey: key).flatMap(ShelfEdge.init(rawValue:)) ?? .top
    }

    public func save(_ edge: ShelfEdge) { defaults.set(edge.rawValue, forKey: key) }
}

/// 晾衣架几何尺寸与绳索曲线布局计算
public enum ShelfLayout {
    public static let panelHeight: CGFloat = 210
    public static let ropeTop: CGFloat = 10
    public static let cardGap: CGFloat = 24
    public static let endPadding: CGFloat = 30
    public static let cardInset: CGFloat = 4
    public static let clipWidth: CGFloat = 9
    public static let clipHeight: CGFloat = 26
    public static let clipOverlap: CGFloat = 12
    public static let pinAbove: CGFloat = 9.5
    public static let maxPhotoWidth: CGFloat = 136
    public static let maxPhotoHeight: CGFloat = 104
    public static let controlsHeight: CGFloat = 44

    /// 鼠标可停在物理屏幕端点；CGRect.contains 会排除 maxX / maxY。
    public static func containsPointer(_ point: CGPoint, in rect: CGRect) -> Bool {
        !rect.isEmpty
            && point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// 横向停靠时给两端控制键留空；窄屏保留至少一半宽度。
    public static func horizontalMargin(forWidth width: CGFloat) -> CGFloat {
        min(160, max(0, width) * 0.25)
    }

    /// AppKit 屏幕坐标，原点在左下；避开菜单栏和 Dock。
    public static func panelFrame(in visible: CGRect, edge: ShelfEdge) -> CGRect {
        let thickness = min(panelHeight, edge.isVertical ? visible.width : visible.height)
        let margin = horizontalMargin(forWidth: visible.width)
        switch edge {
        case .top:
            return CGRect(x: visible.minX + margin, y: visible.maxY - thickness, width: visible.width - 2 * margin, height: thickness)
        case .bottom:
            return CGRect(x: visible.minX + margin, y: visible.minY, width: visible.width - 2 * margin, height: thickness)
        case .left:
            return CGRect(x: visible.minX, y: visible.minY, width: thickness, height: visible.height)
        case .right:
            return CGRect(x: visible.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        }
    }

    public static func activationZone(in screen: CGRect, edge: ShelfEdge, topInset: CGFloat, visibleFrame: CGRect? = nil) -> CGRect {
        let band: CGFloat = 4
        let horizontal = panelFrame(in: visibleFrame ?? screen, edge: edge)
        switch edge {
        case .top:
            let height = max(band, topInset)
            return CGRect(x: horizontal.minX, y: screen.maxY - height, width: horizontal.width, height: height)
        case .bottom:
            return CGRect(x: horizontal.minX, y: screen.minY, width: horizontal.width, height: band)
        case .left:
            return CGRect(x: screen.minX, y: screen.minY, width: band, height: screen.height)
        case .right:
            return CGRect(x: screen.maxX - band, y: screen.minY, width: band, height: screen.height)
        }
    }

    /// 展开后允许光标经过面板与屏幕边缘间的 Dock / 菜单栏区域。
    public static func retentionZone(panel: CGRect, screen: CGRect, edge: ShelfEdge) -> CGRect {
        switch edge {
        case .top:
            return CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: screen.maxY - panel.minY)
        case .bottom:
            return CGRect(x: panel.minX, y: screen.minY, width: panel.width, height: panel.maxY - screen.minY)
        case .left:
            return CGRect(x: screen.minX, y: panel.minY, width: panel.maxX - screen.minX, height: panel.height)
        case .right:
            return CGRect(x: panel.minX, y: panel.minY, width: screen.maxX - panel.minX, height: panel.height)
        }
    }

    /// SwiftUI 坐标，原点在左上。
    public static func hiddenOffset(edge: ShelfEdge) -> CGSize {
        let distance = panelHeight + 12
        switch edge {
        case .top: return CGSize(width: 0, height: -distance)
        case .bottom: return CGSize(width: 0, height: distance)
        case .left: return CGSize(width: -distance, height: 0)
        case .right: return CGSize(width: distance, height: 0)
        }
    }

    /// 绳索中部最大下垂幅度（抛物线顶点深度）
    public static func sag(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(30, width * 0.018)
    }

    /// 计算给定 X 坐标处绳索的 Y 坐标（二次抛物线曲线）
    public static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = min(max(x / width, 0), 1)
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    public struct Arrangement {
        public let contentLength: CGFloat
        public let frames: [CGRect]
    }

    /// 按实际缩略图、画框及夹子尺寸排列；槽位不包含摇摆动画，保证拖动落点稳定。
    public static func arrangement(
        originalSizes: [CGSize], availableLength: CGFloat, edge: ShelfEdge
    ) -> Arrangement {
        let sizes = originalSizes.map { original in
            let photo = photoSize(for: original)
            return CGSize(
                width: max(clipWidth, photo.width + 2 * cardInset),
                height: max(clipHeight, photo.height + 2 * cardInset + clipHeight - clipOverlap)
            )
        }
        let extents = sizes.map { edge.isVertical ? $0.height : $0.width }
        let total = extents.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * cardGap
        let length = max(availableLength, total + 2 * endPadding)
        var cursor = (length - total) / 2
        let frames = sizes.enumerated().map { index, size in
            let center = cursor + extents[index] / 2
            defer { cursor += extents[index] + cardGap }
            return CGRect(
                x: edge.isVertical ? (panelHeight - size.width) / 2 : cursor,
                y: edge.isVertical ? cursor : ropeY(x: center, width: length) - pinAbove,
                width: size.width,
                height: size.height
            )
        }
        return Arrangement(contentLength: length, frames: frames)
    }

    /// 根据屏幕宽度计算推荐容纳的卡片数量
    public static func capacity(forWidth width: CGFloat) -> Int {
        let usable = max(0, width - 200)
        // 保持原有存储容量策略，不因缩略图尺寸或排列方向改变而丢弃图片。
        return max(3, min(12, Int(usable / 174)))
    }

    /// 计算等比缩放后的预览图尺寸（保持原比例适配卡片）
    public static func photoSize(
        for size: CGSize,
        maxWidth: CGFloat = maxPhotoWidth,
        maxHeight: CGFloat = maxPhotoHeight
    ) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
    }
}

/// 根据当前可见布局（包含滚动偏移）计算移除拖动项后的插入位置。
public enum ShelfReordering {
    public static func insertionIndex(
        draggedID: UUID, orderedIDs: [UUID], frames: [UUID: CGRect],
        point: CGPoint, edge: ShelfEdge
    ) -> Int? {
        guard orderedIDs.contains(draggedID), orderedIDs.allSatisfy({ frames[$0] != nil }) else { return nil }
        let coordinate = edge.isVertical ? point.y : point.x
        return orderedIDs.filter { id in
            guard id != draggedID, let frame = frames[id] else { return false }
            return coordinate > (edge.isVertical ? frame.midY : frame.midX)
        }.count
    }

    public static func moving(_ id: UUID, to index: Int, in ids: [UUID]) -> [UUID] {
        guard ids.contains(id) else { return ids }
        var result = ids.filter { $0 != id }
        result.insert(id, at: min(max(index, 0), result.count))
        return result
    }
}
