// SPDX-License-Identifier: AGPL-3.0-or-later
// Real decoding in the production timeline bubble; mock transport, no real send.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/pages/chat/events/image_bubble.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MediaDatabase implements DatabaseApi {
  _MediaDatabase(this.gif);
  final Uint8List gif;
  final reads = <Uri>[];
  final downloads = <Uri>[];
  final still = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
  );
  @override
  int get maxFileSize => 1 << 24;
  @override
  Future<Uint8List?> getFile(Uri uri) async {
    reads.add(uri);
    return null;
  }

  @override
  Future<void> storeFile(Uri uri, Uint8List bytes, int time) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture storage access: ${invocation.memberName}',
  );
}

class _Client extends Client {
  _Client(_MediaDatabase database, http.Client transport)
    : super('inline image fixture', database: database, httpClient: transport) {
    homeserver = Uri.parse('https://example.invalid');
  }
  @override
  Future<bool> authenticatedMediaSupported() async => true;
}

void main() {
  late Uint8List gif;
  late _MediaDatabase database;
  late Client client;
  late Event event;
  void media(String extension) {
    gif = File(
      'test/notion/fixtures/inline-animated.$extension',
    ).readAsBytesSync();
    database = _MediaDatabase(gif);
    client = _Client(
      database,
      MockClient((request) async {
        database.downloads.add(request.url);
        return http.Response.bytes(
          request.url.path.endsWith('poster') ? database.still : gif,
          200,
        );
      }),
    );
    event = Event(
      room: Room(id: '!gif:example.invalid', client: client),
      eventId: r'$gif',
      type: EventTypes.Message,
      senderId: '@fixture:example.invalid',
      originServerTs: DateTime.utc(2026),
      content: {
        'msgtype': MessageTypes.Image,
        'body': 'reaction.$extension',
        'url': 'mxc://example.invalid/original',
        'info': {
          'mimetype': 'image/$extension',
          'size': gif.length,
          'w': 4,
          'h': 4,
          'thumbnail_url': 'mxc://example.invalid/poster',
          'thumbnail_info': {'mimetype': 'image/jpeg', 'w': 4, 'h': 4},
        },
      },
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.autoplayImages.setItem(true);
    await AppSettings.showThumbnailsInTimeline.setItem(true);
    await AppSettings.personalDataSaver.setItem(false);
    media('gif');
  });

  Widget app({
    bool visible = true,
    bool reduced = false,
    NotionAccessibilitySettings? accessibility,
  }) => MaterialApp(
    theme: NotionTheme.build(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: NotionAccessibilityScope(settings: accessibility, child: child!),
    ),
    home: Scaffold(
      body: TickerMode(
        enabled: visible,
        child: ImageBubble(event, width: 64, height: 64),
      ),
    ),
  );

  Future<void> loaded(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      // Let the real codec and fake frame clock both progress.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<int> pixel(WidgetTester tester) async {
    final raw = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((w) => w.image != null)
        .last;
    return (await tester.runAsync(() async {
      final data = await raw.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return data!.buffer.asUint8List().first;
    }))!;
  }

  for (final extension in ['gif', 'webp']) {
    testWidgets(
      '$extension chat bubble downloads original instead of poster and animates without tapping',
      (tester) async {
        media(extension);
        expect(event.hasThumbnail, isTrue);
        await tester.pumpWidget(app());
        await loaded(tester);
        expect(
          database.reads.any((uri) => uri.path.endsWith('original')),
          isTrue,
        );
        expect(
          database.reads.any((uri) => uri.path.endsWith('poster')),
          isFalse,
        );
        final samples = <int>{};
        for (var i = 0; i < 6; i++) {
          samples.add(await pixel(tester));
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(
          samples.length,
          greaterThan(1),
          reason:
              'The inline image must show different GIF frames without a tap',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'unknown-size GIF starts inline within the data-saver read limit',
    (tester) async {
      (event.content['info'] as Map).remove('size');
      await AppSettings.personalDataSaver.setItem(true);
      await tester.pumpWidget(app());
      await loaded(tester);
      expect(
        database.downloads.any((uri) => uri.path.endsWith('original')),
        isTrue,
      );
      expect(find.text('Load image'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('known oversized GIF retains the data-saver explicit-load gate', (
    tester,
  ) async {
    (event.content['info'] as Map)['size'] = 4 * 1024 * 1024;
    await AppSettings.personalDataSaver.setItem(true);
    await tester.pumpWidget(app());
    await loaded(tester);
    expect(database.downloads, isEmpty);
    expect(
      find.byWidgetPredicate(
        (w) => w is NotionIconButton && w.label == 'Load image',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit autoplay off keeps the inline animation still', (
    tester,
  ) async {
    await AppSettings.autoplayImages.setItem(false);
    await tester.pumpWidget(app());
    await loaded(tester);
    final first = await pixel(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      expect(await pixel(tester), first);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native media autoplay stays independent of reduced UI motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        reduced: true,
        accessibility: const NotionAccessibilitySettings(
          reduceMotion: true,
          animatedImages: true,
        ),
      ),
    );
    await loaded(tester);
    final samples = <int>{};
    for (var i = 0; i < 6; i++) {
      samples.add(await pixel(tester));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(samples.length, greaterThan(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disabled native autoplay can be played and paused inside the bubble',
    (tester) async {
      await tester.pumpWidget(
        app(
          reduced: true,
          accessibility: const NotionAccessibilitySettings(
            reduceMotion: true,
            animatedImages: false,
          ),
        ),
      );
      await loaded(tester);
      final still = await pixel(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(await pixel(tester), still);
      await tester.tap(find.byType(NotionMediaPlaybackControl));
      await tester.pump();
      final samples = <int>{};
      for (var i = 0; i < 6; i++) {
        samples.add(await pixel(tester));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(samples.length, greaterThan(1));
      await tester.tap(find.byType(NotionMediaPlaybackControl));
      await tester.pump();
      final paused = await pixel(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(await pixel(tester), paused);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'inline GIF respects ${reduced ? 'Reduce Motion' : 'hidden surface'}',
      (tester) async {
        await tester.pumpWidget(app(visible: reduced, reduced: reduced));
        await loaded(tester);
        final first = await pixel(tester);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 120));
          expect(await pixel(tester), first);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
