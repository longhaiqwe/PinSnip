# PinSnip Core Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that captures a region, adds basic vector annotations, copies/saves it, and pins screenshots or clipboard content above other windows.

**Architecture:** AppKit owns application lifecycle, status item, global hotkeys, borderless overlay panels, and pinned windows. Pure Swift value types own geometry, annotation state, clipboard classification, and image transformations so they can be tested without UI automation. ScreenCaptureKit supplies snapshots and Core Graphics renders export output.

**Tech Stack:** Swift 6.2, AppKit, ScreenCaptureKit, CoreGraphics, Carbon hotkeys, XCTest, XcodeGen.

---

### Task 1: Project skeleton and geometry model

**Files:**
- Create: `project.yml`
- Create: `PinSnip/Core/SelectionRect.swift`
- Test: `PinSnipTests/SelectionRectTests.swift`

- [ ] **Step 1: Write the failing geometry tests**

```swift
func testDragNormalizesInEveryDirection() {
    XCTAssertEqual(SelectionRect(start: .init(x: 80, y: 50), end: .init(x: 20, y: 10)).rect,
                   CGRect(x: 20, y: 10, width: 60, height: 40))
}

func testClampedSelectionStaysInsideBounds() {
    let subject = SelectionRect(start: .init(x: -5, y: 10), end: .init(x: 120, y: 90))
    XCTAssertEqual(subject.clamped(to: CGRect(x: 0, y: 0, width: 100, height: 80)).rect,
                   CGRect(x: 0, y: 10, width: 100, height: 70))
}
```

- [ ] **Step 2: Generate and run the test target**

Run: `xcodegen generate && xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/SelectionRectTests`
Expected: FAIL because `SelectionRect` is not defined.

- [ ] **Step 3: Implement normalized and clamped selection geometry**

```swift
struct SelectionRect: Equatable {
    let start: CGPoint
    let end: CGPoint
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    func clamped(to bounds: CGRect) -> SelectionRect {
        let intersection = rect.intersection(bounds)
        return SelectionRect(start: intersection.origin,
                             end: CGPoint(x: intersection.maxX, y: intersection.maxY))
    }
}
```

- [ ] **Step 4: Run the focused and full test suites**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: TEST SUCCEEDED.

### Task 2: Annotation document and undo/redo

**Files:**
- Create: `PinSnip/Annotations/Annotation.swift`
- Create: `PinSnip/Annotations/AnnotationDocument.swift`
- Test: `PinSnipTests/AnnotationDocumentTests.swift`

- [ ] **Step 1: Write failing tests for append, undo, and redo**

```swift
func testUndoAndRedoMoveAnnotationsBetweenStacks() {
    var document = AnnotationDocument()
    document.append(.rectangle(.init(x: 1, y: 2, width: 30, height: 40), .red, 3))
    document.undo()
    XCTAssertTrue(document.annotations.isEmpty)
    document.redo()
    XCTAssertEqual(document.annotations.count, 1)
}
```

- [ ] **Step 2: Run and observe the expected missing-type failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/AnnotationDocumentTests`
Expected: FAIL because `AnnotationDocument` is not defined.

- [ ] **Step 3: Implement value-based annotation history**

```swift
struct AnnotationDocument {
    private(set) var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    mutating func append(_ annotation: Annotation) { annotations.append(annotation); redoStack.removeAll() }
    mutating func undo() { if let item = annotations.popLast() { redoStack.append(item) } }
    mutating func redo() { if let item = redoStack.popLast() { annotations.append(item) } }
}
```

- [ ] **Step 4: Run tests and confirm history behavior passes**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: TEST SUCCEEDED.

### Task 3: Clipboard payload classification

**Files:**
- Create: `PinSnip/Clipboard/ClipboardPayload.swift`
- Create: `PinSnip/Clipboard/ClipboardReader.swift`
- Test: `PinSnipTests/ClipboardPayloadTests.swift`

- [ ] **Step 1: Write failing tests for colors and ordinary text**

```swift
func testHexTextBecomesColorCard() {
    XCTAssertEqual(ClipboardPayload.classify(text: "#0EA5E9"), .color(.init(red: 14/255, green: 165/255, blue: 233/255, alpha: 1)))
}

func testOrdinaryTextRemainsText() {
    XCTAssertEqual(ClipboardPayload.classify(text: "ship the useful thing"), .text("ship the useful thing"))
}
```

- [ ] **Step 2: Run and observe the missing classifier failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/ClipboardPayloadTests`
Expected: FAIL because `ClipboardPayload.classify` is not defined.

- [ ] **Step 3: Implement strict hex parsing and pasteboard precedence**

```swift
static func classify(text: String) -> ClipboardPayload {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let color = RGBAColor(hex: value) { return .color(color) }
    return .text(text)
}
```

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: TEST SUCCEEDED.

### Task 4: App lifecycle, status item, and global commands

**Files:**
- Create: `PinSnip/App/AppDelegate.swift`
- Create: `PinSnip/App/PinSnipApp.swift`
- Create: `PinSnip/Hotkeys/GlobalHotKeyCenter.swift`
- Create: `PinSnip/Resources/Info.plist`

