#import "LegacyScreenCapture.h"

CGImageRef PinSnipCopyDisplayImage(CGDirectDisplayID displayID) {
    if (!CGPreflightScreenCaptureAccess() || !CGDisplayIsActive(displayID)) return NULL;
    return CGDisplayCreateImage(displayID);
}

CGImageRef PinSnipCopyWindowImage(CGWindowID windowID) {
    if (!CGPreflightScreenCaptureAccess()) return NULL;
    return CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        windowID, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
}
