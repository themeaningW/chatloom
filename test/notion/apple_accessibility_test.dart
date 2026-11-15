// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('native animation and transparency choices are independent', (
    tester,
  ) async {
    late bool uiReduced, mediaReduced, manualReduced, glass;
    Future<void> mount(
      NotionAccessibilitySettings settings, {
      bool active = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: TickerMode(
          enabled: active,
          child: NotionAccessibilityScope(
            settings: settings,
            child: NotionGlassScope(
              mode: NotionGlassMode.on,
              child: Builder(
                builder: (context) {
                  uiReduced = NotionMotion.reduced(context);
                  mediaReduced = NotionMotion.mediaReduced(context);
                  manualReduced = NotionMotion.mediaReduced(
                    context,
                    manual: true,
                  );
                  glass = notionGlassEnabled(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await mount(
      const NotionAccessibilitySettings(
        reduceMotion: true,
        animatedImages: true,
      ),
    );
    expect(uiReduced, isTrue);
    expect(mediaReduced, isFalse);
    expect(glass, isTrue);
    await mount(
      const NotionAccessibilitySettings(
        reduceTransparency: true,
        animatedImages: false,
      ),
    );
    expect(uiReduced, isFalse);
    expect(mediaReduced, isTrue);
    expect(manualReduced, isFalse);
    expect(glass, isFalse);
  });

  testWidgets('bare and resolved token styles inherit the Apple system face', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('Direct token', style: NotionType.caption),
                Text(
                  'Resolved token',
                  style: context.notion.typography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final label in ['Direct token', 'Resolved token']) {
      final rich = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(rich.text.style?.fontFamily, NotionType.platformFamily);
    }
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
