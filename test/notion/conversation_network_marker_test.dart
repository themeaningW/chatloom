// SPDX-License-Identifier: AGPL-3.0-or-later
// Production merged conversations; fictional offline messages and media.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/l10n/l10n.dart';
import 'package:chatloom/pages/chat/conversation_network_change.dart';
import 'package:chatloom/pages/chat/events/message.dart';
import 'package:chatloom/pages/chat/events/message_content.dart'
    show RedactionWidget;
import 'package:chatloom/pages/chat/events/state_message.dart';
import 'package:chatloom/personal/merged_chat_page.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/ui/notion_network_selector.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:chatloom/widgets/matrix.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart'
    show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:personal_core/personal_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conversation_test_support.dart';

class _Room extends ConversationRoom {
  _Room(super.client, super.id, {required super.network});
  Timeline? timeline;

  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => timeline = ConversationTimeline(
    room: this,
    chunk: TimelineChunk(events: sourceEvents),
    onUpdate: onUpdate,
  );

  void revealOlder(Event event) {
    timeline!.events.add(event);
    timeline!.onUpdate?.call();
  }
}

Event _event(
  _Room room,
  String id,
  String body,
  DateTime time, {
  bool outgoing = false,
  String sender = '@anna:example.invalid',
  String type = EventTypes.Message,
  Map<String, dynamic>? content,
  bool add = true,
}) {
  final event = Event(
    room: room,
    eventId: id,
    senderId: outgoing ? room.client.userID! : sender,
    type: type,
    originServerTs: time,
    content: content ?? {'msgtype': MessageTypes.Text, 'body': body},
  );
  if (add) room.sourceEvents.insert(0, event);
  return event;
}

