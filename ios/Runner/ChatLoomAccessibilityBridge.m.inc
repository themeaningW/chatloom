// SPDX-License-Identifier: AGPL-3.0-or-later
#import <Accessibility/Accessibility.h>

@interface ChatLoomAccessibilityBridge : NSObject
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
    if (@available(iOS 17.0, *)) {
      [center addObserver:self selector:@selector(settingsChanged) name:AXAnimatedImagesEnabledDidChangeNotification object:nil];
    }
  }
  return self;
}
- (NSDictionary*)snapshot {
  id animated = [NSNull null];
  if (@available(iOS 17.0, *)) animated = @(AXAnimatedImagesEnabled());
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
