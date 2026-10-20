import XCTest
@testable import PinSnipCore

final class ShelfQueueTests: XCTestCase {
    func testQueueInsertNewestFirst() {
        var queue = ShelfQueue(maxCapacity: 5)
        let item1 = ShelfItemRecord(
            originalSize: CGSize(width: 100, height: 100),
            fileURL: URL(fileURLWithPath: "/tmp/1.png")
        )
        let item2 = ShelfItemRecord(
            originalSize: CGSize(width: 200, height: 200),
            fileURL: URL(fileURLWithPath: "/tmp/2.png")
        )

        queue.insert(item1)
        queue.insert(item2)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.items.first?.id, item2.id)
        XCTAssertEqual(queue.items.last?.id, item1.id)
    }

    func testQueueEvictsOldestWhenExceedingCapacity() {
        var queue = ShelfQueue(maxCapacity: 2)
        let item1 = ShelfItemRecord(
            originalSize: CGSize(width: 100, height: 100),
            fileURL: URL(fileURLWithPath: "/tmp/1.png")
        )
        let item2 = ShelfItemRecord(
            originalSize: CGSize(width: 200, height: 200),
            fileURL: URL(fileURLWithPath: "/tmp/2.png")
        )
        let item3 = ShelfItemRecord(
            originalSize: CGSize(width: 300, height: 300),
            fileURL: URL(fileURLWithPath: "/tmp/3.png")
        )

        queue.insert(item1)
        queue.insert(item2)
        let evicted = queue.insert(item3)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(evicted.count, 1)
        XCTAssertEqual(evicted.first?.id, item1.id)
        XCTAssertEqual(queue.items.map(\.id), [item3.id, item2.id])
    }

    func testRemoveById() {
        var queue = ShelfQueue(maxCapacity: 5)
        let item1 = ShelfItemRecord(
            originalSize: CGSize(width: 100, height: 100),
            fileURL: URL(fileURLWithPath: "/tmp/1.png")
        )
        let item2 = ShelfItemRecord(
            originalSize: CGSize(width: 200, height: 200),
            fileURL: URL(fileURLWithPath: "/tmp/2.png")
        )

        queue.insert(item1)
        queue.insert(item2)

        let removed = queue.remove(id: item1.id)
        XCTAssertEqual(removed?.id, item1.id)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.id, item2.id)

        let removedAgain = queue.remove(id: item1.id)
        XCTAssertNil(removedAgain)
    }

    func testUpdateCapacityShrinksList() {
        var queue = ShelfQueue(maxCapacity: 5)
        for i in 1...5 {
            queue.insert(ShelfItemRecord(
                originalSize: CGSize(width: i * 10, height: i * 10),
                fileURL: URL(fileURLWithPath: "/tmp/\(i).png")
            ))
        }
        XCTAssertEqual(queue.count, 5)

        let evicted = queue.updateCapacity(3)
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(evicted.count, 2)
    }
}
