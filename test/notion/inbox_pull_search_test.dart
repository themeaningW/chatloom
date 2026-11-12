// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/notion_inbox_page.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('search stays hidden until pulling the top on $platform', (
      tester,
    ) async {
      final scroll = ScrollController();
      var searches = 0;
      InboxSort? sort;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(
            Brightness.dark,
          ).copyWith(platform: platform),
          home: NotionInboxPage(
            scrollController: scroll,
            pins: const [],
            networks: const ['whatsapp', 'messenger'],
            onSettings: () {},
            onSearch: () => searches++,
            onNetworkSelected: (_) {},
            onSortSelected: (value) => sort = value,
            rows: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 72, child: Text('Fictional conversation $i')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('notion_dock_search'));
      final fab = find.byKey(const ValueKey('inbox_search_fab'));
      expect(scroll.offset, 0);
      expect(search.hitTestable(), findsNothing);
      expect(find.text('All networks').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Sort chats').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Sort chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest activity'));
      await tester.pumpAndSettle();
      expect(sort, InboxSort.oldestActivity);

      scroll.jumpTo(400);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsNothing);
      final position = scroll.offset;
      await tester.tap(fab);
      expect(searches, 1);
      expect(scroll.offset, position);
      final fabRect = tester.getRect(fab);
      expect(fabRect.center.dx, greaterThan(300));
      expect(fabRect.bottom, lessThanOrEqualTo(844));

      scroll.jumpTo(0);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(0));
      expect(search.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(search).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Chats')).dy),
      );
      await tester.tap(search);
      expect(searches, 2);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(search.hitTestable(), findsNothing);

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = tester.getRect(find.text('Fictional conversation 29'));
      expect(last.bottom, lessThan(tester.getRect(fab).top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    });
  }
}
