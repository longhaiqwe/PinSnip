import AppKit
import PinSnipCore

struct WindowDetector {
    func candidates(on screen: NSScreen) -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let primaryScreen = NSScreen.screens.first
        else { return [] }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return windowInfo.enumerated().compactMap { zOrder, info in
            guard let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerProcessID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerProcessID != ownProcessID,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }

            guard let localFrame = WindowFrameMapper.localFrame(
                quartzFrame: quartzFrame,
                primaryScreenMaxY: primaryScreen.frame.maxY,
                screenFrame: screen.frame
            ), localFrame.width >= 20, localFrame.height >= 20
            else { return nil }

            return WindowCandidate(id: windowID, frame: localFrame, zOrder: zOrder)
        }
    }
}
