// SPDX-License-Identifier: AGPL-3.0-or-later
// Production inbox presenters; fictional offline conversations only.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/personal/ui/notion_inbox_page.dart';
import 'package:chatloom/personal/ui/notion_inbox_row.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<ScrollController> mount(
    WidgetTester tester, {
    required Size size,
    double scale = 1,
    EdgeInsets safe = const EdgeInsets.only(top: 59, bottom: 34),
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: NotionTheme.build(
          brightness,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safe,
            viewPadding: safe,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture-inbox-edge'),
          child: NotionInboxPage(
            scrollController: scroll,
            pins: const [],
            networks: const ['messenger', 'instagram', 'whatsapp'],
            onSettings: () {},
            onSearch: () {},
            onNetworkSelected: (_) {},
            onSortSelected: (_) {},
            onViewSelected: (_) {},
            unreadCount: 6,
            rows: [
              for (var i = 0; i < 16; i++)
                NotionInboxRow(
                  key: ValueKey('row-$i'),
                  avatar: NotionInitialAvatar(
                    key: ValueKey('avatar-$i'),
                    name: i == 0 ? 'Study group' : 'Ada',
                  ),
                  name: i == 0 ? 'Fictional university study group' : 'Ada $i',
                  preview: i == 0 ? 'Sam: Sent a photo' : 'See you tomorrow!',
                  time: i == 0 ? '16:36' : '12:45',
                  muted: i == 0,
                  unreadCount: i == 0
                      ? 214
                      : i == 2
                      ? 2
                      : 0,
                  networks: const ['messenger'],
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scroll;
  }

  for (final size in [
    const Size(320, 760),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 430),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('inbox uses screen edges at $size / $scale', (tester) async {
        final landscape = size.width > size.height;
        final safe = landscape
            ? const EdgeInsets.only(left: 44, right: 34, bottom: 21)
            : const EdgeInsets.only(top: 59, bottom: 34);
        await mount(tester, size: size, scale: scale, safe: safe);
        final leading = safe.left + 16;
        final trailing = size.width - safe.right - 16;
        expect(tester.getTopLeft(find.text('Chats')).dx, leading);
        expect(tester.getTopLeft(find.text('All networks')).dx, leading);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('avatar-0'))).dx,
          leading,
        );
        expect(tester.getTopRight(find.text('16:36')).dx, trailing);
        expect(
          tester
              .getTopRight(find.byKey(const ValueKey('inbox_new_message')))
              .dx,
          trailing,
        );
        final name = tester.getRect(
          find.text('Fictional university study group'),
        );
        expect(tester.getRect(find.byType(Divider).first).left, name.left);
        expect(tester.getRect(find.byType(Divider).first).right, trailing);
        expect(
          tester.getRect(find.byType(NotionInboxRow).first).width,
          size.width - safe.horizontal - 24,
        );
        final fab = tester.getRect(
          find.byKey(const ValueKey('inbox_search_fab')),
        );
        expect(fab.size, const Size.square(48));
        expect(fab.right, lessThanOrEqualTo(size.width - safe.right));
        expect(fab.bottom, lessThanOrEqualTo(size.height - safe.bottom));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('revealed search shares the header gutter', (tester) async {
    await mount(tester, size: const Size(430, 932));
    final search = find.byKey(const ValueKey('notion_dock_search'));
    expect(search.hitTestable(), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(search.hitTestable(), findsOneWidget);
    final rect = tester.getRect(search);
    expect(rect.left, 16);
    expect(rect.right, 414);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('edge layout capture in ${brightness.name}', (tester) async {
      await mount(tester, size: const Size(430, 932), brightness: brightness);
      final directory = Platform.environment['CHATLOOM_INBOX_EDGE_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-inbox-edge')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/inbox-edge-${brightness.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
