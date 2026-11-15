// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'momentum completes a deliberate flick, reversal cancels, twitch does nothing',
    () {
      expect(
        NotionSwipePhysics.commits(distance: 50, velocity: 900, threshold: 100),
        isTrue,
      );
      expect(
        NotionSwipePhysics.commits(
          distance: 110,
          velocity: -900,
          threshold: 100,
        ),
        isFalse,
      );
      expect(
        NotionSwipePhysics.commits(
          distance: 10,
          velocity: 4000,
          threshold: 100,
        ),
        isFalse,
      );
      expect(
        NotionSwipePhysics.commits(
          distance: -50,
          velocity: -900,
          threshold: 100,
        ),
        isTrue,
      );
      expect(
        NotionSwipePhysics.commits(distance: 50, velocity: 0, threshold: 100),
        isFalse,
      );
    },
  );

  test(
    'soft boundary keeps moving and regrab preserves its presentation position',
    () {
      expect(NotionSwipePhysics.resist(90, 100, 300), 90);
      final first = NotionSwipePhysics.resist(400, 100, 300);
      final next = NotionSwipePhysics.resist(500, 100, 300);
      expect(next, greaterThan(first));
      expect(next - first, lessThan(100));
      expect(NotionSwipePhysics.unresist(first, 100, 300), closeTo(400, .001));
    },
  );

  testWidgets('a moving dismiss can be caught before it commits', (
    tester,
  ) async {
    var commits = 0;
    const row = ValueKey('swipe-row');
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: NotionSwipeAction(
                endToStart: NotionSwipeActionSide(
                  icon: Icons.archive_outlined,
                  label: 'Aside',
                  dismisses: true,
                  onCommit: () => commits++,
                ),
                child: const SizedBox(
                  key: row,
                  height: 80,
                  child: Text('Fictional chat'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.byKey(row));
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(-120, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(commits, 0);
    final catchDrag = await tester.startGesture(
      tester.getCenter(find.byKey(row)),
    );
    await catchDrag.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await catchDrag.up();
    await tester.pumpAndSettle();
    expect(commits, 0);
    expect(tester.getCenter(find.byKey(row)).dx, closeTo(start.dx, .5));
    expect(tester.takeException(), isNull);
  });
}
