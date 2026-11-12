// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/notion_inbox_dock.dart';
import 'package:chatloom/personal/ui/notion_inbox_page.dart';
import 'package:chatloom/personal/ui/notion_inbox_pins.dart';
import 'package:chatloom/personal/ui/notion_inbox_row.dart';
import 'package:chatloom/personal/ui/notion_inbox_view_chips.dart';
import 'package:chatloom/personal/ui/notion_search_controls.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    ),
    child: content!,
  ),
  home: Scaffold(body: child),
);

Widget avatar() => const ColoredBox(color: Color(0xFF555555));
void main() {
  testWidgets(
    'large text scales row content while decorative avatar initials stay bounded',
    (tester) async {
      var avatarScale = 0.0;
      await tester.pumpWidget(
        host(
          NotionInboxRow(
            avatar: Builder(
              builder: (context) {
                avatarScale = MediaQuery.textScalerOf(context).scale(1);
                return const NotionInitialAvatar(name: 'Ada');
              },
            ),
            name: 'Ada',
            preview: 'Readable message',
            unreadCount: 3,
            onTap: () {},
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(avatarScale, 1);
      for (final content in ['Ada', 'Readable message', '3']) {
        expect(
          MediaQuery.textScalerOf(tester.element(find.text(content))).scale(1),
          2,
          reason: 'Only decorative avatar lettering opts out of Dynamic Type',
        );
      }
      final initial = tester.getRect(find.text('A'));
      final circle = tester.getRect(find.byType(NotionInitialAvatar));
      expect(initial.width, lessThanOrEqualTo(circle.width));
      expect(initial.height, lessThanOrEqualTo(circle.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('sort choices are reachable and notify the selected order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var sort = InboxSort.latestActivity;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => NotionInboxPage(
            rows: const [],
            pins: const [],
            networks: const ['whatsapp'],
            onSettings: () {},
            onSearch: () {},
            onNetworkSelected: (_) {},
            sort: sort,
            onSortSelected: (value) => setState(() => sort = value),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    final target = find.byTooltip('Sort chats');
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oldest activity'));
    await tester.pumpAndSettle();
    expect(sort, InboxSort.oldestActivity);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread first'));
    await tester.pumpAndSettle();
    expect(sort, InboxSort.unreadFirst);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1200, 800),
  ]) {
    testWidgets(
      'inbox toolbar and search stay usable at $size with Dynamic Type',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var settings = 0;
        var searches = 0;
        final scroll = ScrollController();
        await tester.pumpWidget(
          host(
            NotionInboxPage(
              scrollController: scroll,
              pins: const [],
              networks: const ['whatsapp', 'instagram'],
              onSettings: () => settings++,
              onSearch: () => searches++,
              onNetworkSelected: (_) {},
              rows: [
                for (var i = 0; i < 20; i++)
                  NotionInboxRow(
                    avatar: avatar(),
                    name: 'Conversation $i',
                    preview: 'A readable fictional message preview',
                    time: '16:45',
                    onTap: () {},
                  ),
              ],
            ),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(NotionInboxDock), findsNothing);
        await tester.tap(find.byKey(const ValueKey('inbox_search_fab')));
        expect(searches, 1);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.tap(find.byTooltip('New message'));
        expect(settings, 1);
        expect(searches, 2);
        expect(
          tester.getTopLeft(find.byTooltip('Settings')).dy,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester.getSize(find.byTooltip('New message')).height,
          greaterThanOrEqualTo(44),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
      },
    );
  }

  testWidgets('storage failure hides saved rows and offers a local retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      host(
        NotionInboxPage(
          rows: const [Text('Unclassified saved chat')],
          pins: const [],
          unreadCount: 75,
          emptyMessage: 'Retry loading your chats.',
          onRetryLoading: () => retries++,
          onSettings: () {},
          onSearch: () {},
          onNetworkSelected: (_) {},
          networks: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unclassified saved chat'), findsNothing);
    expect(find.text('75'), findsNothing);
    expect(find.text('Saved chats could not be loaded'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('loading replaces cached rows, pins and unread counters', (
    tester,
  ) async {
    var searches = 0;
    Widget page(bool loading) => NotionInboxPage(
      loading: loading,
      rows: const [Text('Saved chat preview')],
      pins: [
        NotionPinnedShortcut(
          name: 'Saved pin',
          avatar: avatar(),
          onTap: () {},
          order: 0,
        ),
      ],
      unreadCount: 75,
      requestCount: 9,
      onSettings: () {},
      onSearch: () => searches++,
      onNetworkSelected: (_) {},
      networks: const [],
    );
    await tester.pumpWidget(host(page(true)));
    expect(find.byType(NotionSkeleton), findsOneWidget);
    expect(find.text('Saved chat preview'), findsNothing);
    expect(find.text('Saved pin'), findsNothing);
    expect(find.text('75'), findsNothing);
    expect(find.text('Requests'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inbox_search_fab')));
    expect(searches, 0);
    await tester.pumpWidget(host(page(false)));
    await tester.pumpAndSettle();
    expect(find.byType(NotionSkeleton), findsNothing);
    expect(find.text('Saved chat preview'), findsOneWidget);
    expect(find.text('Saved pin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inbox_search_fab')));
    expect(searches, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Aside is reachable from chips and the dock without changing network',
    (tester) async {
      final views = <InboxFilter>[];
      final networks = <String?>[];
      await tester.pumpWidget(
        host(
          Column(
            children: [
              NotionInboxViewChips(
                selected: InboxFilter.inbox,
                onViewSelected: views.add,
              ),
              const Spacer(),
              NotionInboxDock(
                onSettings: () {},
                onSearch: () {},
                networks: const ['whatsapp', 'telegram'],
                selectedNetwork: 'whatsapp',
                onNetworkSelected: networks.add,
                onViewSelected: views.add,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('notion_inbox_chip_aside')));
      await tester.pumpAndSettle();
      expect(views, [InboxFilter.aside]);
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aside').last);
      await tester.pumpAndSettle();
      expect(views, [InboxFilter.aside, InboxFilter.aside]);
      expect(networks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('unread emphasis clears after reading in $brightness', (
      tester,
    ) async {
      Future<void> row({
        bool unread = false,
        bool selected = false,
        bool muted = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NotionTheme.build(brightness),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 320,
                  child: NotionInboxRow(
                    avatar: avatar(),
                    name: 'Ada',
                    preview: 'Latest message',
                    time: '09:12',
                    unread: unread,
                    selected: selected,
                    muted: muted,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // The resting tint; a selection paints over it (and hides it).
      Color background() {
        final tint =
            (tester
                        .widget<DecoratedBox>(
                          find.byKey(const ValueKey('notion_inbox_row_tint')),
                        )
                        .decoration
                    as BoxDecoration)
                .color!;
        return tint == Colors.transparent
            ? NotionTheme.build(brightness).scaffoldBackgroundColor
            : tint;
      }

      await row();
      final read = background();
      expect(
        tester.widget<Text>(find.text('Ada')).style!.fontWeight,
        FontWeight.w500,
      );
      expect(
        tester.getSize(find.byType(NotionInboxRow)).height,
        greaterThanOrEqualTo(66),
      );
      await row(unread: true);
      expect(background(), isNot(read));
      final title = tester.widget<Text>(find.text('Ada'));
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(
        NotionContrast.ratio(title.style!.color!, background()),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        find.byKey(const ValueKey('notion_inbox_unread_dot')),
        findsOneWidget,
      );
      await row(unread: true, selected: true);
      final selection = background();
      await row(selected: true);
      expect(background(), selection);
      await row(unread: true, muted: true);
      expect(background(), read);
      expect(
        tester.widget<Text>(find.text('Ada')).style!.fontWeight,
        FontWeight.w600,
      );
      await row();
      expect(background(), read);
      expect(
        find.byKey(const ValueKey('notion_inbox_unread_dot')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/notion/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/notion/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/notion/fonts/Roboto-Bold.ttf'));
    await fonts.load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'view and network selection remain independent at text scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var view = InboxFilter.inbox;
        String? network = 'telegram';
        var managed = 0;
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, update) => Align(
                alignment: Alignment.bottomCenter,
                child: NotionInboxDock(
                  onSettings: () {},
                  onSearch: () {},
                  networks: const ['telegram', 'whatsapp'],
                  selectedNetwork: network,
                  selectedView: view,
                  onNetworkSelected: (value) => update(() => network = value),
                  onViewSelected: (value) => update(() => view = value),
                  onManageNetworks: () => managed++,
                ),
              ),
            ),
            scale: scale,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('notion_dock_network')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ignored'));
        await tester.pumpAndSettle();
        expect(view, InboxFilter.ignored);
        expect(network, 'telegram');
        await tester.tap(find.byKey(const ValueKey('notion_dock_network')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('All networks'), 150);
        await tester.tap(find.text('All networks'));
        await tester.pumpAndSettle();
        expect(view, InboxFilter.ignored);
        expect(network, isNull);
        await tester.tap(find.byKey(const ValueKey('notion_dock_network')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Manage networks'), 150);
        await tester.tap(find.text('Manage networks'));
        await tester.pumpAndSettle();
        expect(managed, 1);
        expect(find.text('Show chats'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('search field typing stays local and Clear resets it', (
    tester,
  ) async {
    final text = TextEditingController();
    final focus = FocusNode();
    var local = 0;
    var closed = 0;
    await tester.pumpWidget(
      host(
        NotionSearchField(
          controller: text,
          focusNode: focus,
          onChanged: (_) => local++,
          onClose: () => closed++,
        ),
      ),
    );
    // No clear button until there is something to clear.
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'colleague');
    await tester.pumpAndSettle();
    expect(local, 1);
    // The field offers no network or directory action of its own.
    expect(find.text('Discover publicly'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(text.text, isEmpty);
    expect(local, 2);
    expect(closed, 0);
    await tester.pumpWidget(const SizedBox());
    text.dispose();
    focus.dispose();
  });
  for (final composing in [false, true]) {
    testWidgets('search Escape respects active IME composition: $composing', (
      tester,
    ) async {
      final text = TextEditingController();
      final focus = FocusNode();
      var closed = 0;
      var changed = 0;
      await tester.pumpWidget(
        host(
          NotionSearchField(
            controller: text,
            focusNode: focus,
            onChanged: (_) => changed++,
            onClose: () => closed++,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'fictional query');
      if (composing) {
        text.value = text.value.copyWith(
          composing: const TextRange(start: 0, end: 3),
        );
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, composing ? 0 : 1);
      expect(text.text, 'fictional query');
      expect(changed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      text.dispose();
      focus.dispose();
    });
  }
  testWidgets('outside dismissal consumes the tap and restores network focus', (
    tester,
  ) async {
    var chatsOpened = 0;
    await tester.pumpWidget(
      host(
        Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => chatsOpened++,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 46,
              child: NotionInboxDock(
                onSettings: () {},
                onSearch: () {},
                onNetworkSelected: (_) {},
                networks: const ['whatsapp', 'slack'],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('All networks'));
    await tester.pumpAndSettle();
    expect(find.text('Show chats'), findsOneWidget);
    await tester.tapAt(const Offset(30, 150));
    await tester.pumpAndSettle();
    expect(find.text('Show chats'), findsNothing);
    expect(chatsOpened, 0);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Inbox network filter',
    );
    await tester.tap(find.text('All networks'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Show chats'), findsNothing);
  });
  testWidgets('selection fires once and modal Back dismisses', (tester) async {
    final selected = <String?>[];
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.bottomCenter,
          child: NotionInboxDock(
            onSettings: () {},
            onSearch: () {},
            onNetworkSelected: selected.add,
            networks: const ['slack'],
          ),
        ),
      ),
    );
    await tester.tap(find.text('All networks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slack'));
    await tester.pumpAndSettle();
    expect(selected, ['slack']);
    expect(find.text('Show chats'), findsNothing);
    await tester.tap(find.text('All networks'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Show chats'), findsNothing);
  });
  testWidgets(
    'pins collapse when empty, order persists and chats stay in Messages',
    (tester) async {
      Widget page(List<NotionPinnedShortcut> pins) => NotionInboxPage(
        rows: [
          NotionInboxRow(
            avatar: avatar(),
            name: 'Early',
            preview: 'Loaded preview',
            onTap: () {},
          ),
        ],
        pins: pins,
        onSettings: () {},
        onSearch: () {},
        onNetworkSelected: (_) {},
        networks: const [],
      );
      await tester.pumpWidget(host(page([])));
      expect(find.text('Pinned'), findsNothing);
      await tester.pumpWidget(
        host(
          page([
            NotionPinnedShortcut(
              name: 'Late',
              avatar: avatar(),
              onTap: () {},
              order: 9,
            ),
            NotionPinnedShortcut(
              name: 'Early',
              avatar: avatar(),
              onTap: () {},
              order: 1,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Early'), findsNWidgets(2));
      final early = tester.getTopLeft(find.text('Early').first);
      final late = tester.getTopLeft(find.text('Late'));
      expect(early.dx, lessThan(late.dx));
      // The view chips replaced the second large title (UX-16).
      expect(
        find.byKey(const ValueKey('notion_inbox_chip_inbox')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'large text keeps toolbar actions reachable and the final row unobscured',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      await tester.pumpWidget(
        host(
          NotionInboxPage(
            scrollController: scroll,
            rows: [
              for (var i = 0; i < 12; i++)
                NotionInboxRow(
                  avatar: avatar(),
                  name: 'A very long conversation name $i',
                  preview: 'A long loaded preview from this conversation',
                  time: '16:45',
                  unreadCount: 2,
                  onTap: () {},
                ),
            ],
            pins: const [],
            onSettings: () {},
            onSearch: () {},
            onNetworkSelected: (_) {},
            networks: const ['unknown'],
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final row = tester.getBottomLeft(
        find.ancestor(
          of: find.text('A very long conversation name 11'),
          matching: find.byType(NotionInboxRow),
        ),
      );
      expect(find.byType(NotionInboxDock), findsNothing);
      expect(row.dy, lessThanOrEqualTo(568 - 34));
      expect(
        tester
            .getTopLeft(
              find.ancestor(
                of: find.text('A very long conversation name 11'),
                matching: find.byType(NotionInboxRow),
              ),
            )
            .dy,
        greaterThan(tester.getBottomLeft(find.byTooltip('New message')).dy),
      );
      expect(
        tester.getTopLeft(find.byTooltip('Settings')).dy,
        greaterThanOrEqualTo(0),
      );
      expect(
        tester.getBottomLeft(find.byTooltip('New message')).dy,
        lessThan(568),
      );
      scroll.jumpTo(scroll.position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      final searchText = tester.widget<Text>(find.text('Search'));
      expect(searchText.maxLines, 1);
      expect(searchText.softWrap, false);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Search'))
            .didExceedMaxLines,
        false,
      );
      for (final region in ['settings', 'search', 'network']) {
        final target = tester.getSize(
          find.byKey(ValueKey('notion_dock_$region')),
        );
        expect(target.width, greaterThanOrEqualTo(44));
        expect(target.height, greaterThanOrEqualTo(44));
      }
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  test('large dock label splits only between words', () {
    expect(notionInboxDockLabelLines('All networks'), ['All', 'networks']);
    expect(notionInboxDockLabelLines('Unread · Google Messages'), [
      'Unread',
      'Google Messages',
    ]);
    expect(notionInboxDockLabelLines('Telegram'), ['Telegram']);
  });

  testWidgets('dock network label never wraps mid-word at 200% text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.bottomCenter,
          child: NotionInboxDock(
            onSettings: () {},
            onSearch: () {},
            onNetworkSelected: (_) {},
            networks: const ['telegram'],
          ),
        ),
        scale: 2,
      ),
    );
    final labels = find.descendant(
      of: find.byKey(const ValueKey('notion_dock_network')),
      matching: find.byType(Text),
    );
    expect(labels, findsNWidgets(2));
    for (final text in tester.widgetList<Text>(labels)) {
      expect(text.softWrap, isFalse);
      expect(text.maxLines, 1);
    }
    expect(find.text('All'), findsOneWidget);
    expect(find.text('networks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'row marks unread with a dot and name weight while timestamps stay quiet',
    (tester) async {
      Future<Color?> timeColor({
        int count = 0,
        bool unread = false,
        bool muted = false,
      }) async {
        await tester.pumpWidget(
          host(
            NotionInboxRow(
              avatar: avatar(),
              name: 'Ada',
              preview: 'Preview',
              time: '09:12',
              unreadCount: count,
              unread: unread,
              muted: muted,
              onTap: () {},
            ),
          ),
        );
        return tester.widget<Text>(find.text('09:12')).style?.color;
      }

      final read = await timeColor();
      final manual = await timeColor(unread: true);
      expect(find.byKey(const ValueKey('notion_inbox_unread_dot')), findsOne);
      expect(find.text('•'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('notion_inbox_unread_dot'))),
        const Size.square(10),
      );
      expect(manual, read);
      expect(
        tester.widget<Text>(find.text('Ada')).style!.fontWeight,
        FontWeight.w600,
      );
      final counted = await timeColor(count: 4);
      expect(counted, manual);
      expect(find.text('4'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notion_inbox_unread_dot')),
        findsNothing,
      );
      expect(await timeColor(count: 4, muted: true), read);
    },
  );

  testWidgets('row exposes full unread identity in semantics despite ellipsis', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        NotionInboxRow(
          avatar: avatar(),
          name: 'Long conversation name',
          preview: 'Complete preview',
          time: '16:45',
          unreadCount: 3,
          onTap: () {},
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Long conversation name, Complete preview, 16:45, 3 unread messages',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(
      host(
        NotionInboxRow(
          avatar: avatar(),
          name: 'Private preference',
          preview: 'Loaded preview',
          muted: true,
          notificationLabel: 'Marked muted in private preferences',
          onTap: () {},
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Private preference, Loaded preview, Marked muted in private preferences',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