void main() {
  final start = DateTime.utc(2026, 11, 13, 12);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      AppSettings.showThumbnailsInTimeline.key: false,
    });
    await AppSettings.init(loadWebConfigFile: false);
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  Future<ConversationPersonal> mount(
    WidgetTester tester,
    ConversationClient client,
    List<_Room> rooms, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(430, 1500),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final personal = ConversationPersonal(client);
    PersonalClient.debugUse(client, personal);
    addTearDown(personal.dispose);
    final matrix = ConversationMatrix(
      client,
      await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: matrix,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NotionTheme.build(
            brightness,
          ).copyWith(platform: TargetPlatform.iOS),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: RepaintBoundary(
            key: const ValueKey('capture-network-changes'),
            child: MergedChatPage(
              personal: personal,
              group: PersonGroup(
                id: 'network-marker-person',
                name: 'Fictional person',
                members: [for (final room in rooms) personal.ref(room)],
                defaultRoomId: rooms.first.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return personal;
  }

  List<String> markers(WidgetTester tester) => tester
      .widgetList<ConversationNetworkChange>(
        find.byType(ConversationNetworkChange),
      )
      .map((marker) => marker.network)
      .toList();

  Future<void> unmount(WidgetTester tester) async {
    expect(find.textContaining(RegExp(r'^via ')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same network ignores sender, reply, day, gap and room boundaries',
    (tester) async {
      final client = ConversationClient();
      final a = _Room(client, '!same-a:example.invalid', network: 'whatsapp');
      final b = _Room(client, '!same-b:example.invalid', network: 'whatsapp');
      _event(a, r'$old', 'Older day', start.subtract(const Duration(days: 1)));
      _event(a, r'$new', 'New day', start);
      _event(
        a,
        r'$reply',
        'Reply on the same network',
        start.add(const Duration(minutes: 1)),
        outgoing: true,
        content: {
          'msgtype': MessageTypes.Text,
          'body': 'Reply on the same network',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$new'},
          },
        },
      );
      _event(
        b,
        r'$another-room',
        'Another source room',
        start.add(const Duration(hours: 1)),
      );
      await mount(tester, client, [a, b]);
      expect(find.text('Reply on the same network'), findsOneWidget);
      expect(find.text('Another source room'), findsOneWidget);
      expect(markers(tester), isEmpty);
      await unmount(tester);
    },
  );

  testWidgets('A to B to A emits two centered logos without initial marker', (
    tester,
  ) async {
    final client = ConversationClient();
    final a = _Room(client, '!switch-a:example.invalid', network: 'whatsapp');
    final b = _Room(client, '!switch-b:example.invalid', network: 'messenger');
    _event(a, r'$a1', 'First WhatsApp message', start);
    _event(
      a,
      r'$a2',
      'Second WhatsApp message',
      start.add(const Duration(minutes: 1)),
      outgoing: true,
    );
    _event(
      b,
      r'$b1',
      'First Messenger message',
      start.add(const Duration(minutes: 2)),
    );
    _event(
      b,
      r'$b2',
      'Second Messenger message',
      start.add(const Duration(minutes: 3)),
      outgoing: true,
    );
    _event(
      a,
      r'$a3',
      'Back to WhatsApp',
      start.add(const Duration(minutes: 4)),
    );
    await mount(tester, client, [a, b]);
    expect(markers(tester).toSet(), {'messenger', 'whatsapp'});
    expect(find.byType(ConversationNetworkChange), findsNWidgets(2));
    for (final marker in find.byType(ConversationNetworkChange).evaluate()) {
      final glyph = find.descendant(
        of: find.byWidget(marker.widget),
        matching: find.byType(NotionNetworkGlyph),
      );
      expect(tester.getCenter(glyph).dx, closeTo(215, 1));
    }
    await unmount(tester);
  });

  testWidgets(
    'older history reveals a real transition instead of marking an unknown start',
    (tester) async {
      final client = ConversationClient();
      final a = _Room(
        client,
        '!history-a:example.invalid',
        network: 'whatsapp',
      );
      final b = _Room(
        client,
        '!history-b:example.invalid',
        network: 'messenger',
      );
      _event(a, r'$current', 'Initially loaded message', start);
      await mount(tester, client, [a, b]);
      expect(markers(tester), isEmpty);
      final current = find.byWidgetPredicate(
        (widget) => widget is Message && widget.event.eventId == r'$current',
      );
      final originalElement = tester.element(current);
      b.revealOlder(
        _event(
          b,
          r'$history',
          'Older Messenger history',
          start.subtract(const Duration(minutes: 1)),
          add: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Older Messenger history'), findsOneWidget);
      expect(markers(tester), ['whatsapp']);
      expect(tester.element(current), same(originalElement));
      await unmount(tester);
    },
  );

  testWidgets('a bridge service notice does not create a network switch', (
    tester,
  ) async {
    final client = ConversationClient();
    final a = _Room(client, '!notice-a:example.invalid', network: 'whatsapp');
    final b = _Room(client, '!notice-b:example.invalid', network: 'messenger');
    _event(a, r'$before', 'Before service notice', start);
    _event(
      b,
      r'$service',
      'Fictional bridge failure',
      start.add(const Duration(minutes: 1)),
      content: {
        'msgtype': MessageTypes.Notice,
        'body': 'Fictional bridge failure',
        'fi.mau.bridge.internal_error': true,
      },
    );
    _event(
      a,
      r'$after',
      'After service notice',
      start.add(const Duration(minutes: 2)),
    );
    await mount(tester, client, [a, b]);
    expect(find.text('After service notice'), findsOneWidget);
    expect(markers(tester), isEmpty);
    await unmount(tester);
  });

  for (final missingMetadata in [true, false]) {
    testWidgets(
      'an ${missingMetadata ? 'unidentified' : 'unknown'} source between Messenger messages has no network logos',
      (tester) async {
        final client = ConversationClient();
        final messenger = _Room(
          client,
          '!known-network:example.invalid',
          network: 'messenger',
        );
        final unknown = _Room(
          client,
          '!unknown-network:example.invalid',
          network: 'unknown',
        );
        if (missingMetadata) unknown.states.remove('m.bridge');
        expect(PersonalClient.networkOf(unknown), 'unknown');
        _event(messenger, r'$before-unknown', 'Before unknown source', start);
        _event(
          unknown,
          r'$unknown-source',
          'Message with no identified network',
          start.add(const Duration(minutes: 1)),
        );
        _event(
          messenger,
          r'$after-unknown',
          'Still on Messenger',
          start.add(const Duration(minutes: 2)),
        );
        await mount(tester, client, [messenger, unknown]);
        expect(find.text('Message with no identified network'), findsOneWidget);
        expect(find.text('Still on Messenger'), findsOneWidget);
        expect(markers(tester), isEmpty);
        await unmount(tester);
      },
    );
  }

  for (final type in [EventTypes.Encrypted, EventTypes.Message]) {
    final encrypted = type == EventTypes.Encrypted;
    testWidgets(
      'a redacted ${encrypted ? 'encrypted service line does not switch networks' : 'message placeholder still switches networks'}',
      (tester) async {
        final client = ConversationClient();
        final messenger = _Room(
          client,
          '!redacted-messenger:example.invalid',
          network: 'messenger',
        );
        final whatsapp = _Room(
          client,
          '!redacted-whatsapp:example.invalid',
          network: 'whatsapp',
        );
        _event(
          messenger,
          r'$before-redacted',
          'Before the deleted event',
          start,
        );
        final redacted = _event(
          whatsapp,
          r'$redacted',
          'Deleted event',
          start.add(const Duration(minutes: 1)),
          type: type,
        );
        redacted.setRedactionEvent(
          Event(
            room: whatsapp,
            eventId: r'$redaction',
            senderId: '@anna:example.invalid',
            type: EventTypes.Redaction,
            originServerTs: start.add(const Duration(minutes: 2)),
            content: {'redacts': redacted.eventId},
            redacts: redacted.eventId,
          ),
        );
        _event(
          messenger,
          r'$after-redacted',
          'Back on Messenger',
          start.add(const Duration(minutes: 3)),
        );
        await mount(tester, client, [messenger, whatsapp]);
        expect(find.text('Back on Messenger'), findsOneWidget);
        if (encrypted) {
          expect(find.byType(StateMessage), findsOneWidget);
          expect(markers(tester), isEmpty);
        } else {
          expect(find.byType(RedactionWidget), findsOneWidget);
          expect(markers(tester), hasLength(2));
          expect(markers(tester).toSet(), {'whatsapp', 'messenger'});
        }
        await unmount(tester);
      },
    );
  }

  testWidgets('a network switch into an album stays on its visible lead', (
    tester,
  ) async {
    final client = ConversationClient();
    final a = _Room(client, '!album-a:example.invalid', network: 'whatsapp');
    final b = _Room(client, '!album-b:example.invalid', network: 'messenger');
    _event(a, r'$text', 'Before the album', start);
    for (var i = 0; i < 2; i++) {
      _event(
        b,
        '\$image-$i',
        'photo-$i.jpg',
        start.add(Duration(seconds: 10 + i)),
        content: {
          'msgtype': MessageTypes.Image,
          'body': 'photo-$i.jpg',
          'filename': 'photo-$i.jpg',
          'url': 'mxc://example.invalid/fictional-$i',
          'info': {'w': 300, 'h': 200, 'size': 12, 'mimetype': 'image/jpeg'},
        },
      );
    }
    await mount(tester, client, [a, b]);
    expect(markers(tester), ['messenger']);
    final messages = tester.widgetList<Message>(find.byType(Message));
    expect(
      messages.where((message) => message.album?.lead == false),
      hasLength(1),
    );
    final lead = find.byWidgetPredicate(
      (widget) => widget is Message && widget.album?.lead == true,
    );
    expect(
      tester.getTopLeft(find.byType(ConversationNetworkChange)).dy,
      lessThan(tester.getTopLeft(lead).dy),
    );
    await unmount(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('network changes capture in ${brightness.name}', (
      tester,
    ) async {
      final client = ConversationClient();
      final a = _Room(
        client,
        '!capture-a:example.invalid',
        network: 'whatsapp',
      );
      final b = _Room(
        client,
        '!capture-b:example.invalid',
        network: 'messenger',
      );
      final c = _Room(
        client,
        '!capture-c:example.invalid',
        network: 'instagram',
      );
      _event(a, r'$a1', 'Are we meeting tomorrow?', start);
      _event(
        a,
        r'$a2',
        'Yes, after class.',
        start.add(const Duration(minutes: 1)),
        outgoing: true,
      );
      _event(
        b,
        r'$b1',
        'I will send the address here.',
        start.add(const Duration(minutes: 2)),
        outgoing: true,
      );
      _event(b, r'$b2', 'Thanks!', start.add(const Duration(minutes: 3)));
      _event(
        c,
        r'$c1',
        'Found the place.',
        start.add(const Duration(minutes: 4)),
      );
      _event(
        c,
        r'$c2',
        'See you there.',
        start.add(const Duration(minutes: 5)),
      );
      await mount(
        tester,
        client,
        [a, b, c],
        brightness: brightness,
        size: const Size(430, 932),
      );
      final directory =
          Platform.environment['CHATLOOM_NETWORK_CHANGE_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-network-changes')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/conversation-network-changes-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.byType(ConversationNetworkChange), findsNWidgets(2));
      await unmount(tester);
    });
  }
}
