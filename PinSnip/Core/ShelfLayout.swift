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
    public static let spacing: CGFloat = 174
    public static let cardWidth: CGFloat = 150
    public static let pinAbove: CGFloat = 9.5
    public static let maxPhotoWidth: CGFloat = 136
    public static let maxPhotoHeight: CGFloat = 104

    /// AppKit 屏幕坐标，原点在左下；避开菜单栏和 Dock。
    public static func panelFrame(in visible: CGRect, edge: ShelfEdge) -> CGRect {
        let thickness = min(panelHeight, edge.isVertical ? visible.width : visible.height)
        switch edge {
        case .top:
            return CGRect(x: visible.minX, y: visible.maxY - thickness, width: visible.width, height: thickness)
        case .bottom:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: thickness)
        case .left:
            return CGRect(x: visible.minX, y: visible.minY, width: thickness, height: visible.height)
        case .right:
            return CGRect(x: visible.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        }
    }

    public static func activationZone(in screen: CGRect, edge: ShelfEdge, topInset: CGFloat) -> CGRect {
        let band: CGFloat = 4
        switch edge {
        case .top:
            let height = max(band, topInset)
            return CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        case .bottom:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: band)
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

    /// 计算第 index 张卡片的中心 X 轴坐标（整组卡片水平居中）
    public static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 0, index >= 0, index < count else { return width / 2 }
        let total = CGFloat(max(count - 1, 0)) * spacing
        return width / 2 - total / 2 + CGFloat(index) * spacing
    }

    /// 根据屏幕宽度计算推荐容纳的卡片数量
    public static func capacity(forWidth width: CGFloat) -> Int {
        let usable = max(0, width - 200)
        return max(3, min(12, Int(usable / spacing)))
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
