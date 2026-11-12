// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/personal/ui/notion_inbox_dock.dart';
import 'package:chatloom/personal/ui/notion_inbox_page.dart';
import 'package:chatloom/personal/ui/notion_inbox_row.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

const _trigger = ValueKey('notion_dock_network');
const _panel = ValueKey('notion_network_selector_panel');
const _scroll = ValueKey('notion_network_selector_scroll');
const _capture = ValueKey('network_selector_capture');

void _phone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  EdgeInsets padding = const EdgeInsets.only(top: 59, bottom: 34),
}) {
  // These are physical pixels, including the actual 3x iPhone safe insets.
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.view.padding = FakeViewPadding(
    left: padding.left * 3,
    top: padding.top * 3,
    right: padding.right * 3,
    bottom: padding.bottom * 3,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
}

Widget _app(Widget child, {double scale = 1}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: NotionTheme.build(Brightness.dark),
    builder: (context, content) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: content!,
    ),
    home: child,
  ),
);

/// Optional rendered fixture evidence; ordinary test runs write no artifacts.
Future<void> _capturePopup(WidgetTester tester, String name) async {
  final directory = Platform.environment['CHATLOOM_CONTACT_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

NotionInboxPage _inbox({
  required ValueChanged<String?> onNetworkSelected,
  ValueChanged<InboxFilter>? onViewSelected,
  VoidCallback? onManageNetworks,
  VoidCallback? onMarkAllRead,
  ScrollController? controller,
}) => NotionInboxPage(
  scrollController: controller,
  rows: [
    for (var i = 0; i < 15; i++)
      NotionInboxRow(
        key: ValueKey('chat-$i'),
        avatar: const NotionInitialAvatar(name: 'Ada'),
        name: 'Conversation $i',
        preview: 'A fictional message',
        onTap: () {},
      ),
  ],
  pins: const [],
  networks: const ['telegram', 'whatsapp', 'instagram', 'slack'],
  onSettings: () {},
  onSearch: () {},
  onNetworkSelected: onNetworkSelected,
  onViewSelected: onViewSelected,
  onManageNetworks: onManageNetworks,
  onMarkAllRead: onMarkAllRead,
);

Rect _globalRect(WidgetTester tester, Finder finder) {
  final box = tester.element(finder).findRenderObject()! as RenderBox;
  // getRect combines a global origin with an untransformed size. Both corners
  // must be transformed when checking a navigator inside a scaled pane.
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void _contained(WidgetTester tester, Rect bounds) {
  final panel = _globalRect(tester, find.byKey(_panel));
  expect(panel.left, greaterThanOrEqualTo(bounds.left - .01));
  expect(panel.top, greaterThanOrEqualTo(bounds.top - .01));
  expect(panel.right, lessThanOrEqualTo(bounds.right + .01));
  expect(panel.bottom, lessThanOrEqualTo(bounds.bottom + .01));
}

Finder _menuText(String label) =>
    find.descendant(of: find.byKey(_panel), matching: find.text(label));

Future<void> _reveal(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    _menuText(label),
    100,
    scrollable: find.descendant(
      of: find.byKey(_scroll),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  expect(_menuText(label).hitTestable(), findsOneWidget);
}

void main() {
  setUpAll(() async {
    final directory = Platform.environment['CHATLOOM_CONTACT_CAPTURE_DIR'];
    if (directory == null || directory.isEmpty) return;
    final text = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      text.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await text.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('iPhone 3x header picker opens below and within safe edges', (
    tester,
  ) async {
    _phone(tester);
    final selected = <String?>[];
    await tester.pumpWidget(
      _app(_inbox(onNetworkSelected: selected.add, onViewSelected: (_) {})),
    );
    await tester.pumpAndSettle();
    final anchor = _globalRect(tester, find.byKey(_trigger));
    await tester.tap(find.byKey(_trigger));
    await tester.pumpAndSettle();
    _contained(tester, const Rect.fromLTRB(16, 75, 374, 794));
    final panel = _globalRect(tester, find.byKey(_panel));
    expect(panel.top, greaterThanOrEqualTo(anchor.bottom));
    expect(panel.left, closeTo(anchor.left, .01));
    await _capturePopup(tester, 'network-picker-390-dpr3');
    await _reveal(tester, 'WhatsApp');
    await tester.tap(_menuText('WhatsApp'));
    await tester.pumpAndSettle();
    expect(selected, ['whatsapp']);
    expect(find.byKey(_panel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320pt at 2x text keeps every menu action scrollable and tappable',
    (tester) async {
      _phone(
        tester,
        size: const Size(320, 568),
        padding: const EdgeInsets.only(top: 44, bottom: 34),
      );
      var marked = 0;
      await tester.pumpWidget(
        _app(
          _inbox(
            onNetworkSelected: (_) {},
            onViewSelected: (_) {},
            onManageNetworks: () {},
            onMarkAllRead: () => marked++,
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_trigger));
      await tester.pumpAndSettle();
      const bounds = Rect.fromLTRB(16, 60, 304, 518);
      _contained(tester, bounds);
      await _capturePopup(tester, 'network-picker-320-large-text');
      for (final label in [
        'Main list',
        'Groups',
        'Aside',
        'Ignored',
        'Technical',
        'All networks',
        'Telegram',
        'WhatsApp',
        'Instagram',
        'Slack',
        'Manage networks',
        'Mark all as read',
      ]) {
        await _reveal(tester, label);
        final row = _globalRect(tester, _menuText(label));
        expect(row.top, greaterThanOrEqualTo(bounds.top - .01));
        expect(row.bottom, lessThanOrEqualTo(bounds.bottom + .01));
      }
      await _capturePopup(tester, 'network-picker-320-large-text-scrolled');
      await tester.tap(_menuText('Mark all as read'));
      await tester.pumpAndSettle();
      expect(marked, 1);
      expect(find.byKey(_panel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the legacy bottom dock opens its menu above the trigger', (
    tester,
  ) async {
    _phone(tester);
    final selected = <String?>[];
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: NotionInboxDock(
                onSettings: () {},
                onSearch: () {},
                networks: const ['whatsapp'],
                onNetworkSelected: selected.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final anchor = _globalRect(tester, find.byKey(_trigger));
    await tester.tap(find.byKey(_trigger));
    await tester.pumpAndSettle();
    _contained(tester, const Rect.fromLTRB(16, 75, 374, 794));
    expect(
      _globalRect(tester, find.byKey(_panel)).bottom,
      lessThanOrEqualTo(anchor.top),
    );
    await tester.tap(_menuText('WhatsApp'));
    await tester.pumpAndSettle();
    expect(selected, ['whatsapp']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a partially scrolled header uses its current visible anchor', (
    tester,
  ) async {
    _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_inbox(controller: controller, onNetworkSelected: (_) {})),
    );
    await tester.pumpAndSettle();
    final initial = _globalRect(tester, find.byKey(_trigger));
    controller.jumpTo(40);
    await tester.pumpAndSettle();
    final scrolled = _globalRect(tester, find.byKey(_trigger));
    expect(scrolled.top, lessThan(initial.top));
    expect(find.byKey(_trigger).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(_trigger));
    await tester.pumpAndSettle();
    _contained(tester, const Rect.fromLTRB(16, 75, 374, 794));
    expect(
      _globalRect(tester, find.byKey(_panel)).top,
      closeTo(scrolled.bottom + NotionSpace.xs, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offset scaled root overlay and nested navigator share anchor space',
    (tester) async {
      _phone(tester, size: const Size(720, 900), padding: EdgeInsets.zero);
      final selected = <String?>[];
      const pane = ValueKey('navigator-pane');
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          builder: (context, content) => Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: const Offset(70, 50),
              child: Transform.scale(
                scale: .85,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: pane,
                  width: 390,
                  height: 760,
                  child: content,
                ),
              ),
            ),
          ),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => _inbox(onNetworkSelected: selected.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final anchor = _globalRect(tester, find.byKey(_trigger));
      await tester.tap(find.byKey(_trigger));
      await tester.pumpAndSettle();
      _contained(
        tester,
        _globalRect(tester, find.byKey(pane)).deflate(NotionSpace.md * .85),
      );
      final panel = _globalRect(tester, find.byKey(_panel));
      expect(panel.left, closeTo(anchor.left, .01));
      expect(panel.top, closeTo(anchor.bottom + NotionSpace.xs * .85, .01));
      await _reveal(tester, 'Telegram');
      await tester.tap(_menuText('Telegram'));
      await tester.pumpAndSettle();
      expect(selected, ['telegram']);
      expect(find.byKey(_panel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('landscape side safe areas and keyboard bound the popup', (
    tester,
  ) async {
    _phone(
      tester,
      size: const Size(844, 390),
      padding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 80 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(_app(_inbox(onNetworkSelected: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_trigger));
    await tester.pumpAndSettle();
    _contained(tester, const Rect.fromLTRB(75, 16, 769, 294));
    await _reveal(tester, 'Slack');
    expect(tester.takeException(), isNull);
  });
}
