// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/app_feedback_capture.dart';
import 'package:chatloom/personal/ui/app_feedback_sheet.dart';
import 'package:chatloom/personal/ui/shake_to_report.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:chatloom/utils/ios_shake.dart';
import 'package:chatloom/widgets/app_lock.dart';
import 'package:chatloom/widgets/settings_switch_list_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const events = MethodChannel('chatloom/ios_shake');
const codec = StandardMethodCodec();

void main() {
  late GlobalKey<NavigatorState> navigator;
  late AppLockController lock;
  late TextEditingController draft;
  late BuildContext manualContext;
  final nativeCalls = <MethodCall>[];
  var available = true;
  var missingNative = false;
  var elapsed = Duration.zero;
  Completer<bool>? probe;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    navigator = GlobalKey<NavigatorState>();
    lock = AppLockController(pincode: '1234');
    lock.unlock('1234');
    draft = TextEditingController(text: 'Unsent message');
    nativeCalls.clear();
    available = true;
    missingNative = false;
    elapsed = Duration.zero;
    probe = null;
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IosShake.availability, (call) async {
      if (missingNative) throw MissingPluginException();
      return probe?.future ?? available;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      nativeCalls.add(call);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(IosShake.availability, null)
      ..setMockMethodCallHandler(events, null);
    lock.dispose();
    draft.dispose();
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: NotionTheme.build(Brightness.dark),
        builder: (context, child) => AppLockWidget(
          controller: lock,
          isLoggedIn: true,
          child: AppFeedbackCaptureScope(
            captureImage: (_, _) async => base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
            ),
            child: ShakeToReportScope(
              navigatorKey: navigator,
              elapsed: () => elapsed,
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              manualContext = context;
              return Column(
                children: [
                  TextField(
                    key: const ValueKey('chat-draft'),
                    controller: draft,
                  ),
                  NotionButton(
                    label: 'Manual report',
                    onPressed: () => showAppFeedback(context),
                  ),
                  SettingsSwitchListTile.adaptive(
                    title: 'Shake to report',
                    setting: AppSettings.personalShakeToReport,
                    onChanged: shakeToReportPreferenceChanged,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String getSubscription() =>
      nativeCalls.lastWhere((c) => c.method == 'listen').arguments as String;
  Future<void> settleNative(WidgetTester tester) async {
    // Stream cancellation may finish on the platform messenger's real zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> emit(
    WidgetTester tester, {
    String? subscription,
    Object? payload,
  }) async {
    ServicesBinding.instance.channelBuffers.push(
      events.name,
      codec.encodeSuccessEnvelope(
        payload ??
            {
              'type': 'shake',
              'subscription': subscription ?? getSubscription(),
            },
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeReport(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  }

  void iosTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await body(tester);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  iosTest(
    'shake opens the existing report once, preserves text/selection and applies cooldown',
    (tester) async {
      await mount(tester);
      expect(nativeCalls.where((c) => c.method == 'listen'), hasLength(1));
      await tester.showKeyboard(find.byKey(const ValueKey('chat-draft')));
      draft.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
      final before = draft.value;
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      expect(
        tester
            .widget<AppFeedbackSheet>(find.byType(AppFeedbackSheet))
            .screenshot,
        isNotNull,
      );
      expect(find.text('Report a problem'), findsOneWidget);
      await emit(tester);
      await showAppFeedback(manualContext);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      elapsed = const Duration(seconds: 10);
      await emit(tester);
      await closeReport(tester);
      expect(draft.value.text, before.text);
      expect(draft.selection, before.selection);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      elapsed = const Duration(seconds: 14);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
    },
  );
  iosTest(
    'disabled setting cancels native listener and rejects old packets after re-enable',
    (tester) async {
      await mount(tester);
      final old = getSubscription();
      await tester.tap(find.text('Shake to report'));
      await settleNative(tester);
      expect(AppSettings.personalShakeToReport.value, isFalse);
      expect(nativeCalls.where((c) => c.method == 'cancel'), hasLength(1));
      await emit(tester, subscription: old);
      await tester.tap(find.text('Manual report'));
      await tester.pumpAndSettle();
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
      await tester.tap(find.text('Shake to report'));
      await settleNative(tester);
      expect(getSubscription(), isNot(old));
      await emit(tester, subscription: old);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
    },
  );
  iosTest(
    'background and lock drop events, with no replay after resume or unlock',
    (tester) async {
      await mount(tester);
      var old = getSubscription();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      await emit(tester, subscription: old);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleNative(tester);
      expect(getSubscription(), isNot(old));
      await emit(tester, subscription: old);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      old = getSubscription();
      lock.showLockScreen();
      await tester.pumpAndSettle();
      await emit(tester, subscription: old);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      lock.unlock('1234');
      await settleNative(tester);
      await emit(tester, subscription: old);
      expect(find.byType(AppFeedbackSheet), findsNothing);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
    },
  );
  iosTest('a stale availability probe cannot subscribe after locking', (
    tester,
  ) async {
    probe = Completer<bool>();
    await mount(tester);
    lock.showLockScreen();
    probe!.complete(true);
    await tester.pumpAndSettle();
    expect(nativeCalls.where((c) => c.method == 'listen'), isEmpty);
  });
  iosTest(
    'missing native runner retains manual feedback and unknown packets are ignored',
    (tester) async {
      missingNative = true;
      await mount(tester);
      expect(nativeCalls, isEmpty);
      await tester.tap(find.text('Manual report'));
      await tester.pumpAndSettle();
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
      expect(tester.takeException(), isNull);
    },
  );
  iosTest(
    'only known envelopes open feedback and disposal cancels the channel',
    (tester) async {
      await mount(tester);
      await emit(tester, payload: 'shake');
      await emit(
        tester,
        payload: {'type': 'other', 'subscription': getSubscription()},
      );
      expect(find.byType(AppFeedbackSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(nativeCalls.where((c) => c.method == 'cancel'), hasLength(1));
      await mount(tester);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(appFeedbackOpen, isFalse);
      await mount(tester);
      await emit(tester);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      await closeReport(tester);
    },
  );
  iosTest('other platforms do not subscribe to the iOS motion channel', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await mount(tester);
    expect(nativeCalls, isEmpty);
  });
}
