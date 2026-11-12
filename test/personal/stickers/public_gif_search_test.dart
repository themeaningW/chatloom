// SPDX-License-Identifier: AGPL-3.0-or-later
// Fictional keys, contacts and media. No request reaches an external service.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatloom/pages/chat/conversation_source.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/round_video/round_playback_coordinator.dart';
import 'package:chatloom/personal/stickers/composer_panel.dart';
import 'package:chatloom/personal/stickers/gif_result_tile.dart';
import 'package:chatloom/personal/stickers/gif_search.dart';
import 'package:chatloom/personal/stickers/online_gif_panel.dart';
import 'package:chatloom/personal/stickers/public_gif_search.dart';
import 'package:chatloom/personal/stickers/sticker_panel.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart'
    show FontLoader, MethodChannel, TextInputAction, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../notion/conversation_test_support.dart';

Map<String, Object?> _item(String slug, {bool clip = false}) => {
  'slug': slug,
  'title': 'Fictional reaction',
  'file': clip
      ? {'mp4': 'https://static.klipy.com/$slug.mp4?delivery=keep'}
      : {
          'md': {
            'mp4': {
              'url': 'https://static.klipy.com/$slug.mp4?delivery=keep',
              'width': 320,
              'height': 240,
            },
          },
          // No remote thumbnail: tests never load a real Image.network.
        },
};
http.Response _page(List<Object?> items, {bool more = false}) => http.Response(
  jsonEncode({
    'result': true,
    'data': {'data': items, 'has_next': more},
  }),
  200,
);

class _Host implements ConversationComposerHost {
  _Host(
    this.room, {
    this.replyEvent,
    this.activeThreadId,
    this.threadLastEventId,
  });
  @override
  final Room room;
  @override
  Event? replyEvent;
  @override
  final String? activeThreadId;
  @override
  final String? threadLastEventId;
  @override
  void cancelReplyEventAction() => replyEvent = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = streams.length;
    streams[id] = StreamController<VideoEvent>.broadcast(
      onListen: () => scheduleMicrotask(
        () => streams[id]?.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 2),
            size: const Size(320, 240),
          ),
        ),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) => streams[id]!.stream;
  @override
  Future<void> dispose(int id) async {
    playing.remove(id);
    unawaited(streams.remove(id)?.close());
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> play(int id) async {
    playing.add(id);
  }

  @override
  Future<void> pause(int id) async {
    playing.remove(id);
  }

  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
}

