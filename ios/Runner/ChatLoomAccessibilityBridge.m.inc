// SPDX-License-Identifier: AGPL-3.0-or-later
#import <dlfcn.h>

// xcross links Runner with ld64 directly (no Clang availability runtime).
// Resolve these public iOS 17+ symbols from Apple's system framework so the
// same runner also starts on older iOS, where the media signal stays null.

@interface ChatLoomAccessibilityBridge : NSObject {
  void* _accessibilityLibrary;
  BOOL (*_animatedImagesEnabled)(void);
}
@property(nonatomic, strong) FlutterMethodChannel* channel;
+ (instancetype)shared;
- (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;
@end

@implementation ChatLoomAccessibilityBridge
+ (instancetype)shared {
  static ChatLoomAccessibilityBridge* bridge;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ bridge = [[ChatLoomAccessibilityBridge alloc] init]; });
  return bridge;
}
- (instancetype)init {
  self = [super init];
  if (self) {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[UIAccessibilityReduceMotionStatusDidChangeNotification,
        UIAccessibilityReduceTransparencyStatusDidChangeNotification, UIApplicationDidBecomeActiveNotification]) {
      [center addObserver:self selector:@selector(settingsChanged) name:name object:nil];
    }
    _accessibilityLibrary = dlopen("/System/Library/Frameworks/Accessibility.framework/Accessibility", RTLD_LAZY | RTLD_LOCAL);
    if (_accessibilityLibrary != NULL) {
      _animatedImagesEnabled = (BOOL (*)(void))dlsym(_accessibilityLibrary, "AXAnimatedImagesEnabled");
      CFStringRef const* notification = (CFStringRef const*)dlsym(_accessibilityLibrary, "AXAnimatedImagesEnabledDidChangeNotification");
      if (notification != NULL && *notification != NULL) {
        [center addObserver:self selector:@selector(settingsChanged) name:(__bridge NSString*)*notification object:nil];
      }
    }
  }
  return self;
}
- (NSDictionary*)snapshot {
  id animated = [NSNull null];
  if (_animatedImagesEnabled != NULL) animated = @(_animatedImagesEnabled());
  return @{@"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
           @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
           @"animatedImages": animated};
}
- (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  [self.channel setMethodCallHandler:nil];
  self.channel = [FlutterMethodChannel methodChannelWithName:@"chatloom/ios_accessibility" binaryMessenger:messenger];
  __weak ChatLoomAccessibilityBridge* weakSelf = self;
  [self.channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
    if ([call.method isEqualToString:@"snapshot"]) result([weakSelf snapshot]);
    else result(FlutterMethodNotImplemented);
  }];
}
- (void)settingsChanged {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.channel invokeMethod:@"settingsChanged" arguments:[self snapshot]];
  });
}
@end
