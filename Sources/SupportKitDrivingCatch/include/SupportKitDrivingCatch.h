// What `SupportKitDriving` cannot do in Swift: stop an `NSException` raised while it performs
// a command. Swift has no `@try`, and an exception out of the channel's poll, a repeating
// timer's callout, leaves that timer firing, so it never fires again: one command that
// raised ended the channel (Maquette, 2026-11-16).
//
// Defined only in DEBUG on macOS, as the channel is, so a Release build of this target is an
// object with no symbol. Declared always: a Swift target imports this header with its own
// flags, not this target's, so a declaration behind `DEBUG` was not seen by SwiftPM's native
// build system, and the Swift that calls it is itself compiled only in DEBUG.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the exception it raised, or nil when it returned. The frames
/// between are unwound as AppKit's own loop unwinds an event whose action raised: what they
/// held is not released.
FOUNDATION_EXPORT NSException *_Nullable SupportKitDrivingCatching(
    NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