void main() {
  setUpAll(() async {
    final text = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      text.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await text.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  late Room room;
  setUp(() {
    room = ConversationRoom(ConversationClient(), '!fixture:example.invalid');
    GifResultTile.debugSupportsPlayback = false;
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });
  tearDown(() {
    GifResultTile.debugSupportsPlayback = null;
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });

  test(
    'GIF search is direct, paginated, and excludes Matrix credentials',
    () async {
      final calls = <http.Request>[];
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((r) async {
          calls.add(r);
          return _page([_item('reaction')], more: true);
        }),
      );
      addTearDown(source.dispose);
      final page = await source.search(room, '  zażółć & cats  ');
      expect(page.nextOffset, '2');
      expect(
        page.results.single.remoteVideo.toString(),
        'https://static.klipy.com/reaction.mp4?delivery=keep',
      );
      await source.search(room, 'test', offset: page.nextOffset);
      expect(calls.last.url.queryParameters['page'], '2');
      expect(calls.first.url.host, 'api.klipy.com');
      expect(calls.first.url.queryParameters['q'], 'zażółć & cats');
      expect(calls.first.headers['Authorization'], isNull);
      expect(calls.first.url.queryParameters.containsKey('user_id'), isFalse);
      expect(
        calls.first.url.queryParameters.containsKey('customer_id'),
        isFalse,
      );
    },
  );
  test(
    'clips have audio and a separate endpoint; GIFs have looping flags',
    () async {
      late Uri requested;
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((r) async {
          requested = r.url;
          return _page([_item('clip', clip: true)]);
        }),
      )..kind = GifSearchKind.clips;
      addTearDown(source.dispose);
      final clip = (await source.search(room, 'hello')).results.single;
      expect(requested.path, endsWith('/clips/search'));
      expect(clip.hasAudio, isTrue);
      final clipInfo =
          PublicGifSearch.sendPlan(room, clip).content!['info'] as Map;
      expect(clipInfo['fi.mau.gif'], isNull);
      final gif = PublicGifSearch.parseItem(_item('gif'), GifSearchKind.gifs)!;
      final gifInfo =
          PublicGifSearch.sendPlan(room, gif).content!['info'] as Map;
      expect(gifInfo['fi.mau.gif'], isTrue);
      expect(gifInfo['fi.mau.no_audio'], isTrue);
    },
  );
  test('missing key and blank queries make no requests', () async {
    var calls = 0;
    final source = PublicGifSearch(
      client: MockClient((_) async {
        calls++;
        return _page([]);
      }),
    );
    addTearDown(source.dispose);
    expect(source.availability(room).enabled, isFalse);
    await expectLater(
      source.search(room, 'hi'),
      throwsA(isA<GifSearchException>()),
    );
    expect(calls, 0);
  });
  test('API errors never expose a key, query URL, or remote message', () async {
    for (final status in [401, 403, 429, 500]) {
      final source = PublicGifSearch(
        apiKey: 'fictional-secret',
        client: MockClient(
          (r) async => http.Response('private error: ${r.url}', status),
        ),
      );
      try {
        await source.search(room, 'private-query');
        fail('Expected failure');
      } on GifSearchException catch (e) {
        expect(e.message, isNot(contains('fictional-secret')));
        expect(e.message, isNot(contains('private-query')));
        expect(e.toString(), 'GifSearchException');
      } finally {
        source.dispose();
      }
    }
  });
  test(
    'provider URLs must be HTTPS KLIPY URLs; ads are not playable media',
    () {
      for (final url in [
        'http://static.klipy.com/x',
        'https://klipy.com.evil.invalid/x',
        'https://user:pass@static.klipy.com/x',
        'file:///x',
      ]) {
        expect(PublicGifSearch.mediaUri(url), isNull);
      }
      expect(
        PublicGifSearch.parseItem({
          ..._item('ad'),
          'type': 'ad',
        }, GifSearchKind.gifs),
        isNull,
      );
    },
  );
  test(
    'previews return direct URLs without fetching or uploading media',
    () async {
      var calls = 0;
      final source = PublicGifSearch(
        client: MockClient((_) async {
          calls++;
          throw StateError('No HTTP');
        }),
      );
      addTearDown(source.dispose);
      final item = PublicGifSearch.parseItem(
        _item('preview'),
        GifSearchKind.gifs,
      )!;
      final media = await source.media(room, item, video: true);
      expect(media.item, isNull);
      expect(media.remoteVideo, item.remoteVideo);
      expect(calls, 0);
    },
  );
  test(
    'selected MP4 is downloaded without auth, redirects or URL rewriting',
    () async {
      final source = PublicGifSearch(
        client: MockClient((r) async {
          expect(r.url.query, 'delivery=keep');
          expect(r.followRedirects, isFalse);
          expect(r.headers['Authorization'], isNull);
          return http.Response.bytes([
            0,
            0,
            0,
            16,
            ...ascii.encode('ftypisom'),
            0,
            0,
            0,
            0,
          ], 200);
        }),
      );
      addTearDown(source.dispose);
      final file = await source.download(
        PublicGifSearch.parseItem(_item('selected'), GifSearchKind.gifs)!,
      );
      expect(file.mimeType, 'video/mp4');
      expect(file.width, 320);
    },
  );
  test('download rejects redirects, HTML and oversized responses', () async {
    for (final response in [
      http.Response('', 302),
      http.Response('<html>error</html>', 200),
      http.Response(
        '',
        200,
        headers: {'content-length': '${PublicGifSearch.maxMediaBytes + 1}'},
      ),
    ]) {
      final source = PublicGifSearch(client: MockClient((_) async => response));
      await expectLater(
        source.download(
          PublicGifSearch.parseItem(_item('bad'), GifSearchKind.gifs)!,
        ),
        throwsA(isA<GifSearchException>()),
      );
      source.dispose();
    }
  });

  test(
    'unannounced oversized stream is stopped before it becomes a file',
    () async {
      final source = PublicGifSearch(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(Uint8List(PublicGifSearch.maxMediaBytes + 1)),
            200,
          ),
        ),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(
          PublicGifSearch.parseItem(_item('huge'), GifSearchKind.gifs)!,
        ),
        throwsA(
          isA<GifSearchException>().having(
            (e) => e.message,
            'reason',
            contains('too large'),
          ),
        ),
      );
    },
  );

  Widget app(PublicGifSearch source) => MaterialApp(
    theme: NotionTheme.build(Brightness.dark),
    home: Scaffold(
      body: SizedBox(
        height: 420,
        child: OnlineGifPanel(
          host: _Host(room),
          source: source,
          loadCredentials: false,
        ),
      ),
    ),
  );

  test(
    'GIPHY has its own API, key, pagination and unmodified media URLs',
    () async {
      final requests = <http.Request>[];
      final source = PublicGifSearch(
        provider: GifProvider.giphy,
        apiKey: 'giphy-fictional-key',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'reaction',
                  'title': 'Fictional reaction',
                  'images': {
                    'original': {
                      'mp4':
                          'https://media.giphy.com/reaction.mp4?cid=preserved',
                      'width': '320',
                      'height': '240',
                      'mp4_size': '1000',
                    },
                    'fixed_height_still': {
                      'url':
                          'https://media.giphy.com/reaction.jpg?cid=preserved',
                    },
                  },
                },
              ],
              'pagination': {'total_count': 100, 'count': 24, 'offset': 24},
            }),
            200,
          );
        }),
      );
      addTearDown(source.dispose);
      final page = await source.search(room, 'hello', offset: '2');
      expect(requests.single.url.host, 'api.giphy.com');
      expect(
        requests.single.url.queryParameters['api_key'],
        'giphy-fictional-key',
      );
      expect(requests.single.url.queryParameters['offset'], '24');
      expect(requests.single.headers['Authorization'], isNull);
      expect(page.nextOffset, '3');
      expect(
        page.results.single.remoteVideo.toString(),
        'https://media.giphy.com/reaction.mp4?cid=preserved',
      );
      expect(
        page.results.single.remoteThumbnail.toString(),
        'https://media.giphy.com/reaction.jpg?cid=preserved',
      );
      expect(page.results.single.hasAudio, isFalse);
    },
  );
  test('changing providers rejects an outstanding response', () async {
    final pending = Completer<http.Response>();
    final source = PublicGifSearch(
      apiKey: 'fictional-key',
      client: MockClient((_) => pending.future),
    );
    addTearDown(source.dispose);
    final request = source.search(room, 'hello');
    source.provider = GifProvider.giphy;
    pending.complete(_page([_item('stale')]));
    await expectLater(request, throwsA(isA<GifSearchException>()));
    expect(source.configured, isFalse);
  });
  testWidgets(
    'provider picker switches to GIPHY with its own setup and no clips',
    (tester) async {
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((_) async => throw StateError('No HTTP')),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(app(source));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KLIPY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GIPHY'));
      await tester.pumpAndSettle();
      expect(source.provider, GifProvider.giphy);
      expect(find.text('Set up GIPHY'), findsOneWidget);
      expect(find.text('Clips'), findsNothing);
      expect(find.bySemanticsLabel('Powered by GIPHY'), findsOneWidget);
    },
  );

  testWidgets('narrow large-text setup stays usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = PublicGifSearch(
      client: MockClient((_) async => throw StateError('No HTTP')),
    );
    addTearDown(source.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture-klipy'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NotionTheme.build(Brightness.dark),
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              height: 420,
              child: OnlineGifPanel(
                host: _Host(room),
                source: source,
                loadCredentials: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final directory = Platform.environment['CHATLOOM_KLIPY_CAPTURE_DIR'];
    if (directory != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-klipy')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$directory/klipy-320-large-text.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets(
    'preview and cancel never download or send; Send queues only the selected file',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final player = _Player();
      VideoPlayerPlatform.instance = player;
      RoundPlaybackCoordinator.shared.debugReset();
      addTearDown(() {
        VideoPlayerPlatform.instance = original;
        RoundPlaybackCoordinator.shared.debugReset();
      });
      final requests = <String>[];
      final sent = <GifSendRequest>[];
      final reply = Event(
        room: room,
        type: EventTypes.Message,
        content: {'body': 'Earlier'},
        eventId: r'$reply',
        senderId: '@anna:example.invalid',
        originServerTs: DateTime(2020),
      );
      final host = _Host(
        room,
        replyEvent: reply,
        activeThreadId: r'$root',
        threadLastEventId: r'$last',
      );
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((r) async {
          requests.add(r.url.host);
          return r.url.host == 'api.klipy.com'
              ? _page([_item('chosen')])
              : http.Response.bytes([
                  0,
                  0,
                  0,
                  16,
                  ...ascii.encode('ftypisom'),
                  0,
                  0,
                  0,
                  0,
                ], 200);
        }),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              height: 420,
              child: OnlineGifPanel(
                host: host,
                source: source,
                loadCredentials: false,
                send: (r) async {
                  sent.add(r);
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('klipy-search')),
        'hello',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GifResultTile));
      await tester.pumpAndSettle();
      expect(find.text('Send'), findsOneWidget);
      expect(requests, ['api.klipy.com']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(requests, ['api.klipy.com']);
      await tester.tap(find.byType(GifResultTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      // Stream.timeout crosses the fake-async zone; yield a real event-loop
      // turn before pumping its widget continuation.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(
        sent,
        hasLength(1),
        reason:
            'Requests: $requests; UI: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
      );
      expect(sent.single.room, same(room));
      expect(sent.single.reply, same(reply));
      expect(sent.single.thread, r'$root');
      expect(sent.single.last, r'$last');
      expect(sent.single.file.mimeType, 'video/mp4');
      expect((sent.single.extraContent['info'] as Map)['fi.mau.gif'], isTrue);
      expect(sent.single.extraContent.containsKey('url'), isFalse);
      expect(requests, ['api.klipy.com', 'static.klipy.com']);
      await tester.tap(find.byType(GifResultTile));
      await tester.pumpAndSettle();
      PersonalPrivacy.surfaceUnlocked = false;
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(requests, ['api.klipy.com', 'static.klipy.com']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'no Telegram requirement; setup is available without making a request',
    (tester) async {
      final source = PublicGifSearch(
        client: MockClient((_) async => throw StateError('No HTTP')),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(app(source));
      expect(find.text('Set up KLIPY'), findsOneWidget);
      expect(find.textContaining('Connect Telegram'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final provider in GifProvider.values) {
    testWidgets(
      'unconfigured $provider accepts and keeps typing without an API request',
      (tester) async {
        var requests = 0;
        final source = PublicGifSearch(
          apiKey: '',
          provider: provider,
          client: MockClient((_) async {
            requests++;
            return _page([]);
          }),
        );
        addTearDown(source.dispose);
        await tester.pumpWidget(app(source));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('klipy-search'));
        await tester.tap(field);
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        tester.testTextInput.enterText('cat');
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.widget<TextField>(field).controller!.text, 'cat');
        expect(requests, 0);
        expect(find.text('Set up ${source.label}'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('compact GIF controls in ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((_) async => _page([])),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NotionTheme.build(brightness),
          home: RepaintBoundary(
            key: const ValueKey('capture-compact-gifs'),
            child: Scaffold(
              appBar: AppBar(title: const Text('Fictional chat')),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 360,
                  child: OnlineGifPanel(
                    host: _Host(room),
                    source: source,
                    loadCredentials: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['KLIPY', 'GIFs', 'Clips']) {
        final pill = find.ancestor(
          of: find.text(label),
          matching: find.byType(NotionGlassPill),
        );
        final surface = find.descendant(
          of: pill,
          matching: find.byType(NotionGlassSurface),
        );
        expect(tester.getSize(pill).height, 48);
        expect(tester.getSize(surface).height, 36);
      }
      final directory = Platform.environment['CHATLOOM_KLIPY_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-compact-gifs')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/gif-controls-${brightness.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final clips = find.ancestor(
        of: find.text('Clips'),
        matching: find.byType(NotionGlassPill),
      );
      final rect = tester.getRect(clips);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      await tester.pumpAndSettle();
      expect(source.kind, GifSearchKind.clips);
      await tester.tap(find.text('KLIPY'));
      await tester.pumpAndSettle();
      expect(find.text('GIF source'), findsOneWidget);
      await tester.tap(find.text('GIPHY'));
      await tester.pumpAndSettle();
      expect(source.provider, GifProvider.giphy);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final expired in [false, true]) {
    testWidgets(
      'provider setup resumes only a current query: expired=$expired',
      (tester) async {
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final requests = <String>[];
        final source = PublicGifSearch(
          apiKey: '',
          client: MockClient((request) async {
            requests.add(request.url.toString());
            return _page([]);
          }),
        );
        addTearDown(source.dispose);
        await tester.pumpWidget(app(source));
        await tester.enterText(
          find.byKey(const ValueKey('klipy-search')),
          'cat',
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(requests, isEmpty);
        if (expired) {
          PersonalPrivacy.surfaceUnlocked = false;
          PersonalPrivacy.surfaceUnlocked = true;
        }
        await source.setKey('fictional-key');
        await tester.pumpAndSettle();
        if (expired) {
          expect(requests, isEmpty);
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        }
        expect(requests, hasLength(1));
        expect(requests.single, contains('cat'));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('klipy-search')))
              .controller!
              .text,
          'cat',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'GIF typing survives the keyboard in the full composer at $size / $scale',
        (tester) async {
          ComposerKeyboardMetrics.reset();
          StickerPanel.debugResetTab(StickerPanelTab.gifs);
          final input = FocusNode();
          final panelSearch = FocusNode();
          final scope = FocusScopeNode();
          final draft = TextEditingController(text: 'Preserved draft');
          addTearDown(() {
            input.dispose();
            panelSearch.dispose();
            scope.dispose();
            draft.dispose();
            StickerPanel.debugResetTab();
          });
          final requests = <String>[];
          final source = PublicGifSearch(
            apiKey: 'fictional-key',
            client: MockClient((request) async {
              requests.add(request.url.toString());
              return _page([]);
            }),
          );
          addTearDown(source.dispose);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: NotionTheme.build(
                Brightness.dark,
              ).copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                appBar: AppBar(title: const Text('Fictional chat')),
                body: Column(
                  children: [
                    const Expanded(child: SizedBox()),
                    TextField(
                      key: const ValueKey('draft'),
                      focusNode: input,
                      controller: draft,
                    ),
                    ComposerPanelSlot(
                      visible: true,
                      inputFocus: input,
                      searchFocus: scope,
                      softKeyboard: true,
                      builder: (context, height) => FocusScope(
                        node: scope,
                        child: StickerPanel(
                          host: _Host(room),
                          searchFocus: panelSearch,
                          gifSource: source,
                          loadGifCredentials: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final field = find.byKey(const ValueKey('klipy-search'));
          final state = tester.state(find.byType(OnlineGifPanel));
          await tester.tap(field);
          await tester.pump();
          tester.testTextInput.enterText('ca');
          for (final inset in [300.0, 260.0, 300.0]) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            await tester.pump(const Duration(milliseconds: 40));
            expect(tester.takeException(), isNull);
            expect(panelSearch.hasFocus, isTrue);
          }
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(OnlineGifPanel)), same(state));
          expect(tester.testTextInput.isVisible, isTrue);
          tester.testTextInput.enterText('cat');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field).controller!.text, 'cat');
          expect(requests.last, contains('cat'));
          expect(draft.text, 'Preserved draft');
          final inputRect = tester.getRect(field);
          expect(inputRect.bottom, lessThanOrEqualTo(size.height - 300));
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(panelSearch.hasFocus, isFalse);
          expect(find.text('Clips'), findsOneWidget);
          expect(tester.state(find.byType(OnlineGifPanel)), same(state));
          expect(tester.widget<TextField>(field).controller!.text, 'cat');
          expect(draft.text, 'Preserved draft');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }

  testWidgets('debounces typing, shows results and searches clips separately', (
    tester,
  ) async {
    final paths = <String>[];
    final source = PublicGifSearch(
      apiKey: 'fictional-key',
      client: MockClient((r) async {
        paths.add(r.url.path);
        return _page([_item('reaction')]);
      }),
    );
    addTearDown(source.dispose);
    await tester.pumpWidget(app(source));
    await tester.enterText(find.byKey(const ValueKey('klipy-search')), 'he');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('klipy-search')), 'hello');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(paths, hasLength(1));
    expect(find.byType(GifResultTile), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clips'));
    await tester.pumpAndSettle();
    expect(paths.last, endsWith('/clips/search'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'old search results are ignored immediately after editing and lock',
    (tester) async {
      final response = Completer<http.Response>();
      final source = PublicGifSearch(
        apiKey: 'fictional-key',
        client: MockClient((_) => response.future),
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(app(source));
      final field = find.byKey(const ValueKey('klipy-search'));
      await tester.enterText(field, 'old');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(field, 'new');
      PersonalPrivacy.surfaceUnlocked = false;
      response.complete(_page([_item('old')]));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(GifResultTile), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
