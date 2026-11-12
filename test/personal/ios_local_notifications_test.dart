// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/ios_local_notifications.dart';
import 'package:chatloom/personal/ui/ios_notifications_page.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  late IosLocalNotifications notifications;
  var allowed = false;
  var failInitialization = false;
  Map<String, Object?>? launch;
  Completer<bool>? permissionRequest;
  Completer<bool>? initialization;
  var failShow = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    allowed = false;
    failInitialization = false;
    launch = null;
    permissionRequest = null;
    initialization = null;
    failShow = false;
    notifications = IosLocalNotifications();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              if (initialization != null) return initialization!.future;
              if (failInitialization) {
                throw PlatformException(code: 'fixture-unavailable');
              }
              return true;
            case 'getNotificationAppLaunchDetails':
              return launch;
            case 'checkPermissions':
              return {'isEnabled': allowed};
            case 'requestPermissions':
              if (permissionRequest != null) return permissionRequest!.future;
              return allowed;
            case 'openAppNotificationSettings':
              return true;
            case 'show':
              if (failShow) {
                throw PlatformException(code: 'fixture-show-failed');
              }
              return null;
            default:
              throw StateError(
                'Unexpected notification operation ${call.method}',
              );
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'initialization is shared, enables banners, and never requests permission',
    () async {
      await Future.wait([
        notifications.initialize(),
        notifications.initialize(),
      ]);
      final init =
          calls.where((c) => c.method == 'initialize').single.arguments as Map;
      expect(init['requestAlertPermission'], isFalse);
      expect(init['requestSoundPermission'], isFalse);
      expect(init['requestBadgePermission'], isFalse);
      expect(init['defaultPresentBanner'], isTrue);
      expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
    },
  );

  test(
    'failed initialization can be retried without masking failure',
    () async {
      failInitialization = true;
      await expectLater(
        notifications.initialize(),
        throwsA(isA<PlatformException>()),
      );
      failInitialization = false;
      await notifications.initialize();
      expect(calls.where((c) => c.method == 'initialize'), hasLength(2));
    },
  );

  test(
    'explicit permission requests are coalesced and ask only alert/sound/badge',
    () async {
      permissionRequest = Completer<bool>();
      final first = notifications.requestPermission();
      final second = notifications.requestPermission();
      permissionRequest!.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      final request =
          calls.where((c) => c.method == 'requestPermissions').single.arguments
              as Map;
      expect(request['alert'], isTrue);
      expect(request['sound'], isTrue);
      expect(request['badge'], isTrue);
      expect(request['critical'], isFalse);
    },
  );

  test(
    'denied permission prevents even the generic test from being shown',
    () async {
      expect(
        await notifications.permission(),
        IosNotificationPermission.denied,
      );
      expect(await notifications.showTest(), isFalse);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
    },
  );

  test(
    'local test is generic and has no chat, reply or APNs operation',
    () async {
      allowed = true;
      expect(await notifications.showTest(), isTrue);
      final show =
          calls.where((c) => c.method == 'show').single.arguments as Map;
      expect(show['title'], 'ChatLoom');
      expect(show['body'], contains('Background push is not enabled'));
      // The native plugin normalizes an omitted payload to an empty string.
      // Both forms are intentionally unroutable and carry no chat identity.
      expect(show['payload'], anyOf(isNull, equals('')));
      expect(show.toString(), isNot(contains('example.invalid')));
      expect(calls.map((c) => c.method), [
        'initialize',
        'getNotificationAppLaunchDetails',
        'checkPermissions',
        'show',
      ]);
    },
  );

  test(
    'cold response waits for router and warm duplicate is handled once',
    () async {
      launch = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 19,
          'notificationResponseType': 0,
          'payload': 'fictional-payload',
        },
      };
      await notifications.initialize();
      final opened = <NotificationResponse>[];
      await notifications.initialize(onResponse: opened.add);
      notifications.handleResponse(
        const NotificationResponse(
          id: 19,
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'fictional-payload',
        ),
      );
      expect(opened, hasLength(1));
      notifications.handleResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      );
      expect(opened, hasLength(1), reason: 'local test has no chat to route');
    },
  );

  test('permission refresh follows changes made in iPhone Settings', () async {
    expect(await notifications.permission(), IosNotificationPermission.denied);
    allowed = true;
    expect(await notifications.permission(), IosNotificationPermission.allowed);
    expect(await notifications.openSettings(), isTrue);
    expect(calls.last.method, 'openAppNotificationSettings');
  });

  Future<bool> message({
    String event = 'fictional-event',
    int time = 10,
    bool sound = true,
    bool Function()? current,
  }) => notifications.showMessage(
    id: 77,
    threadIdentifier: 'fictional-client_person:fictional-person',
    eventIdentity: event,
    timestamp: DateTime.fromMillisecondsSinceEpoch(time),
    title: 'ChatLoom',
    body: 'New message',
    payload: 'fictional-payload:$event',
    playSound: sound,
    canPresent: current ?? () => true,
  );

  test(
    'concurrent duplicate alerts show once and do not request permission',
    () async {
      final results = await Future.wait([message(), message()]);
      expect(results.where((r) => r), hasLength(1));
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
    },
  );
  test(
    'backfill cannot replace the newest conversation alert; sound is optional',
    () async {
      await message();
      expect(await message(event: 'older', time: 9), isFalse);
      expect(await message(event: 'newer', time: 11, sound: false), isTrue);
      final shown = calls.where((c) => c.method == 'show').toList();
      expect(shown, hasLength(2));
      final args = shown.last.arguments as Map;
      expect(args['payload'], 'fictional-payload:newer');
      final details = args['platformSpecifics'] as Map;
      expect(
        details['threadIdentifier'],
        'fictional-client_person:fictional-person',
      );
      expect(details['presentSound'], isFalse);
      expect(details['presentBanner'], isTrue);
    },
  );
  test(
    'an account or privacy change during initialization prevents presentation',
    () async {
      initialization = Completer<bool>();
      var current = true;
      final requested = message(current: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      initialization!.complete(true);
      expect(await requested, isFalse);
      expect(calls.where((c) => c.method == 'show'), isEmpty);
    },
  );
  test('a failed local presentation can be retried', () async {
    failShow = true;
    await expectLater(message(), throwsA(isA<PlatformException>()));
    failShow = false;
    expect(await message(), isTrue);
  });

  testWidgets(
    'iPhone settings stays readable at large text and does not prompt on entry',
    (tester) async {
      try {
        SharedPreferences.setMockInitialValues({});
        await AppSettings.init();
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: NotionTheme.build(Brightness.dark),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
              ),
              child: const IosNotificationsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Enable notifications'), findsOneWidget);
        expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
        await tester.scrollUntilVisible(
          find.text('Background push is not connected'),
          240,
        );
        expect(tester.takeException(), isNull);
        expect(calls.where((c) => c.method == 'show'), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        // Widget binding checks foundation globals before ordinary tearDown.
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
