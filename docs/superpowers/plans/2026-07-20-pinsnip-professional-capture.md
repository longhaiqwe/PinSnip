# PinSnip Professional Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent screenshot history, repeat-last-region, window selection, delayed/active-window capture, fixed aspect ratios, rounded output, and in-place screenshot refresh to the existing PinSnip core loop.

**Architecture:** Pure Swift models in `PinSnipCore` own history retention, normalized regions, selection constraints, window candidate ranking, and image masking. AppKit adapters discover macOS windows, store PNG history, expose menu commands, and update the existing overlay while keeping annotation state intact.

**Tech Stack:** Swift 6.2, AppKit, ScreenCaptureKit, CoreGraphics, XCTest, XcodeGen.

---

### Task 1: Fixed-aspect selection and normalized last region

**Files:**
- Create: `PinSnip/Core/SelectionConstraint.swift`
- Create: `PinSnip/Core/LastCaptureRegion.swift`
- Test: `PinSnipTests/SelectionConstraintTests.swift`
- Test: `PinSnipTests/LastCaptureRegionTests.swift`

- [x] **Step 1: Write failing behavior tests**

```swift
func testSquareConstraintPreservesDragDirection() {
    XCTAssertEqual(
        SelectionConstraint(aspectRatio: 1).rect(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 60, y: 40),
            inside: CGRect(x: 0, y: 0, width: 100, height: 100)
        ),
        CGRect(x: 10, y: 10, width: 50, height: 50)
    )
}

func testNormalizedRegionRoundTripsOnDifferentScreenSize() {
    let region = LastCaptureRegion(rect: CGRect(x: 100, y: 50, width: 400, height: 200), screenSize: CGSize(width: 1000, height: 500))
    XCTAssertEqual(region.rect(in: CGSize(width: 2000, height: 1000)), CGRect(x: 200, y: 100, width: 800, height: 400))
}
```

- [x] **Step 2: Verify RED**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/SelectionConstraintTests -only-testing:PinSnipTests/LastCaptureRegionTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because both types are missing.

- [x] **Step 3: Implement constrained geometry and normalized storage**

`SelectionConstraint` derives height from the dominant horizontal drag while keeping the original quadrant, then clamps the result to screen bounds. `LastCaptureRegion` stores x/y/width/height as 0...1 fractions and reconstructs a point-space rectangle for the current display size.

- [x] **Step 4: Verify GREEN**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/SelectionConstraintTests -only-testing:PinSnipTests/LastCaptureRegionTests CODE_SIGNING_ALLOWED=NO`
Expected: TEST SUCCEEDED.

### Task 2: Rounded screenshot processor

**Files:**
- Create: `PinSnip/Output/CaptureImageProcessor.swift`
- Test: `PinSnipTests/CaptureImageProcessorTests.swift`

- [ ] **Step 1: Write a failing alpha-mask test**

Create a 20×20 opaque image, call `CaptureImageProcessor.rounded(_:radius:)`, and assert that pixel `(0,0)` is transparent while `(10,10)` remains opaque.

- [ ] **Step 2: Verify RED**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/CaptureImageProcessorTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because `CaptureImageProcessor` is missing.

- [ ] **Step 3: Implement the Core Graphics mask**

Create an sRGB premultiplied-alpha context, clip it with `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)`, draw the original image, and return the resulting `CGImage`.

- [ ] **Step 4: Verify GREEN**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/CaptureImageProcessorTests CODE_SIGNING_ALLOWED=NO`
Expected: TEST SUCCEEDED.

### Task 3: Persistent bounded screenshot history

**Files:**
- Create: `PinSnip/Core/CaptureHistoryStore.swift`
- Test: `PinSnipTests/CaptureHistoryStoreTests.swift`
- Create: `PinSnip/Capture/CaptureHistoryController.swift`

- [ ] **Step 1: Write failing persistence and pruning tests**

```swift
func testEntriesSurviveStoreRecreation() throws {
    let first = try CaptureHistoryStore(directory: directory, capacity: 3)
    let entry = try first.append(imageData: Data("one".utf8), capturedAt: date)
    let second = try CaptureHistoryStore(directory: directory, capacity: 3)
    XCTAssertEqual(second.entries.map(\.id), [entry.id])
    XCTAssertEqual(try second.imageData(for: entry), Data("one".utf8))
}

func testCapacityPrunesOldestFile() throws {
    let store = try CaptureHistoryStore(directory: directory, capacity: 2)
    _ = try store.append(imageData: Data("one".utf8), capturedAt: date)
    _ = try store.append(imageData: Data("two".utf8), capturedAt: date.addingTimeInterval(1))
    _ = try store.append(imageData: Data("three".utf8), capturedAt: date.addingTimeInterval(2))
    XCTAssertEqual(store.entries.count, 2)
}
```

