import Foundation

/// 晾衣架卡片基础元数据
public struct ShelfItemRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let originalSize: CGSize
    public let tilt: Double
    public let fileURL: URL
    public let isTemporary: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalSize: CGSize,
        tilt: Double = 0.0,
        fileURL: URL,
        isTemporary: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalSize = originalSize
        self.tilt = tilt
        self.fileURL = fileURL
        self.isTemporary = isTemporary
    }
}

/// 晾衣架项队列管理（包含容量限制和增删操作）
public struct ShelfQueue: Equatable, Sendable {
    public private(set) var items: [ShelfItemRecord]
    public var maxCapacity: Int

    public init(items: [ShelfItemRecord] = [], maxCapacity: Int = 10) {
        self.items = items
        self.maxCapacity = max(1, maxCapacity)
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var count: Int {
        items.count
    }

    /// 在队首插入新项（最新截取的图挂在最左侧或最前）
    @discardableResult
    public mutating func insert(_ item: ShelfItemRecord) -> [ShelfItemRecord] {
        items.insert(item, at: 0)
        var evicted: [ShelfItemRecord] = []
        if items.count > maxCapacity {
            let overflow = items.suffix(from: maxCapacity)
            evicted = Array(overflow)
            items.removeLast(items.count - maxCapacity)
        }
        return evicted
    }

    /// 移除指定 ID 的项
    @discardableResult
    public mutating func remove(id: UUID) -> ShelfItemRecord? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return items.remove(at: index)
    }

    /// 清空所有项
    public mutating func removeAll() -> [ShelfItemRecord] {
        let old = items
        items.removeAll()
        return old
    }

    /// 调整最大容量
    public mutating func updateCapacity(_ newCapacity: Int) -> [ShelfItemRecord] {
        self.maxCapacity = max(1, newCapacity)
        var evicted: [ShelfItemRecord] = []
        if items.count > maxCapacity {
            let overflow = items.suffix(from: maxCapacity)
            evicted = Array(overflow)
            items.removeLast(items.count - maxCapacity)
        }
        return evicted
    }
}
