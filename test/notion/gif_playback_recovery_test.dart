// SPDX-License-Identifier: AGPL-3.0-or-later
// Offline controller protocol only: no native codec, account or provider request.
import 'dart:async';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/pages/chat/events/inline_loop_slots.dart';
import 'package:chatloom/pages/chat/events/inline_loop_video.dart';
import 'package:chatloom/personal/round_video/round_playback_coordinator.dart';
import 'package:chatloom/personal/stickers/gif_result_tile.dart';
import 'package:chatloom/personal/stickers/gif_search.dart';
import 'package:chatloom/personal/stickers/public_gif_search.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
// The fake implements the video_player plugin's platform contract.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'conversation_test_support.dart';

class _Players extends VideoPlayerPlatform {
  var next = 0;
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  final volumes = <int, double>{};
  final loops = <int, bool>{};
  bool failNext = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = next++;
    final fail = failNext;
    failNext = false;
    streams[id] = StreamController<VideoEvent>.broadcast(
      onListen: () => scheduleMicrotask(() {
        if (fail) {
          streams[id]?.addError(
            PlatformException(
              code: 'temporary-media-error',
              message: 'Temporary media failure',
            ),
          );
          return;
        }
        streams[id]?.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 2),
            size: const Size(160, 120),
          ),
        );
      }),
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
  Future<void> play(int id) async => playing.add(id);
  @override
  Future<void> pause(int id) async => playing.remove(id);
  @override
  Future<void> setVolume(int id, double value) async => volumes[id] = value;
  @override
  Future<void> setLooping(int id, bool value) async => loops[id] = value;
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

void main() {
  late _Players players;
  late VideoPlayerPlatform previous;
  late PublicGifSearch source;
  late Room room;
  late Event event;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.autoplayImages.setItem(true);
    await AppSettings.showThumbnailsInTimeline.setItem(true);
    previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = players = _Players();
    source = PublicGifSearch(
      client: MockClient((_) => throw StateError('No HTTP')),
      apiKey: 'fictional',
    );
    room = ConversationRoom(ConversationClient(), '!gif:example.invalid');
    event = Event(
      room: room,
      eventId: r'$gif',
      senderId: '@anna:example.invalid',
      type: EventTypes.Message,
      originServerTs: DateTime.utc(2026),
      content: {
        'msgtype': MessageTypes.Video,
        'body': 'GIF',
        'url': 'mxc://example.invalid/gif',
        'info': {
          'mimetype': 'video/mp4',
          'fi.mau.gif': true,
          'w': 160,
          'h': 120,
        },
      },
    );
    InlineLoopVideo.debugSupportsPlayback = true;
    InlineLoopVideo.debugCreatePlayer = (_) async =>
        VideoPlayerController.networkUrl(
          Uri.parse('https://example.invalid/gif.mp4'),
        );
    GifResultTile.debugSupportsPlayback = true;
    RoundPlaybackCoordinator.shared.debugReset();
    InlineLoopSlots.debugReset();
  });
  tearDown(() async {
    RoundPlaybackCoordinator.shared.debugReset();
    InlineLoopVideo.debugCreatePlayer = null;
    InlineLoopVideo.debugSupportsPlayback = null;
    GifResultTile.debugSupportsPlayback = null;
    VideoPlayerPlatform.instance = previous;
    source.dispose();
    InlineLoopSlots.debugReset();
  });

  Widget tile(bool timeline) => SizedBox(
    width: 160,
    height: 120,
    child: timeline
        ? InlineLoopVideo(event, width: 160, height: 120)
        : GifResultTile(
            result: GifSearchResult(
              id: 'fictional',
              remoteVideo: Uri.parse('https://static.klipy.com/fake.mp4'),
            ),
            source: source,
            room: room,
            size: 160,
            onTap: () {},
            onLongPress: () {},
          ),
  );
  Widget app(Widget child, {bool powerSaving = false, bool reduced = false}) =>
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark).copyWith(
          extensions: [
            ...NotionTheme.build(Brightness.dark).extensions.values,
            NotionDisplayPreferences(reduceMotion: reduced),
          ],
        ),
        home: NotionActivity(
          powerSaving: ValueNotifier(powerSaving),
          child: Scaffold(body: child),
        ),
      );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // The platform stream cancellation completes in the real plugin zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(players.streams, isEmpty, reason: 'All video controllers disposed');
    expect(players.playing, isEmpty);
    expect(InlineLoopSlots.live, 0);
  }

  for (final timeline in [true, false]) {
    final label = timeline ? 'timeline' : 'search';
    testWidgets('$label GIF plays in a lower pane with local MediaQuery size', (
      tester,
    ) async {
      RoundPlaybackCoordinator.shared.debugReset();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.bottomCenter,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(390, 180)),
              child: tile(timeline),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(players.playing, hasLength(1));
      expect(players.volumes.values, everyElement(0));
      expect(players.loops.values, everyElement(true));
      await close(tester);
    });
    testWidgets(
      '$label GIF plays in Low Power Mode but respects Reduce Motion',
      (tester) async {
        RoundPlaybackCoordinator.shared.debugReset();
        await tester.pumpWidget(app(tile(timeline), powerSaving: true));
        await settle(tester);
        expect(players.playing, hasLength(1));
        await close(tester);
        await tester.pumpWidget(
          app(tile(timeline), powerSaving: true, reduced: true),
        );
        await settle(tester);
        expect(players.playing, isEmpty);
        await close(tester);
      },
    );
    testWidgets('$label GIF reacts to unlock after the lifecycle callback', (
      tester,
    ) async {
      RoundPlaybackCoordinator.shared.debugReset();
      unawaited(RoundPlaybackCoordinator.shared.stopAll());
      await tester.pump();
      await tester.pumpWidget(app(tile(timeline)));
      await settle(tester);
      expect(players.playing, isEmpty);
      RoundPlaybackCoordinator.shared.resume();
      await settle(tester);
      expect(players.playing, hasLength(1));
      unawaited(RoundPlaybackCoordinator.shared.stopAll());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);
      expect(players.playing, isEmpty);
      RoundPlaybackCoordinator.shared.resume();
      await settle(tester);
      expect(players.playing, hasLength(1));
      await close(tester);
    });
    testWidgets('$label GIF still honors autoplay off', (tester) async {
      RoundPlaybackCoordinator.shared.debugReset();
      await AppSettings.autoplayImages.setItem(false);
      await tester.pumpWidget(app(tile(timeline)));
      await settle(tester);
      expect(players.playing, isEmpty);
      await close(tester);
    });
    testWidgets('$label GIF retries a transient failure after scrolling back', (
      tester,
    ) async {
      RoundPlaybackCoordinator.shared.debugReset();
      players.failNext = true;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        app(
          ListView(
            controller: scroll,
            children: [tile(timeline), const SizedBox(height: 1600)],
          ),
        ),
      );
      await settle(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);
      expect(players.playing, isEmpty);
      expect(players.next, 1);
      scroll.jumpTo(250);
      await settle(tester);
      scroll.jumpTo(0);
      await settle(tester);
      expect(players.playing, hasLength(1));
      expect(players.next, 2);
      await close(tester);
    });
  }
}