- [ ] **Step 1: Add command-state tests before UI wiring**

Create `PinSnipTests/AppCommandTests.swift` with a recorder command handler and assertions that `.capture` and `.paste` are dispatched exactly once.

- [ ] **Step 2: Run and observe the missing command router failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/AppCommandTests`
Expected: FAIL because `AppCommandRouter` is not defined.

- [ ] **Step 3: Implement the router, status menu, and Carbon hotkey registration**

Register `Control-Shift-1` for capture and `Control-Shift-2` for paste; route both menu actions and hotkey events through `AppCommandRouter`.

- [ ] **Step 4: Build the app**

Run: `xcodebuild build -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

### Task 5: Capture service and selection overlay

**Files:**
- Create: `PinSnip/Capture/ScreenCaptureService.swift`
- Create: `PinSnip/Capture/CaptureCoordinator.swift`
- Create: `PinSnip/Capture/SelectionOverlayController.swift`
- Create: `PinSnip/Capture/SelectionOverlayView.swift`

- [ ] **Step 1: Add tests for display-coordinate conversion**

Create `PinSnipTests/DisplayCoordinateMapperTests.swift` covering Retina scale and AppKit/CoreGraphics vertical-axis conversion.

- [ ] **Step 2: Run and observe the missing mapper failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/DisplayCoordinateMapperTests`
Expected: FAIL because `DisplayCoordinateMapper` is not defined.

- [ ] **Step 3: Implement ScreenCaptureKit snapshot and overlay panels**

Capture each active display with `SCScreenshotManager`, then create one borderless panel per screen. The overlay darkens unselected content, draws a cyan selection border and size label, and commits a normalized selection on mouse-up.

- [ ] **Step 4: Build and manually invoke capture**

Run: `open build/Debug/PinSnip.app`
Expected: selecting “截图” from the menu bar shows the permission guide or selection overlay.

### Task 6: Annotation canvas and rendered export

**Files:**
- Create: `PinSnip/Annotations/AnnotationCanvasView.swift`
- Create: `PinSnip/Annotations/AnnotationToolbarController.swift`
- Create: `PinSnip/Annotations/AnnotationRenderer.swift`
- Test: `PinSnipTests/AnnotationRendererTests.swift`

- [ ] **Step 1: Write a failing renderer pixel test**

Render a red rectangle over a white 32×32 bitmap and assert the border pixel differs from the untouched center pixel.

- [ ] **Step 2: Run and observe the missing renderer failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/AnnotationRendererTests`
Expected: FAIL because `AnnotationRenderer` is not defined.

- [ ] **Step 3: Implement rectangle, arrow, and pencil rendering**

Keep annotations vector-backed until export. Composite the cropped screenshot and annotations into an sRGB bitmap at the source image scale.

- [ ] **Step 4: Run renderer and full tests**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: TEST SUCCEEDED.

### Task 7: Copy, save, and pin output actions

**Files:**
- Create: `PinSnip/Output/CaptureOutputService.swift`
- Create: `PinSnip/Pins/PinWindowController.swift`
- Create: `PinSnip/Pins/PinImageView.swift`
- Test: `PinSnipTests/PinTransformTests.swift`

- [ ] **Step 1: Write failing tests for rotation, flip, scale, and opacity clamps**

```swift
func testOpacityIsClamped() {
    XCTAssertEqual(PinTransform(opacity: 2).opacity, 1)
    XCTAssertEqual(PinTransform(opacity: -1).opacity, 0.15)
}
```

- [ ] **Step 2: Run and observe the missing transform failure**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/PinTransformTests`
Expected: FAIL because `PinTransform` is not defined.

- [ ] **Step 3: Implement output and borderless pinned windows**

Copy TIFF and PNG representations to `NSPasteboard`, save PNG with `NSSavePanel`, and create a movable borderless `NSPanel` whose context menu controls transform, click-through, and topmost state.

- [ ] **Step 4: Run tests and exercise every output button**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS'`
Expected: TEST SUCCEEDED; copy, save, and pin each produce visible output.

### Task 8: Clipboard-to-pin workflow and release smoke test

**Files:**
- Modify: `PinSnip/Clipboard/ClipboardReader.swift`
- Modify: `PinSnip/Pins/PinWindowController.swift`
- Create: `README.md`

- [ ] **Step 1: Add pasteboard integration tests using a unique pasteboard**

Cover PNG data, file URL, plain text, and `#RRGGBB` color in precedence order.

- [ ] **Step 2: Run the integration tests and observe failures for unsupported payloads**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/ClipboardReaderTests`
Expected: FAIL for each not-yet-supported payload.

- [ ] **Step 3: Implement image, file, text-card, and color-card conversion**

Render text cards with adaptive width, padding, and semantic colors; render color cards with HEX/RGB labels and contrasting foreground text.

- [ ] **Step 4: Run tests, build Release, and launch the app bundle**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' && xcodebuild build -project PinSnip.xcodeproj -scheme PinSnip -configuration Release -destination 'platform=macOS'`
Expected: TEST SUCCEEDED and BUILD SUCCEEDED with no new warnings.

