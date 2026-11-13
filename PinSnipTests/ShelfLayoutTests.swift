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
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .top), CGRect(x: -1280, y: 720, width: 1120, height: 210))
        XCTAssertEqual(ShelfLayout.panelFrame(in: visible, edge: .bottom), CGRect(x: -1280, y: 80, width: 1120, height: 210))
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

    func testHorizontalMarginsExcludeControlsFromActivationAndRetention() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 960)
        let visible = CGRect(x: -1380, y: 60, width: 1380, height: 870)
        for edge in [ShelfEdge.top, .bottom] {
            let panel = ShelfLayout.panelFrame(in: visible, edge: edge)
            let trigger = ShelfLayout.activationZone(in: screen, edge: edge, topInset: 30, visibleFrame: visible)
            let retention = ShelfLayout.retentionZone(panel: panel, screen: screen, edge: edge)
            XCTAssertEqual(panel.minX - visible.minX, 160)
            XCTAssertEqual(visible.maxX - panel.maxX, 160)
            XCTAssertEqual(trigger.minX, panel.minX)
            XCTAssertEqual(trigger.maxX, panel.maxX)
            for x in [visible.minX + 20, visible.maxX - 20] {
                XCTAssertFalse(trigger.contains(CGPoint(x: x, y: trigger.midY)))
                XCTAssertFalse(retention.contains(CGPoint(x: x, y: panel.midY)))
            }
            XCTAssertTrue(trigger.contains(CGPoint(x: panel.midX, y: trigger.midY)))
        }
    }

    func testHorizontalMarginsScaleDownOnNarrowScreens() {
        let visible = CGRect(x: 200, y: -500, width: 400, height: 400)
        for edge in [ShelfEdge.top, .bottom] {
            let panel = ShelfLayout.panelFrame(in: visible, edge: edge)
            XCTAssertEqual(panel.width, 200)
            XCTAssertEqual(panel.midX, visible.midX)
            XCTAssertTrue(visible.contains(panel))
        }
    }

    func testPointerAtPhysicalTopEdgeActivatesWithVisibleOrHiddenMenuBar() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let pointer = CGPoint(x: screen.midX, y: screen.maxY)
        for menuBarHeight: CGFloat in [0, 30] {
            let visible = CGRect(x: screen.minX, y: screen.minY + 67,
                                 width: screen.width, height: screen.height - 67 - menuBarHeight)
            let trigger = ShelfLayout.activationZone(in: screen, edge: .top,
                                                     topInset: menuBarHeight, visibleFrame: visible)
            XCTAssertTrue(ShelfLayout.containsPointer(pointer, in: screen))
            XCTAssertTrue(ShelfLayout.containsPointer(pointer, in: trigger))
            let panel = ShelfLayout.panelFrame(in: visible, edge: .top)
            let retention = ShelfLayout.retentionZone(panel: panel, screen: screen, edge: .top)
            XCTAssertTrue(ShelfLayout.containsPointer(pointer, in: retention))
            XCTAssertTrue(ShelfLayout.containsPointer(CGPoint(x: pointer.x, y: panel.maxY), in: retention))
        }
    }

    func testPhysicalEdgesStayWithinActivationAndRetentionZones() {
        let screen = CGRect(x: 1920, y: -300, width: 1440, height: 900)
        let points: [ShelfEdge: CGPoint] = [
            .top: CGPoint(x: screen.midX, y: screen.maxY),
            .bottom: CGPoint(x: screen.midX, y: screen.minY),
            .left: CGPoint(x: screen.minX, y: screen.midY),
            .right: CGPoint(x: screen.maxX, y: screen.midY)
        ]
        for edge in ShelfEdge.allCases {
            let point = points[edge]!
            let trigger = ShelfLayout.activationZone(in: screen, edge: edge, topInset: 30)
            let panel = ShelfLayout.panelFrame(in: screen, edge: edge)
            let retention = ShelfLayout.retentionZone(panel: panel, screen: screen, edge: edge)
            XCTAssertTrue(ShelfLayout.containsPointer(point, in: screen), "\(edge)")
            XCTAssertTrue(ShelfLayout.containsPointer(point, in: trigger), "\(edge)")
            XCTAssertTrue(ShelfLayout.containsPointer(point, in: retention), "\(edge)")
        }
    }

    func testInclusivePointerBoundsDoNotExpandTriggerIntoMarginsOrOutsideScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let trigger = ShelfLayout.activationZone(in: screen, edge: .top, topInset: 30)
        for point in [CGPoint(x: 0, y: screen.maxY), CGPoint(x: screen.maxX, y: screen.maxY),
                      CGPoint(x: trigger.minX - 0.5, y: screen.maxY),
                      CGPoint(x: trigger.maxX + 0.5, y: screen.maxY),
                      CGPoint(x: screen.midX, y: screen.maxY + 0.5),
                      CGPoint(x: screen.midX, y: trigger.minY - 0.5)] {
            XCTAssertFalse(ShelfLayout.containsPointer(point, in: trigger))
        }
        XCTAssertFalse(ShelfLayout.containsPointer(.zero, in: .zero))
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

    func testShortImagesUseTheirHeightsOnEitherSide() {
        for edge in [ShelfEdge.left, .right] {
            let layout = ShelfLayout.arrangement(
                originalSizes: [CGSize(width: 1200, height: 120), CGSize(width: 400, height: 200)],
                availableLength: 800, edge: edge
            )
            let first = layout.frames[0], second = layout.frames[1]
            XCTAssertEqual(first.height, 36)
            XCTAssertEqual(second.height, 90)
            XCTAssertEqual(second.minY - first.maxY, 24)
            XCTAssertEqual(second.midY - first.midY, 87)
            XCTAssertEqual((first.minY + second.maxY) / 2, 400)
            XCTAssertEqual(layout.contentLength, 800)
        }
    }

    func testNarrowImagesUseTheirWidthsAtTopAndBottom() {
        for edge in [ShelfEdge.top, .bottom] {
            let layout = ShelfLayout.arrangement(
                originalSizes: [CGSize(width: 100, height: 400), CGSize(width: 400, height: 200)],
                availableLength: 800, edge: edge
            )
            let first = layout.frames[0], second = layout.frames[1]
            XCTAssertEqual(first.width, 34)
            XCTAssertEqual(second.width, 144)
            XCTAssertEqual(second.minX - first.maxX, 24)
            XCTAssertEqual(second.midX - first.midX, 113)
            XCTAssertEqual((first.minX + second.maxX) / 2, 400)
            XCTAssertEqual(first.minY + ShelfLayout.pinAbove,
                           ShelfLayout.ropeY(x: first.midX, width: layout.contentLength))
        }
    }

    func testOverflowUsesActualExtentsAndKeepsBothEndsReachable() {
        for edge in ShelfEdge.allCases {
            let layout = ShelfLayout.arrangement(
                originalSizes: Array(repeating: CGSize(width: 400, height: 200), count: 8),
                availableLength: 300, edge: edge
            )
            let first = layout.frames.first!, last = layout.frames.last!
            XCTAssertEqual(edge.isVertical ? first.minY : first.minX, 30)
            XCTAssertEqual(layout.contentLength - (edge.isVertical ? last.maxY : last.maxX), 30)
            XCTAssertEqual(layout.contentLength, edge.isVertical ? 948 : 1380)
        }
    }

    func testEmptyAndSingleItemRemainCentered() {
        for edge in ShelfEdge.allCases {
            let empty = ShelfLayout.arrangement(originalSizes: [], availableLength: 800, edge: edge)
            XCTAssertTrue(empty.frames.isEmpty)
            XCTAssertEqual(empty.contentLength, 800)
            let single = ShelfLayout.arrangement(originalSizes: [.zero], availableLength: 800, edge: edge)
            let frame = single.frames[0]
            XCTAssertEqual(edge.isVertical ? frame.midY : frame.midX, 400)
            XCTAssertEqual(frame.size, CGSize(width: 144, height: 126))
        }
    }

    func testVariableSlotsReorderUsingActualCentersAfterScrolling() {
        let ids = (0..<3).map { _ in UUID() }
        for edge in ShelfEdge.allCases {
            let layout = ShelfLayout.arrangement(
                originalSizes: [CGSize(width: 1200, height: 120), CGSize(width: 100, height: 400),
                                CGSize(width: 400, height: 200)],
                availableLength: 200, edge: edge
            )
            let frames = Dictionary(uniqueKeysWithValues: zip(ids, layout.frames.map {
                $0.offsetBy(dx: edge.isVertical ? 0 : -50, dy: edge.isVertical ? -50 : 0)
            }))
            let middle = frames[ids[1]]!
            let point = CGPoint(x: middle.midX + 1, y: middle.midY + 1)
            XCTAssertEqual(ShelfReordering.insertionIndex(
                draggedID: ids[0], orderedIDs: ids, frames: frames, point: point, edge: edge
            ), 1)
        }
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
