// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
  });
  testWidgets('compact pill keeps its full touch target and fires once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: NotionGlassPill(
              compact: true,
              label: 'Unread',
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    final target = find.byType(NotionGlassPill);
    final surface = find.descendant(
      of: target,
      matching: find.byType(NotionGlassSurface),
    );
    expect(tester.getSize(target).height, 48);
    expect(tester.getSize(surface).height, 36);
    final rect = tester.getRect(target);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    expect(taps, 1);
    await tester.tap(target);
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('compact pill visual and large text in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NotionTheme.build(brightness),
          home: RepaintBoundary(
            key: const ValueKey('capture-pills'),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Compact filters'),
                    Row(
                      children: [
                        NotionGlassPill(
                          compact: true,
                          label: 'All',
                          selected: true,
                          onPressed: () {},
                        ),
                        const SizedBox(width: 8),
                        NotionGlassPill(
                          compact: true,
                          label: 'Unread',
                          trailing: const Text('8'),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Large text'),
                    MediaQuery(
                      data: MediaQueryData(textScaler: TextScaler.linear(2)),
                      child: NotionGlassPill(
                        compact: true,
                        label: 'Study',
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture-pills')),
        matchesGoldenFile(
          'goldens/primitives/compact-pills-${brightness.name}.png',
        ),
      );
    });
  }
}
