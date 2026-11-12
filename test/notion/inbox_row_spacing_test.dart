// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/notion_inbox_network_badge.dart';
import 'package:chatloom/personal/ui/notion_inbox_row.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
  });

  Widget host({
    required NotionDisplayPreferences display,
    required Widget row,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
  }) {
    final theme = NotionTheme.build(Brightness.dark);
    return MaterialApp(
      theme: theme.copyWith(extensions: [...theme.extensions.values, display]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: Alignment.topCenter, child: row),
        ),
      ),
    );
  }

  for (final width in [320.0, 430.0]) {
    for (final density in [.75, 1.0]) {
      for (final direction in TextDirection.values) {
        testWidgets('row edges $width density=$density $direction', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.reset);
          var contentInset = 0.0;
          await tester.pumpWidget(
            host(
              display: NotionDisplayPreferences(inboxScale: density),
              direction: direction,
              row: Builder(
                builder: (context) {
                  contentInset = NotionInboxRow.contentInsetOf(context);
                  return NotionInboxRow(
                    key: const ValueKey('row'),
                    avatar: const SizedBox.expand(
                      key: ValueKey('avatar'),
                      child: NotionInitialAvatar(name: 'Fictional contact'),
                    ),
                    name: 'Fictional contact',
                    preview: 'A short message',
                    time: '16:36',
                    unreadCount: 213,
                    networks: const ['messenger', 'instagram'],
                    onTap: () {},
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final row = tester.getRect(find.byKey(const ValueKey('row')));
          final avatar = tester.getRect(find.byKey(const ValueKey('avatar')));
          final title = tester.getRect(find.text('Fictional contact'));
          final time = tester.getRect(find.text('16:36'));
          final ltr = direction == TextDirection.ltr;
          expect(ltr ? avatar.left : width - avatar.right, 16);
          expect(avatar.width, NotionSize.avatarLg * density);
          expect(ltr ? width - time.right : time.left, 16);
          expect(
            ltr ? title.left - row.left : row.right - title.right,
            closeTo(contentInset, .01),
          );
          final badge = tester.getRect(find.byType(NotionInboxNetworkBadge));
          expect(
            ltr ? badge.right : width - badge.left,
            lessThan(ltr ? title.left : width - title.right),
          );
          expect(find.text('213'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final showAvatars in [false, true]) {
    for (final direction in TextDirection.values) {
      testWidgets('large row retains status avatars=$showAvatars $direction', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        var taps = 0;
        var holds = 0;
        try {
          await tester.pumpWidget(
            host(
              display: NotionDisplayPreferences(inboxAvatars: showAvatars),
              textScale: 2,
              direction: direction,
              row: NotionInboxRow(
                key: const ValueKey('row'),
                avatar: const NotionInitialAvatar(name: 'Study group'),
                name: 'Study group',
                preview: 'Draft: See you tomorrow',
                time: '16:36',
                draft: true,
                failed: true,
                muted: true,
                unreadCount: 99,
                mentioned: true,
                networks: const ['messenger', 'instagram'],
                onTap: () => taps++,
                onLongPress: () => holds++,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final row = find.byKey(const ValueKey('row'));
          expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
          expect(find.text('Draft: See you tomorrow'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('notion_inbox_failed')),
            findsOneWidget,
          );
          expect(
            tester.getSemantics(row).label,
            allOf(
              contains('Study group'),
              contains('Last message not sent'),
              contains('99 unread messages'),
              contains('You were mentioned'),
            ),
          );
          await tester.tap(find.text('Study group'));
          await tester.longPress(find.text('Study group'));
          expect(taps, 1);
          expect(holds, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
