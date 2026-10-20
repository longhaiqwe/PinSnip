import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationTransformTests: XCTestCase {
    func testNewTextStartsAtClickAndCentersFirstLineVertically() {
        let rect = TextAnnotationLayout.initialRect(at: CGPoint(x: 200, y: 150),
            inside: CGRect(x: 0, y: 0, width: 800, height: 600),
            preferredWidth: 160, minimumWidth: 48, height: 32)
        XCTAssertEqual(rect.minX + TextAnnotationLayout.horizontalTextInset, 200)
        XCTAssertEqual(rect.midY, 150)
    }

    func testTextControlsHaveDistinctBodyBorderAndResizeTargets() {
        let rect = CGRect(x: 100, y: 200, width: 160, height: 32)
        XCTAssertEqual(TextAnnotationLayout.hitTarget(at: CGPoint(x: 180, y: 216), in: rect), .text)
        XCTAssertEqual(TextAnnotationLayout.hitTarget(at: CGPoint(x: 180, y: 237), in: rect), .move)
        XCTAssertEqual(TextAnnotationLayout.hitTarget(at: CGPoint(x: 93, y: 216), in: rect), .resize(.left))
        XCTAssertEqual(TextAnnotationLayout.hitTarget(at: CGPoint(x: 267, y: 216), in: rect), .resize(.right))
        XCTAssertNil(TextAnnotationLayout.hitTarget(at: CGPoint(x: 180, y: 250), in: rect))
    }

    func testResizePreservesPointerGrabOffset() {
        let rect = CGRect(x: 100, y: 200, width: 160, height: 32)
        let target = TextAnnotationLayout.resizePoint(for: .right, in: rect,
            from: CGPoint(x: 268, y: 216), to: CGPoint(x: 288, y: 216))
        XCTAssertEqual(target.x, 280)
        XCTAssertFalse(TextAnnotationLayout.hasDragged(from: .zero, to: CGPoint(x: 1, y: 1)))
        XCTAssertTrue(TextAnnotationLayout.hasDragged(from: .zero, to: CGPoint(x: 3, y: 0)))
    }

    func testMultilineGrowthShiftsUpAtBottomInsteadOfClipping() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let rect = CGRect(x: 100, y: 10, width: 160, height: 32)
        let grown = TextAnnotationLayout.fittingHeight(rect, height: 70, inside: bounds)
        XCTAssertEqual(grown, CGRect(x: 100, y: 0, width: 160, height: 70))
        XCTAssertTrue(bounds.contains(grown))
    }

    func testResizeInNarrowSelectionNeverOverflowsMinimumWidth() {
        let bounds = CGRect(x: 0, y: 0, width: 30, height: 100)
        let rect = CGRect(x: 0, y: 20, width: 30, height: 32)
        for handle in TextAnnotationHandle.allCases {
            let resized = TextAnnotationLayout.resize(rect, handle: handle, to: CGPoint(x: 90, y: 20),
                                                     inside: bounds, minimumWidth: 48)
            XCTAssertTrue(bounds.contains(resized))
        }
    }

    func testMapsRectangleFromOverlayPointsIntoCropPixels() {
        let subject = Annotation.rectangle(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            .black,
            3
        )

        XCTAssertEqual(
            subject.mapped(relativeTo: CGPoint(x: 5, y: 6), scale: 2),
            .rectangle(CGRect(x: 10, y: 28, width: 60, height: 80), .black, 6)
        )
    }

    func testMapsArrowAndPencilPoints() {
        let arrow = Annotation.arrow(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 20, y: 40),
            .white,
            2
        )
        XCTAssertEqual(
            arrow.mapped(relativeTo: CGPoint(x: 10, y: 10), scale: 0.5),
            .arrow(from: CGPoint(x: 0, y: 5), to: CGPoint(x: 5, y: 15), .white, 1)
        )

        let pencil = Annotation.pencil([CGPoint(x: 3, y: 5), CGPoint(x: 4, y: 7)], .black, 4)
        XCTAssertEqual(
            pencil.mapped(relativeTo: CGPoint(x: 1, y: 2), scale: 2),
            .pencil([CGPoint(x: 4, y: 6), CGPoint(x: 6, y: 10)], .black, 8)
        )
    }

    func testMapsSequenceNumberCenterAndDiameter() {
        let number = Annotation.number(
            center: CGPoint(x: 15, y: 22),
            value: 3,
            color: .black,
            diameter: 28
        )

        XCTAssertEqual(
            number.mapped(relativeTo: CGPoint(x: 5, y: 7), scale: 2),
            .number(
                center: CGPoint(x: 20, y: 30),
                value: 3,
                color: .black,
                diameter: 56
            )
        )
    }

    func testMapsTextBoxAndFontSizeIntoCropPixels() {
        let text = Annotation.text(
            rect: CGRect(x: 12, y: 18, width: 90, height: 44),
            text: "说明",
            color: .black,
            fontSize: 24
        )

        XCTAssertEqual(
            text.mapped(relativeTo: CGPoint(x: 5, y: 6), scale: 2),
            .text(
                rect: CGRect(x: 14, y: 24, width: 180, height: 88),
                text: "说明",
                color: .black,
                fontSize: 48
            )
        )
    }

    func testTextBoxRightHandleChangesWidthFromTheRight() {
        let original = CGRect(x: 30, y: 40, width: 120, height: 28)

        XCTAssertEqual(
            TextAnnotationLayout.resize(
                original,
                handle: .right,
                to: CGPoint(x: 210, y: 120),
                inside: CGRect(x: 0, y: 0, width: 240, height: 180),
                minimumWidth: 48
            ),
            CGRect(x: 30, y: 40, width: 180, height: 28)
        )
    }

    func testTextBoxLeftHandleClampsToMinimumWidthAndBounds() {
        let original = CGRect(x: 30, y: 40, width: 120, height: 28)

        XCTAssertEqual(
            TextAnnotationLayout.resize(
                original,
                handle: .left,
                to: CGPoint(x: 140, y: 20),
                inside: CGRect(x: 0, y: 0, width: 240, height: 180),
                minimumWidth: 48
            ),
            CGRect(x: 102, y: 40, width: 48, height: 28)
        )
    }

    func testTextBoxProvidesTwoSideHandlesForWidthAdjustment() {
        XCTAssertEqual(
            TextAnnotationHandle.allCases,
            [.left, .right]
        )
        XCTAssertEqual(TextAnnotationHandle.left.horizontalEdge, .left)
        XCTAssertEqual(TextAnnotationHandle.right.horizontalEdge, .right)
    }

    func testMovingTextBoxStaysInsideSelection() {
        XCTAssertEqual(
            TextAnnotationLayout.move(
                CGRect(x: 30, y: 40, width: 80, height: 30),
                by: CGSize(width: 150, height: -80),
                inside: CGRect(x: 0, y: 0, width: 200, height: 120)
            ),
            CGRect(x: 120, y: 0, width: 80, height: 30)
        )
    }

    func testWechatStyleTextPresetsAndPalette() {
        XCTAssertEqual(TextAnnotationSizePreset.allCases.map(\.title), ["小", "中", "大"])
        XCTAssertEqual(TextAnnotationSizePreset.medium.fontSize, 22)
        XCTAssertEqual(TextAnnotationPalette.colors.count, 6)
        XCTAssertEqual(TextAnnotationPalette.colors.last, RGBAColor(red: 1, green: 0.25, blue: 0.29))
    }

    func testTextContentRectUsesSharedEditorAndRendererInsets() {
        XCTAssertEqual(TextAnnotationLayout.horizontalTextInset, 4)
        XCTAssertEqual(TextAnnotationLayout.verticalTextInset, 2)
        XCTAssertEqual(
            TextAnnotationLayout.contentRect(
                in: CGRect(x: 10, y: 20, width: 120, height: 40)
            ),
            CGRect(x: 14, y: 22, width: 112, height: 36)
        )
        XCTAssertEqual(TextAnnotationLayout.effectiveContentWidth(for: 120), 112)
    }

    func testInitialTextBoxShiftsLeftToStayInsideSelection() {
        XCTAssertEqual(
            TextAnnotationLayout.initialRect(
                at: CGPoint(x: 195, y: 50),
                inside: CGRect(x: 0, y: 0, width: 200, height: 120),
                preferredWidth: 160,
                minimumWidth: 48,
                height: 30
            ),
            CGRect(x: 40, y: 35, width: 160, height: 30)
        )

        XCTAssertEqual(
            TextAnnotationLayout.initialRect(
                at: CGPoint(x: 25, y: 4),
                inside: CGRect(x: 0, y: 0, width: 30, height: 20),
                preferredWidth: 160,
                minimumWidth: 48,
                height: 30
            ),
            CGRect(x: 0, y: 0, width: 30, height: 20)
        )
    }

    func testMovingRectanglePreservesStyleAndStaysInsideSelection() {
        let original = Annotation.rectangle(
            CGRect(x: 30, y: 40, width: 80, height: 50),
            RGBAColor(red: 1, green: 0.25, blue: 0.29),
            3
        )

        XCTAssertEqual(
            RectangleAnnotationLayout.move(
                original,
                by: CGSize(width: 160, height: -100),
                inside: CGRect(x: 0, y: 0, width: 200, height: 120)
            ),
            .rectangle(
                CGRect(x: 120, y: 0, width: 80, height: 50),
                RGBAColor(red: 1, green: 0.25, blue: 0.29),
                3
            )
        )
    }

    func testResizingRectangleUsesAllEightHandlesAndPreservesStyle() {
        let original = Annotation.rectangle(
            CGRect(x: 20, y: 30, width: 100, height: 80),
            .black,
            4
        )

        XCTAssertEqual(
            RectangleAnnotationLayout.resize(
                original,
                using: .northEast,
                to: CGPoint(x: 160, y: 150),
                inside: CGRect(x: 0, y: 0, width: 300, height: 200),
                minimumDimension: 8
            ),
            .rectangle(CGRect(x: 20, y: 30, width: 140, height: 120), .black, 4)
        )
        XCTAssertEqual(SelectionResizeHandle.allCases.count, 8)
    }

    func testRectangleHitTestingIncludesInteriorAndSmallOutsideTolerance() {
        let rectangle = Annotation.rectangle(
            CGRect(x: 20, y: 30, width: 100, height: 80),
            .black,
            3
        )

        XCTAssertTrue(
            RectangleAnnotationLayout.hitTest(
                CGPoint(x: 70, y: 70),
                annotation: rectangle,
                tolerance: 5
            )
        )
        XCTAssertTrue(
            RectangleAnnotationLayout.hitTest(
                CGPoint(x: 17, y: 70),
                annotation: rectangle,
                tolerance: 5
            )
        )
        XCTAssertFalse(
            RectangleAnnotationLayout.hitTest(
                CGPoint(x: 10, y: 70),
                annotation: rectangle,
                tolerance: 5
            )
        )
    }
}