- [ ] **Step 2: Verify RED**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/CaptureHistoryStoreTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because `CaptureHistoryStore` is missing.

- [ ] **Step 3: Implement atomic index and image storage**

Use `index.json` plus an `Images` directory, newest-first entries, UUID filenames, atomic writes, and deletion of overflow files. `CaptureHistoryController` converts successful captures to PNG, appends them, and pins a selected historical image.

- [ ] **Step 4: Verify GREEN**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/CaptureHistoryStoreTests CODE_SIGNING_ALLOWED=NO`
Expected: TEST SUCCEEDED.

### Task 4: Window candidate ranking and macOS discovery

**Files:**
- Create: `PinSnip/Core/WindowCandidate.swift`
- Test: `PinSnipTests/WindowCandidateTests.swift`
- Create: `PinSnip/Capture/WindowDetector.swift`

- [ ] **Step 1: Write failing ranking tests**

```swift
func testSmallestContainingWindowWins() {
    let candidates = [
        WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
        WindowCandidate(id: 2, frame: CGRect(x: 20, y: 20, width: 100, height: 100))
    ]
    XCTAssertEqual(WindowCandidate.best(at: CGPoint(x: 30, y: 30), in: candidates)?.id, 2)
}
```

- [ ] **Step 2: Verify RED**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/WindowCandidateTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because `WindowCandidate` is missing.

- [ ] **Step 3: Implement ranking and Core Graphics adapter**

Rank visible layer-zero windows containing the cursor by ascending area. Convert Quartz top-left global bounds to AppKit coordinates using the primary screen's `frame.maxY`, exclude PinSnip's PID, desktop elements, and windows smaller than 20×20 points.

- [ ] **Step 4: Verify GREEN**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/WindowCandidateTests CODE_SIGNING_ALLOWED=NO`
Expected: TEST SUCCEEDED.

### Task 5: Wire professional capture controls into the overlay

**Files:**
- Modify: `PinSnip/Capture/SelectionOverlayView.swift`
- Modify: `PinSnip/Capture/SelectionOverlayController.swift`
- Modify: `PinSnip/Capture/CaptureCoordinator.swift`

- [x] **Step 1: Add overlay state tests to the pure models**

Extend the Task 1 tests with 4:3, 16:9, reverse-direction, and bounds-clamping cases before changing the overlay.

- [x] **Step 2: Verify the new cases fail if the constraint behavior is incomplete**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/SelectionConstraintTests CODE_SIGNING_ALLOWED=NO`
Expected: the new boundary case fails before its implementation is added.

- [ ] **Step 3: Add window hover, ratio and corner controls, repeat region, and refresh**

Pass window frames into the overlay; hover selects the smallest window until manual dragging starts. Add ratio choices Free/1:1/4:3/16:9 and corner choices 0/8/16/32. Return the selected rect with the rendered image, save it as the last region, apply the rounded processor on output, and make F5 replace the screenshot while leaving `AnnotationDocument` untouched.

- [ ] **Step 4: Build the application**

Run: `xcodebuild build -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

### Task 6: Menu commands for history, delay, active window, and repeat region

**Files:**
- Modify: `PinSnip/Core/AppCommand.swift`
- Modify: `PinSnip/App/AppDelegate.swift`
- Modify: `PinSnip/Capture/CaptureCoordinator.swift`
- Modify: `README.md`
- Modify: `docs/product/parity-matrix.md`

- [ ] **Step 1: Extend the existing command router test first**

Route `.captureActiveWindow`, `.captureLastRegion`, `.captureDelayed(seconds: 3)`, and `.showHistory` and assert the exact command order.

- [ ] **Step 2: Verify RED**

Run: `xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' -only-testing:PinSnipTests/AppCommandTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL because the new command cases are missing.

- [ ] **Step 3: Implement menu and history submenu actions**

Add status-menu entries for active window, repeat area, 3/5-second delay, and the ten newest history entries. History selection pins the stored PNG. Active-window capture starts with that window preselected; delayed capture waits without blocking the main thread.

- [ ] **Step 4: Run complete verification and commit**

Run: `./scripts/build-release.sh && git status --short`
Expected: all tests pass, Release build succeeds, and only the intended Phase 2 files are modified before commit.
