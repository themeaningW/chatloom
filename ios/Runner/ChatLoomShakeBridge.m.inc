// SPDX-License-Identifier: AGPL-3.0-or-later
// ChatLoom: native UIKit shake stream (generated runner inclusion).
// Kept alongside the Swift runner equivalent; no sensors, swizzling or responder changes.
@interface ChatLoomShakeBridge : NSObject <FlutterStreamHandler>
@property(nonatomic, strong) FlutterEventChannel* channel;
@property(nonatomic, strong) FlutterMethodChannel* availability;
@property(nonatomic, copy) FlutterEventSink sink;
@property(nonatomic, copy) NSString* subscription;
@property(nonatomic, strong) NSNumber* previousShakeToEdit;
+ (instancetype)shared;
- (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger;
- (void)emitShake;
@end

@implementation ChatLoomShakeBridge
+ (instancetype)shared {
  static ChatLoomShakeBridge* bridge;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ bridge = [[ChatLoomShakeBridge alloc] init]; });
  return bridge;
}
- (instancetype)init {
  self = [super init];
  if (self) {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(resumeShake) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(suspendShake) name:UIApplicationWillResignActiveNotification object:nil];
  }
  return self;
}
- (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  [self.channel setStreamHandler:nil];
  [self.availability setMethodCallHandler:nil];
  self.sink = nil;
  self.subscription = nil;
  [self suspendShake];
  self.channel = [FlutterEventChannel eventChannelWithName:@"chatloom/ios_shake" binaryMessenger:messenger];
  [self.channel setStreamHandler:self];
  self.availability = [FlutterMethodChannel methodChannelWithName:@"chatloom/ios_shake/availability" binaryMessenger:messenger];
  [self.availability setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
    if (![call.method isEqualToString:@"isAvailable"]) {
      result(FlutterMethodNotImplemented);
      return;
    }
    BOOL installed = NO;
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) continue;
      for (UIWindow* window in ((UIWindowScene*)scene).windows) {
        if ([window isKindOfClass:NSClassFromString(@"ChatLoomShakeWindow")]) {
          installed = YES;
          break;
        }
      }
      if (installed) break;
    }
    result(@(installed));
  }];
}
- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  self.sink = nil;
  self.subscription = nil;
  [self suspendShake];
  if (![arguments isKindOfClass:[NSString class]] || [(NSString*)arguments length] == 0) {
    return [FlutterError errorWithCode:@"invalid_subscription" message:@"A nonempty subscription nonce is required." details:nil];
  }
  self.subscription = (NSString*)arguments;
  self.sink = events;
  [self resumeShake];
  return nil;
}
- (FlutterError*)onCancelWithArguments:(id)arguments {
  self.sink = nil;
  self.subscription = nil;
  [self suspendShake];
  return nil;
}
- (void)resumeShake {
  UIApplication* application = [UIApplication sharedApplication];
  if (self.sink == nil || application.applicationState != UIApplicationStateActive) return;
  if (self.previousShakeToEdit == nil) {
    self.previousShakeToEdit = @(application.applicationSupportsShakeToEdit);
  }
  application.applicationSupportsShakeToEdit = NO;
}
- (void)suspendShake {
  if (self.previousShakeToEdit != nil) {
    [UIApplication sharedApplication].applicationSupportsShakeToEdit = self.previousShakeToEdit.boolValue;
    self.previousShakeToEdit = nil;
  }
}
- (void)emitShake {
  FlutterEventSink sink = self.sink;
  NSString* subscription = self.subscription;
  if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive || sink == nil || subscription == nil) return;
  sink(@{@"type": @"shake", @"subscription": subscription});
}
@end

@interface ChatLoomShakeWindow : UIWindow
@end
@implementation ChatLoomShakeWindow
- (void)sendEvent:(UIEvent*)event {
  if (self.isKeyWindow && self.windowScene.activationState == UISceneActivationStateForegroundActive &&
      event.type == UIEventTypeMotion && event.subtype == UIEventSubtypeMotionShake) {
    [[ChatLoomShakeBridge shared] emitShake];
  }
  [super sendEvent:event];
}
@end
// ChatLoom: end native UIKit shake stream.
