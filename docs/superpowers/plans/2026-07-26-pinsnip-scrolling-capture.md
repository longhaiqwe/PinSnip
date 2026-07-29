# PinSnip Scrolling Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a discoverable scrolling-screenshot workflow that captures a selected viewport, stitches vertically scrolled frames, stops at the page end, and lets the user copy, save, or pin the long image.

**Architecture:** `PinSnipCore` owns deterministic pixel sampling, vertical-offset matching, and segment assembly so the image algorithm is covered by XCTest. The AppKit layer reuses ScreenCaptureKit to capture only the selected viewport, excludes PinSnip's own panels, automatically posts scroll-wheel input when Accessibility access is already available, and otherwise falls back to user-driven scrolling without blocking the feature.

**Tech Stack:** Swift 6.3, AppKit, ApplicationServices, ScreenCaptureKit, CoreGraphics, XCTest, XcodeGen.

---

### Task 1: Define scrolling-frame analysis

**Files:**
- Create: `PinSnip/Core/ScrollingCapture.swift`
- Create: `PinSnipTests/ScrollingCaptureTests.swift`

- [ ] **Step 1: Write failing frame-analysis tests**

```swift
func testDetectsVerticalOffsetBetweenContentFrames() {
    let previous = frame(rows: Array(0..<60))
    let current = frame(rows: Array(20..<80))

    XCTAssertEqual(
        ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
        .scrolled(pixelOffset: 20)
    )
}

func testIgnoresAStickyHeaderWhenMatchingScrolledContent() {
    let previous = frame(rows: Array(repeating: 240, count: 8) + Array(0..<52))
    let current = frame(rows: Array(repeating: 240, count: 8) + Array(20..<72))

    XCTAssertEqual(
        ScrollingFrameAnalyzer.analyze(previous: previous, current: current),
        .scrolled(pixelOffset: 20)
    )
}

func testReportsUnchangedAndUnrelatedFrames() {
    let frame = frame(rows: Array(0..<60))
    XCTAssertEqual(
        ScrollingFrameAnalyzer.analyze(previous: frame, current: frame),
        .unchanged
    )
    XCTAssertEqual(
        ScrollingFrameAnalyzer.analyze(
            previous: frame,
            current: frame(rows: Array((0..<60).reversed()))
        ),
        .unmatched
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/ScrollingCaptureTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `ScrollingCaptureFrame` and `ScrollingFrameAnalyzer` do not exist.

- [ ] **Step 3: Implement sampled vertical matching**

Add the following public API and implement it with normalized RGB absolute error over sampled columns. Compare same-position samples first for `.unchanged`; then search offsets from 2 pixels to the configured maximum while excluding the top and bottom margins so fixed browser chrome does not dominate the match.

```swift
public struct ScrollingCaptureFrame: Equatable {
    public let width: Int
    public let height: Int
    public let rgbaPixels: [UInt8]

    public init(width: Int, height: Int, rgbaPixels: [UInt8])
    public init?(image: CGImage)
}

public enum ScrollingFrameAnalysis: Equatable, Sendable {
    case unchanged
    case scrolled(pixelOffset: Int)
    case unmatched
}

