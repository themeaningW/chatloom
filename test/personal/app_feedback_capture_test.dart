// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/app_feedback_capture.dart';
import 'package:chatloom/personal/ui/app_feedback_sheet.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:chatloom/widgets/app_lock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app_feedback_test.dart' show environment;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

void main() {
  late BuildContext page;
  late AppLockController lock;
  var captures = 0;
  setUp(() {
    captures = 0;
    lock = AppLockController(pincode: '1234')..unlock('1234');
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    lock.dispose();
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });

  Future<void> mount(
    WidgetTester tester, {
    Future<Uint8List?> Function(RenderRepaintBoundary, double)? capture,
    bool realCapture = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        builder: (context, child) => AppLockWidget(
          controller: lock,
          isLoggedIn: true,
          child: AppFeedbackCaptureScope(
            captureImage: realCapture
                ? null
                : capture ??
                      (_, _) async {
                        captures++;
                        expectSync(find.byType(AppFeedbackSheet), findsNothing);
                        return _png;
                      },
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return const ColoredBox(
                color: Color(0xff123456),
                child: SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountSheet(
    WidgetTester tester,
    Future<void> Function(String, Uint8List?, Rect) share,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        builder: (context, child) =>
            AppLockWidget(controller: lock, isLoggedIn: true, child: child!),
        home: Scaffold(
          body: AppFeedbackSheet(
            environment: Future.value(environment),
            screenshot: _png,
            share: share,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'captures before the sheet and serializes repeated report entry',
    (tester) async {
      await mount(tester);
      unawaited(showAppFeedback(page));
      unawaited(showAppFeedback(page));
      await tester.pumpAndSettle();
      expect(captures, 1);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      expect(
        tester
            .widget<AppFeedbackSheet>(find.byType(AppFeedbackSheet))
            .screenshot,
        _png,
      );
      expect(find.byTooltip('Remove screenshot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real capture returns bounded PNG pixels of the prior screen', (
    tester,
  ) async {
    await mount(tester, realCapture: true);
    final bytes = await tester.runAsync(() async {
      final capture = AppFeedbackCaptureScope.capture(page);
      await tester.pump();
      return await capture;
    });
    expect(bytes, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes!);
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, lessThanOrEqualTo(2048));
        expect(frame.image.height, lessThanOrEqualTo(2048));
        final pixels = await frame.image.toByteData();
        final center =
            ((frame.image.height ~/ 2) * frame.image.width +
                frame.image.width ~/ 2) *
            4;
        expect(pixels!.buffer.asUint8List(center, 4), [0x12, 0x34, 0x56, 0xff]);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('capture failure leaves a usable text report', (tester) async {
    await mount(
      tester,
      capture: (_, _) async => throw StateError('fixture failure'),
    );
    unawaited(showAppFeedback(page));
    await tester.pumpAndSettle();
    expect(find.text('Screenshot unavailable'), findsOneWidget);
    expect(find.text('Share report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lock and unlock during encoding discard the image and route', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    await mount(tester, capture: (_, _) => pending.future);
    unawaited(showAppFeedback(page));
    await tester.pump();
    lock.showLockScreen();
    lock.unlock('1234');
    pending.complete(_png);
    await tester.pumpAndSettle();
    expect(find.byType(AppFeedbackSheet), findsNothing);
    expect(appFeedbackOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background and resume cannot replay a pending screenshot', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    await mount(tester, capture: (_, _) => pending.future);
    unawaited(showAppFeedback(page));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(_png);
    await tester.pumpAndSettle();
    expect(find.byType(AppFeedbackSheet), findsNothing);
    expect(appFeedbackOpen, isFalse);
  });

  testWidgets('timeout falls back once and ignores a later screenshot', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    await mount(tester, capture: (_, _) => pending.future);
    unawaited(showAppFeedback(page));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Screenshot unavailable'), findsOneWidget);
    pending.complete(_png);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove screenshot'), findsNothing);
    expect(find.byType(AppFeedbackSheet), findsOneWidget);
  });

  testWidgets('unmount during capture releases the report guard', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    await mount(tester, capture: (_, _) => pending.future);
    unawaited(showAppFeedback(page));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_png);
    await tester.pumpAndSettle();
    expect(appFeedbackOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'share explicitly includes description and image; removal persists',
    (tester) async {
      final exports = <(String, Uint8List?, Rect)>[];
      await mountSheet(
        tester,
        (text, bytes, origin) async => exports.add((text, bytes, origin)),
      );
      expect(exports, isEmpty);
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();
      expect(exports, isEmpty);
      expect(find.text('Describe the problem first.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Fictional layout issue');
      await tester.ensureVisible(find.text('Share report'));
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();
      expect(exports.single.$1, contains('Fictional layout issue'));
      expect(exports.single.$1, contains('Screenshot: attached'));
      expect(exports.single.$2, _png);
      expect(exports.single.$3.isEmpty, isFalse);
      await tester.tap(find.byTooltip('Remove screenshot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();
      expect(exports.last.$2, isNull);
      expect(exports.last.$1, contains('Screenshot: not attached'));
      expect(find.text('Fictional layout issue'), findsOneWidget);
    },
  );

  testWidgets('locking an open report clears its screenshot', (tester) async {
    final exports = <Uint8List?>[];
    await mountSheet(tester, (_, bytes, _) async => exports.add(bytes));
    await tester.enterText(find.byType(TextField), 'Fictional issue');
    lock.showLockScreen();
    await tester.pump();
    lock.unlock('1234');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove screenshot'), findsNothing);
    await tester.ensureVisible(find.text('Share report'));
    await tester.tap(find.text('Share report'));
    await tester.pumpAndSettle();
    expect(exports, [null]);
  });
}
