import XCTest
@testable import PinSnipCore

final class AnimationPlaybackStateTests: XCTestCase {
    func testAdvancesThroughEveryFrameAndWrapsToTheFirstFrame() {
        var playback = AnimationPlaybackState(frameCount: 3)

        XCTAssertEqual(playback.frameIndex, 0)
        XCTAssertEqual(playback.advance(), 1)
        XCTAssertEqual(playback.advance(), 2)
        XCTAssertEqual(playback.advance(), 0)
    }

    func testSingleFrameNeverAdvancesPastItsOnlyFrame() {
        var playback = AnimationPlaybackState(frameCount: 1)

        XCTAssertEqual(playback.advance(), 0)
    }
}