public struct ScrollingFrameAnalyzer {
    public static func analyze(
        previous: ScrollingCaptureFrame,
        current: ScrollingCaptureFrame
    ) -> ScrollingFrameAnalysis
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: `ScrollingCaptureTests` passes.

### Task 2: Assemble long images with bounds

**Files:**
- Modify: `PinSnip/Core/ScrollingCapture.swift`
- Modify: `PinSnipTests/ScrollingCaptureTests.swift`

- [ ] **Step 1: Write failing assembler tests**

```swift
func testAssemblerAppendsOnlyNewPixels() throws {
    let assembler = ScrollingCaptureAssembler(maximumPixelCount: 10_000)
    XCTAssertEqual(assembler.append(try image(rows: Array(0..<60))), .started(totalPixelHeight: 60))
    XCTAssertEqual(assembler.append(try image(rows: Array(20..<80))), .appended(pixelHeight: 20, totalPixelHeight: 80))

    let result = try XCTUnwrap(assembler.makeImage())
    XCTAssertEqual(result.width, 8)
    XCTAssertEqual(result.height, 80)
    XCTAssertEqual(try rowValue(in: result, y: 79), 79)
}

func testAssemblerStopsBeforeExceedingPixelBudget() throws {
    let assembler = ScrollingCaptureAssembler(maximumPixelCount: 8 * 70)
    _ = assembler.append(try image(rows: Array(0..<60)))

    XCTAssertEqual(
        assembler.append(try image(rows: Array(20..<80))),
        .reachedLimit(totalPixelHeight: 60)
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run the Task 1 test command.

Expected: FAIL because `ScrollingCaptureAssembler` is missing.

- [ ] **Step 3: Implement bounded segment assembly**

Add an assembler that retains the first image plus copied bottom strips, rejects width changes, caps output by pixel count, and renders all accepted segments top-to-bottom.

```swift
public enum ScrollingCaptureAppendResult: Equatable, Sendable {
    case started(totalPixelHeight: Int)
    case unchanged(totalPixelHeight: Int)
    case appended(pixelHeight: Int, totalPixelHeight: Int)
    case unmatched(totalPixelHeight: Int)
    case reachedLimit(totalPixelHeight: Int)
}

public final class ScrollingCaptureAssembler {
    public init(maximumPixelCount: Int = 24_000_000)
    @discardableResult public func append(_ image: CGImage) -> ScrollingCaptureAppendResult
    public func makeImage() -> CGImage?
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Task 1 test command.

Expected: all scrolling-capture algorithm tests pass.

### Task 3: Capture the selected viewport while it scrolls

**Files:**
- Create: `PinSnip/Capture/ScreenScrollingCapture.swift`
- Create: `PinSnip/Capture/ScrollingCapturePanelController.swift`
- Modify: `PinSnip/Capture/CaptureCoordinator.swift`

- [ ] **Step 1: Reuse tested geometry and output semantics**

Use `ScreenRecordingGeometry` for the ScreenCaptureKit `sourceRect`, set the output to the selected viewport's full backing-pixel size, set `showsCursor = false`, and exclude PinSnip's own `SCRunningApplication` so the progress panel and border never appear in captured frames.

- [ ] **Step 2: Implement automatic and manual capture loops**

Create these app-layer types:

```swift
enum ScrollingCaptureMode {
    case automatic
    case manual
}

enum ScrollingCaptureOutputAction {
    case copy
    case save
    case pin
}

@MainActor
final class ScreenScrollingCapture {
    static let maximumPixelCount = 24_000_000

    func start(
        screen: NSScreen,
        selectionRect: CGRect,
        mode: ScrollingCaptureMode,
        onProgress: @escaping (Int, Int) -> Void,
        onStopRequested: @escaping () -> Void
    ) async throws
    func stop() async -> CGImage?
    func cancel()
}
```

Automatic mode posts a pixel scroll event at the selected viewport center, waits for the page to settle, captures a frame, and stops after two unchanged captures or the pixel limit. Manual mode captures periodically and waits for the user to press an output button.

- [ ] **Step 3: Add a non-captured progress panel**

`ScrollingCapturePanelController` owns the existing blue region border and a floating panel with status plus `取消`, `保存…`, `贴图`, and primary `复制` actions. It exposes:

```swift
var onCancel: (() -> Void)?
var onStop: ((ScrollingCaptureOutputAction) -> Void)?
func present()
func update(frameCount: Int, pixelHeight: Int)
func showExporting()
func finish()
```

- [ ] **Step 4: Wire lifecycle and raw long-image output**

`CaptureCoordinator` dismisses the selection overlay before capture, chooses `.automatic` only when `AXIsProcessTrusted()` is already true, falls back to `.manual` otherwise, routes copied/saved long images without social-card decoration, and cancels recorder/panel state cleanly on errors.

- [ ] **Step 5: Build the app**

Run:

```bash
xcodebuild build -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

### Task 4: Expose scrolling capture in the overlay and menu

**Files:**
- Modify: `PinSnip/Core/CaptureToolbarLayout.swift`
- Modify: `PinSnipTests/CaptureToolbarLayoutTests.swift`
- Modify: `PinSnip/Core/AppCommand.swift`
- Modify: `PinSnipTests/AppCommandTests.swift`
- Modify: `PinSnip/Capture/SelectionOverlayView.swift`
- Modify: `PinSnip/Capture/SelectionOverlayController.swift`
- Modify: `PinSnip/App/AppDelegate.swift`

- [ ] **Step 1: Write failing routing and toolbar tests**

```swift
func testStillImageToolbarIncludesScrollingCaptureBeforeOutputActions() {
    XCTAssertEqual(
        CaptureToolbarLayout.stillImageTrailingActions,
        [.scrollCapture, .save, .pin, .cancel, .copy]
    )
}

func testScrollingCaptureSelectionKeepsStartAtTheFarRight() {
    XCTAssertEqual(
        CaptureToolbarLayout.scrollingCaptureActions,
        [.cancel, .scrollCapture]
    )
}
```

Extend `AppCommandTests` so `.captureScrolling` is routed between ordinary capture and GIF recording.

- [ ] **Step 2: Run both focused suites and verify RED**

Run:

```bash
xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/CaptureToolbarLayoutTests -only-testing:PinSnipTests/AppCommandTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the new action and command cases are missing.

- [ ] **Step 3: Add the action, selection purpose, and menu entry**

Add `.scrollCapture = 24`, `.captureScrolling`, and `.scrollingCapture`. Render the action with SF Symbol `rectangle.stack`, help text `滚动截屏`, and cyan tint. Treat it like GIF recording in `finish(_:)`: return the selection rectangle without cropping it first. Add a menu item named `滚动截屏…`.

- [ ] **Step 4: Run the focused suites and verify GREEN**

Run the Step 2 command.

Expected: both focused suites pass.

### Task 5: Document and verify the complete feature

**Files:**
- Modify: `README.md`
- Modify: `docs/product/parity-matrix.md`
- Regenerate: `PinSnip.xcodeproj/project.pbxproj`

- [ ] **Step 1: Document the workflow and permission fallback**

README must state that users can select `滚动截屏…` from the menu or use the stack button after F1 selection; PinSnip auto-scrolls when Accessibility access is already granted, otherwise it asks the user to scroll manually; capture remains local.

- [ ] **Step 2: Mark the capability in the parity matrix**

Move scrolling capture out of the generic planned “超级截屏” bucket and record automatic/manual scrolling capture as complete.

- [ ] **Step 3: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: the new sources and tests appear in `PinSnip.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Run full verification**

Run:

```bash
xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./scripts/build-release.sh
```

Expected: all tests pass, the Universal Release build succeeds, and `build/Release/PinSnip.app` contains both `arm64` and `x86_64`.

- [ ] **Step 5: Audit without committing**

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Expected: only the scrolling-capture implementation, its tests/docs, the generated project update, and this plan are modified. Do not commit until the user confirms the real-app behavior.
