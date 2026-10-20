import XCTest
@testable import PinSnipCore

final class ShelfLayoutTests: XCTestCase {
    func testDropPositionReordersHorizontallyForTopAndBottom() {
        let ids = (0..<4).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: 40 + index * 174, y: 20, width: 150, height: 160))
        })
        for edge in [ShelfEdge.top, .bottom] {
            XCTAssertEqual(ShelfReordering.insertionIndex(draggedID: ids[0], orderedIDs: ids, frames: frames, point: CGPoint(x: 900, y: 40), edge: edge), 3)
            XCTAssertEqual(ShelfReordering.insertionIndex(draggedID: ids[3], orderedIDs: ids, frames: frames, point: CGPoint(x: 0, y: 190), edge: edge), 0)
            let index = ShelfReordering.insertionIndex(draggedID: ids[0], orderedIDs: ids, frames: frames, point: CGPoint(x: 350, y: 40), edge: edge)!
            XCTAssertEqual(ShelfReordering.moving(ids[0], to: index, in: ids), [ids[1], ids[0], ids[2], ids[3]])
        }
    }

    func testDropPositionReordersVerticallyUsingScrolledFrames() {
        let ids = (0..<4).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: 30, y: -160 + index * 174, width: 150, height: 174))
        })
        for edge in [ShelfEdge.left, .right] {
            let index = ShelfReordering.insertionIndex(draggedID: ids[3], orderedIDs: ids, frames: frames, point: CGPoint(x: 190, y: 150), edge: edge)!
            XCTAssertEqual(index, 2)
            XCTAssertEqual(ShelfReordering.moving(ids[3], to: index, in: ids), [ids[0], ids[1], ids[3], ids[2]])
            XCTAssertEqual(ShelfReordering.insertionIndex(draggedID: ids[0], orderedIDs: ids, frames: frames, point: CGPoint(x: 20, y: 650), edge: edge), 3)
        }
    }

    func testDropRejectsUnknownItemsAndIncompleteGeometry() {
        let id = UUID()
        let frame = CGRect(x: 30, y: 20, width: 150, height: 174)
        XCTAssertNil(ShelfReordering.insertionIndex(draggedID: UUID(), orderedIDs: [id], frames: [id: frame], point: .zero, edge: .top))
        XCTAssertNil(ShelfReordering.insertionIndex(draggedID: id, orderedIDs: [id, UUID()], frames: [id: frame], point: .zero, edge: .top))
        XCTAssertEqual(ShelfReordering.insertionIndex(draggedID: id, orderedIDs: [id], frames: [id: frame], point: .zero, edge: .top), 0)
        XCTAssertEqual(ShelfReordering.moving(id, to: 0, in: [id]), [id])
        XCTAssertEqual(ShelfReordering.moving(UUID(), to: 0, in: [id]), [id])
    }

    func testPanelFramesRespectVisibleAreaOnOffsetDisplay() {
        let visible = CGRect(x: -1440, y: 80, width: 1440, height: 850)
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .top), CGRect(x: -1440, y: 720, width: 1440, height: 210))
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .bottom), CGRect(x: -1440, y: 80, width: 1440, height: 210))
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .left), CGRect(x: -1440, y: 80, width: 210, height: 850))
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .right), CGRect(x: -210, y: 80, width: 210, height: 850))
    }

    func testEdgeActivationAndRetractionZonesIncludeDockGap() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 960)
        let visible = CGRect(x: -1380, y: 60, width: 1320, height: 870)
        let points: [ShelfEdge: CGPoint] = [
            .top: CGPoint(x: -700, y: 950), .bottom: CGPoint(x: -700, y: 1),
            .left: CGPoint(x: -1439, y: 500), .right: CGPoint(x: -1, y: 500)
        ]
        for edge in ShelfEdge.allCases {
            let trigger = ShelfLayout.activationZone(in: screen, edge: edge, topInset: 30)
            XCTAssertTrue(trigger.contains(points[edge]!))
            XCTAssertFalse(trigger.contains(CGPoint(x: -700, y: 500)))
            let panel = ShelfLayout.panelFrame(in: visible, edge: edge)
            let retention = ShelfLayout.retentionZone(panel: panel, screen: screen, edge: edge)
            XCTAssertTrue(retention.contains(points[edge]!))
            XCTAssertTrue(retention.contains(CGPoint(x: panel.midX, y: panel.midY)))
        }
    }

    func testHiddenOffsetsMoveOutThroughSelectedEdge() {
        XCTAssertEqual(ShelfLayout.hiddenOffset(edge: .top), CGSize(width: 0, height: -222))
        XCTAssertEqual(ShelfLayout.hiddenOffset(edge: .bottom), CGSize(width: 0, height: 222))
        XCTAssertEqual(ShelfLayout.hiddenOffset(edge: .left), CGSize(width: -222, height: 0))
        XCTAssertEqual(ShelfLayout.hiddenOffset(edge: .right), CGSize(width: 222, height: 0))
    }

    func testEdgePreferenceDefaultsAndSurvivesNewStore() {
        let suite = "ShelfLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfEdgeStore(defaults: defaults)
        XCTAssertEqual(store.load(), .top)
        for edge in ShelfEdge.allCases {
            store.save(edge)
            XCTAssertEqual(ShelfEdgeStore(defaults: defaults).load(), edge)
        }
        defaults.set("unknown", forKey: "PinSnip.ShelfEdge.v1")
        XCTAssertEqual(store.load(), .top)
    }

    func testSagCalculation() {
        XCTAssertEqual(ShelfLayout.sag(width: 0), 0)
        XCTAssertEqual(ShelfLayout.sag(width: 1000), 18)
        XCTAssertEqual(ShelfLayout.sag(width: 2000), 30) // capped at 30
    }

    func testRopeYParabolaEndpointsAndMidpoint() {
        let width: CGFloat = 1000
        let ropeTop = ShelfLayout.ropeTop
        // At x = 0 and x = width, curve starts/ends at ropeTop
        XCTAssertEqual(ShelfLayout.ropeY(x: 0, width: width), ropeTop, accuracy: 0.001)
        XCTAssertEqual(ShelfLayout.ropeY(x: width, width: width), ropeTop, accuracy: 0.001)

        // At midpoint, curve drops by sag
        let midY = ShelfLayout.ropeY(x: width / 2, width: width)
        let expectedSag = ShelfLayout.sag(width: width)
        XCTAssertEqual(midY, ropeTop + expectedSag, accuracy: 0.001)
    }

    func testCardXCentering() {
        let width: CGFloat = 1000
        // 1 item should be placed exactly in center
        XCTAssertEqual(ShelfLayout.x(index: 0, count: 1, width: width), 500)

        // 3 items should be symmetric around center
        let x0 = ShelfLayout.x(index: 0, count: 3, width: width)
        let x1 = ShelfLayout.x(index: 1, count: 3, width: width)
        let x2 = ShelfLayout.x(index: 2, count: 3, width: width)
        XCTAssertEqual(x1, 500)
        XCTAssertEqual(500 - x0, x2 - 500)
        XCTAssertEqual(x1 - x0, ShelfLayout.spacing)
        XCTAssertEqual(x2 - x1, ShelfLayout.spacing)
    }

    func testCapacityCalculation() {
        XCTAssertEqual(ShelfLayout.capacity(forWidth: 500), 3) // min is 3
        XCTAssertEqual(ShelfLayout.capacity(forWidth: 1920), 9)
        XCTAssertEqual(ShelfLayout.capacity(forWidth: 3840), 12) // capped at 12
    }

    func testPhotoSizeAspectFitting() {
        // Landscape photo
        let landscape = ShelfLayout.photoSize(
            for: CGSize(width: 400, height: 200),
            maxWidth: 136,
            maxHeight: 104
        )
        XCTAssertEqual(landscape.width, 136)
        XCTAssertEqual(landscape.height, 68)

        // Portrait photo
        let portrait = ShelfLayout.photoSize(
            for: CGSize(width: 100, height: 200),
            maxWidth: 136,
            maxHeight: 104
        )
        XCTAssertEqual(portrait.width, 52)
        XCTAssertEqual(portrait.height, 104)
    }
}
