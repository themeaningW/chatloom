// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/personal/app_feedback.dart';
import 'package:chatloom/personal/ui/app_feedback_sheet.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const environment = AppFeedbackEnvironment(
  version: '2.10.0',
  build: '3574',
  platform: 'iOS',
  systemVersion: '18.0',
  width: 390,
  height: 844,
  textScale: 1.4,
  dark: true,
  reducedMotion: true,
);

void main() {
  setUpAll(() async {
    if (Platform.environment['CHATLOOM_IPHONE_CAPTURE_DIR'] == null) return;
    final text = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      text.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await text.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'a report includes actionable display/build context and no automatic logs',
    () {
      final report = environment.report(
        '  Swipe does not close the keyboard.  ',
      );
      expect(report, contains('Swipe does not close the keyboard.'));
      expect(report, contains('2.10.0 (3574)'));
      expect(report, contains('iOS 18.0'));
      expect(report, contains('390 × 844'));
      expect(report, contains('Text scale: 1.40'));
      expect(report, contains('Reduce Motion: on'));
      expect(report.toLowerCase(), isNot(contains('token')));
      expect(() => environment.report('  '), throwsFormatException);
    },
  );
  testWidgets(
    'phone feedback sheet presents the report and copy button together',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('feedback-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NotionTheme.build(
              Brightness.dark,
            ).copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: Builder(
                builder: (context) => NotionButton(
                  label: 'Open report',
                  onPressed: () => showNotionSheet<void>(
                    context: context,
                    title: 'Report a problem',
                    builder: (_) => AppFeedbackSheet(
                      environment: Future.value(environment),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open report'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Example: a button disappears when I open the keyboard.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy report').hitTestable(), findsOneWidget);
      final directory = Platform.environment['CHATLOOM_IPHONE_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('feedback-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/feedback-sheet-dark.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'copy is explicit, validates description, and works at large text',
    (tester) async {
      final copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
              ),
              child: AppFeedbackSheet(environment: Future.value(environment)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      await tester.ensureVisible(find.text('Copy report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy report'));
      await tester.pumpAndSettle();
      expect(find.text('Describe the problem first.'), findsOneWidget);
      expect(copies, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'Expected to go back. Instead nothing happens.',
      );
      await tester.ensureVisible(find.text('Copy report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy report'));
      await tester.pumpAndSettle();
      expect(copies, hasLength(1));
      expect(copies.single, contains('Expected to go back.'));
      expect(copies.single, contains('3574'));
      expect(tester.takeException(), isNull);
    },
  );
}
