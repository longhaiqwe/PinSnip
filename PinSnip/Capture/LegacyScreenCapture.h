#import <CoreGraphics/CoreGraphics.h>

// Public Quartz compatibility APIs, isolated from Swift's unavailable imports.
// Kept only for recovery when a ScreenCaptureKit screenshot does not return.
CGImageRef _Nullable PinSnipCopyDisplayImage(CGDirectDisplayID displayID) CF_RETURNS_RETAINED;
CGImageRef _Nullable PinSnipCopyWindowImage(CGWindowID windowID) CF_RETURNS_RETAINED;
