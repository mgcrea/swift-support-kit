#include "SupportKitDrivingCatch.h"
#include <TargetConditionals.h>

#if TARGET_OS_OSX && defined(DEBUG)

NSException *_Nullable SupportKitDrivingCatching(NS_NOESCAPE void (^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  } @catch (id other) {
    // An object thrown that is not an exception, which AppKit code does not do, but which
    // would otherwise go on up.
    return [NSException exceptionWithName:NSGenericException
                                   reason:[other description]
                                 userInfo:nil];
  }
  return nil;
}

#endif
