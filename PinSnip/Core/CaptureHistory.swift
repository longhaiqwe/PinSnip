public struct CaptureHistory<Entry> {
    public let limit: Int

    private var entries: [Entry] = []
    private var nextPasteIndex = 0

    public init(limit: Int = 10) {
        precondition(limit > 0, "Capture history limit must be positive")
        self.limit = limit
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public mutating func record(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        nextPasteIndex = 0
    }

    public mutating func nextForPasting() -> Entry? {
        guard entries.indices.contains(nextPasteIndex) else { return nil }
        defer { nextPasteIndex += 1 }
        return entries[nextPasteIndex]
    }
}
