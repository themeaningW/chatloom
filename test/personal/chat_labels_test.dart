// SPDX-License-Identifier: AGPL-3.0-or-later
// Offline labels and production UI. Fictional chats; only private replica writes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/personal/chat_labels.dart';
import 'package:chatloom/personal/inbox_projection.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/chat_label_sheets.dart';
import 'package:chatloom/personal/ui/notion_inbox_view_chips.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:personal_core/personal_core.dart';

import '../notion/conversation_test_support.dart';

class _Client extends ConversationClient {
  String current = '@owner:example.invalid';
  @override
  String get userID => current;
}

class _Personal extends PersonalClient {
  _Personal(super.client)
    : super.forTesting(openStore: () => throw StateError('No real storage'));
  bool available = true;
  final writes = <String>[];
  @override
  bool get ready => available;
  @override
  Future<void> load() async {}
  @override
  Future<void> put(String key, Map<String, dynamic> value) async {
    writes.add(key);
    values[key] = Map.of(value);
    notifyListeners();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['CHATLOOM_LABEL_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture-labels')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late _Client client;
  late _Personal personal;
  late Room room;
  late ChatLabels labels;
  setUpAll(() async {
    if (Platform.environment['CHATLOOM_LABEL_CAPTURE_DIR'] == null) return;
    final text = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      text.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await text.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    client = _Client();
    personal = _Personal(client);
    room = ConversationRoom(client, '!study:example.invalid');
    labels = ChatLabels(personal);
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });
  tearDown(() {
    personal.dispose();
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });

  test(
    'create and edit keep stable label identity, custom icon/color and unknown fields',
    () async {
      final id = await labels.create(
        '  Studia  ',
        icon: 'school',
        color: 0xff123456,
      );
      expect(labels.all.single.name, 'Studia');
      expect(labels.all.single.icon, 'school');
      expect(labels.all.single.color, 0xff123456);
      personal.values[id]!['future-field'] = 'kept';
      await labels.update(id, 'Moje studia', icon: 'book', color: 0xffabcdef);
      expect(labels.all.single.id, id);
      expect(labels.all.single.icon, 'book');
      expect(labels.all.single.color, 0xffabcdef);
      expect(personal.values[id]!['future-field'], 'kept');
      expect(personal.writes.every((k) => k.startsWith('label:')), isTrue);
    },
  );
  test(
    'a chat has multiple labels without changing its draft, mute, pin or archive',
    () async {
      final a = await labels.create('Studia'), b = await labels.create('Praca');
      personal.values['org:${room.id}'] = {
        'entityId': room.id,
        'archived': true,
        'pinOrder': 2,
        'muted': true,
        'future-field': 9,
      };
      personal.values['draft:${room.id}'] = {'text': 'Keep my draft'};
      final before = Map.of(personal.values['org:${room.id}']!);
      await labels.assign(room, entity: room.id, added: {a, b}, removed: {});
      expect(labels.selected(room), {a, b});
      expect(personal.values['org:${room.id}'], before);
      expect(personal.values['draft:${room.id}']?['text'], 'Keep my draft');
      expect(
        InboxProjection(
          personal,
        ).rooms(client.rooms, filter: InboxFilter.label, labelKey: a),
        [room],
      );
    },
  );
  test(
    'removing one label preserves another device change and all other labels',
    () async {
      final a = await labels.create('A'),
          b = await labels.create('B'),
          c = await labels.create('C');
      await labels.assign(room, entity: room.id, added: {a, c}, removed: {});
      await labels.assign(room, entity: room.id, added: {b}, removed: {a});
      expect(labels.selected(room), {b, c});
    },
  );
  test('old hidden labels select a space but never hide the normal inbox', () {
    personal.values['label:legacy'] = {'name': 'Legacy', 'showInInbox': false};
    personal.values['org:${room.id}'] = {
      'entityId': room.id,
      'labelIds': ['label:legacy'],
    };
    expect(InboxProjection(personal).rooms(client.rooms), [room]);
    expect(
      InboxProjection(personal).rooms(
        client.rooms,
        filter: InboxFilter.label,
        labelKey: 'label:legacy',
      ),
      [room],
    );
  });
  test(
    'a label includes groups and Aside, excluding ignored and technical rooms',
    () {
      InboxRecord record(
        String id, {
        ChatPlacement place = ChatPlacement.inbox,
        bool technical = false,
      }) => InboxRecord(
        representativeRoomId: id,
        entityId: id,
        displayName: id,
        labelKeys: {'study'},
        metadata: ConversationMetadata(entityId: id),
        placement: place,
        technical: technical,
      );
      final rows = projectInbox(
        [
          record('dm'),
          record('group', place: ChatPlacement.groups),
          record('aside', place: ChatPlacement.aside),
          record('ignored', place: ChatPlacement.ignored),
          record('technical', technical: true),
        ],
        filter: InboxFilter.label,
        labelKey: 'study',
      );
      expect(rows.map((r) => r.entityId).toSet(), {'dm', 'group', 'aside'});
    },
  );
  test(
    'merged chats inherit source labels once; clearing is an explicit person override',
    () async {
      final other = ConversationRoom(
        client,
        '!work:example.invalid',
        network: 'messenger',
      );
      final a = await labels.create('Studia'), b = await labels.create('Praca');
      personal.values['org:${room.id}'] = {
        'entityId': room.id,
        'labelIds': [a],
      };
      personal.values['labels:${other.id}'] = {
        'labels': [b],
      };
      final group = PersonGroup(
        id: 'p',
        name: 'Fictional person',
        members: [personal.ref(room), personal.ref(other)],
        defaultRoomId: room.id,
      );
      personal.values['person:p'] = group.toJson().cast<String, dynamic>();
      final projection = InboxProjection(personal);
      expect(projection.entityFor(room), 'person:p');
      expect(labels.selected(room), {a, b});
      expect(
        projection.rooms(client.rooms, filter: InboxFilter.label, labelKey: b),
        [room],
      );
      await labels.assign(room, entity: 'person:p', added: {}, removed: {a, b});
      expect(labels.selected(other), isEmpty);
      expect(personal.values['labels:${other.id}']?['labels'], [b]);
      personal.values.remove('person:p');
      expect(labels.selected(other), {b});
    },
  );
  test(
    'deleting a definition removes its view without touching chat memberships or messages',
    () async {
      final id = await labels.create('Studia');
      await labels.assign(room, entity: room.id, added: {id}, removed: {});
      personal.writes.clear();
      await labels.remove(id);
      expect(labels.all, isEmpty);
      expect(labels.selected(room), isEmpty);
      expect(InboxProjection(personal).rooms(client.rooms), [room]);
      expect(
        InboxProjection(
          personal,
        ).rooms(client.rooms, filter: InboxFilter.label, labelKey: id),
        isEmpty,
      );
      expect(personal.writes, [id]);
    },
  );
  test(
    'invalid/duplicate names and unavailable private sync cannot write',
    () async {
      await labels.create('Studia');
      await expectLater(labels.create(' studia '), throwsFormatException);
      await expectLater(labels.create('  '), throwsFormatException);
      final count = personal.writes.length;
      personal.available = false;
      await expectLater(labels.create('Praca'), throwsStateError);
      expect(personal.writes, hasLength(count));
    },
  );

  Widget host({
    bool picker = false,
    bool management = false,
    PersonalLabel? edit,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) => RepaintBoundary(
    key: const ValueKey('capture-labels'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NotionTheme.build(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => NotionButton(
            label: 'Open',
            onPressed: () => management
                ? showChatLabels(context, personal)
                : picker
                ? showChatLabelPicker(context, personal, room)
                : showNotionSheet<String>(
                    context: context,
                    title: 'Edit label',
                    builder: (_) =>
                        ChatLabelEditor(personal: personal, label: edit),
                  ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'editor saves chosen name, icon and color through existing label fields',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('label-name')),
        'Moje studia',
      );
      await tester.ensureVisible(find.byTooltip('Icon school'));
      await tester.tap(find.byTooltip('Icon school'));
      await tester.ensureVisible(
        find.byKey(const ValueKey('label-color:180.0')),
      );
      await tester.tap(find.byKey(const ValueKey('label-color:180.0')));
      await tester.pump();
      await _capture(tester, 'label-editor');
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(labels.all.single.name, 'Moje studia');
      expect(labels.all.single.icon, 'school');
      expect(
        labels.all.single.color,
        HSVColor.fromAHSV(1, 180, .7, .85).toColor().toARGB32(),
      );
    },
  );
  testWidgets(
    'picker applies several labels without overwriting another device membership',
    (tester) async {
      final a = await labels.create('A'),
          b = await labels.create('B'),
          c = await labels.create('C');
      await labels.assign(room, entity: room.id, added: {a}, removed: {});
      await tester.pumpWidget(host(picker: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pump();
      personal.values['labels:${room.id}'] = {
        'labels': [a, c],
      };
      personal.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(labels.selected(room), {a, b, c});
    },
  );
  testWidgets('a stale editor cannot write after locking and unlocking', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('label-name')), 'Private');
    PersonalPrivacy.surfaceUnlocked = false;
    PersonalPrivacy.surfaceUnlocked = true;
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(personal.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('an editor cannot write after switching accounts', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('label-name')), 'Private');
    client.current = '@another:example.invalid';
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(personal.writes, isEmpty);
  });
  testWidgets(
    'management creates, edits and deletes a label without deleting a chat',
    (tester) async {
      await tester.pumpWidget(host(management: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New label'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('label-name')),
        'Moje studia',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final id = labels.all.single.id;
      await labels.assign(room, entity: room.id, added: {id}, removed: {});
      await tester.tap(find.byTooltip('Edit Moje studia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('label-name')), 'Praca');
      await tester.tap(find.byTooltip('Icon work'));
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(labels.all.single.name, 'Praca');
      expect(labels.all.single.icon, 'work');
      expect(labels.selected(room), {id});
      await tester.tap(find.byTooltip('Edit Praca'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(labels.all, isEmpty);
      expect(find.text('Praca'), findsNothing);
      expect(InboxProjection(personal).rooms(client.rooms), [room]);
    },
  );
  testWidgets(
    'large-text phone editor scrolls every choice and save into reach',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(scale: 2));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('label-name')),
        'Moje studia',
      );
      await tester.ensureVisible(find.byTooltip('Icon pets'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Icon pets'));
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(labels.all.single.icon, 'pets');
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'phone editor layout, custom color and keyboard in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(host(brightness: brightness));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('label-name')),
          'Moje studia',
        );
        await tester.tap(find.byTooltip('Icon school'));
        await tester.pumpAndSettle();
        await _capture(tester, 'label-editor-${brightness.name}');
        await tester.ensureVisible(find.text('Custom color'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom color'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(Slider).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Slider).first);
        await tester.pumpAndSettle();
        final chosen = tester.widget<Slider>(find.byType(Slider).first).value;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(labels.all.single.icon, 'school');
        expect(
          HSVColor.fromColor(Color(labels.all.single.color!)).hue,
          closeTo(chosen, 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'labels and management remain reachable on a narrow large-text inbox',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = await labels.create(
        'Studia',
        icon: 'school',
        color: 0xff2060dd,
      );
      await labels.create('Praca', icon: 'work', color: 0xff20ad60);
      String? selected;
      var managed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: NotionInboxViewChips(
                selected: InboxFilter.label,
                selectedLabel: a,
                labels: labels.all,
                onViewSelected: (_) {},
                onLabelSelected: (id) => selected = id,
                onManageLabels: () => managed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('notion_label_chip:$a')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Labels'));
      expect(managed, 1);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('notion_label_chip:$a')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(ValueKey('notion_label_chip:$a')));
      expect(selected, a);
      expect(tester.takeException(), isNull);
    },
  );
}
