// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/config/routes.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const detail = ValueKey('ios-detail');

Future<GoRouter> mount(WidgetTester tester, {bool blocked = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => AppRoutes.defaultPageBuilder(
          context,
          state,
          Scaffold(
            body: TextButton(
              onPressed: () => context.push('/detail'),
              child: const Text('Open detail'),
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'detail',
            pageBuilder: (context, state) => AppRoutes.defaultPageBuilder(
              context,
              state,
              PopScope(
                canPop: !blocked,
                child: const Scaffold(
                  key: detail,
                  body: Center(child: TextField()),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: NotionTheme.build(
        Brightness.dark,
      ).copyWith(platform: TargetPlatform.iOS),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open detail'));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'iOS edge-back follows the finger, cancels without losing input, then completes',
    (tester) async {
      final router = await mount(tester);
      await tester.enterText(find.byType(TextField), 'Unsent draft');
      final editor = tester.state(find.byType(EditableText));
      var drag = await tester.startGesture(const Offset(2, 400));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.moveBy(const Offset(110, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(detail)).dx, greaterThan(40));
      await drag.moveBy(const Offset(-130, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.up();
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Unsent draft',
      );
      expect(tester.getTopLeft(find.byKey(detail)).dx, closeTo(0, .1));
      drag = await tester.startGesture(const Offset(2, 400));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.moveBy(const Offset(330, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      expect(find.byKey(detail), findsNothing);
      expect(find.text('Open detail'), findsOneWidget);
    },
  );
  testWidgets('a PopScope veto keeps the protected page in place', (
    tester,
  ) async {
    await mount(tester, blocked: true);
    await tester.dragFrom(const Offset(2, 400), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(detail), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(detail)).dx, closeTo(0, .1));
  });
  testWidgets(
    'Reduce Motion removes translations on imperative iOS routes and keeps input state',
    (tester) async {
      final reduced = ValueNotifier(true);
      addTearDown(reduced.dispose);
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(
            Brightness.dark,
          ).copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: reduced,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold(body: Text('Base'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(root).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(key: detail, body: TextField()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(find.byKey(detail)).dx, closeTo(0, .1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      final editor = tester.state(find.byType(EditableText));
      reduced.value = false;
      await tester.pumpAndSettle();
      reduced.value = true;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Keep this draft',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
