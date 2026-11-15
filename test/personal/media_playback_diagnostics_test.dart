// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/media/media_playback_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notion/conversation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Event event;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    MediaPlaybackDiagnostics.debugReset();
    event = Event(
      room: Room(
        id: '!private-room:example.invalid',
        client: ConversationClient(),
      ),
      eventId: r'$private-event',
      senderId: '@private-person:example.invalid',
      type: EventTypes.Message,
      originServerTs: DateTime.utc(2026),
      content: {
        'msgtype': MessageTypes.Image,
        'body': 'private-caption',
        'url': 'mxc://example.invalid/private-media',
        'file': {'key': 'private-key'},
        'info': {'mimetype': 'image/gif', 'size': 100, 'fi.mau.gif': true},
      },
    );
  });
  tearDown(MediaPlaybackDiagnostics.debugReset);

  test('ordinary builds collect nothing', () async {
    MediaPlaybackDiagnostics.record(event, MediaPlaybackPhase.imageOriginal);
    await MediaPlaybackDiagnostics.debugSettled;
    expect(
      AppSettings.store.getString(MediaPlaybackDiagnostics.storageKey),
      isNull,
    );
  });
  test(
    'opt-in records fixed metadata without message contents or identifiers',
    () async {
      MediaPlaybackDiagnostics.debugEnabled = true;
      MediaPlaybackDiagnostics.record(
        event,
        MediaPlaybackPhase.imageOriginal,
        animatedBytes: false,
      );
      await MediaPlaybackDiagnostics.debugSettled;
      final raw = AppSettings.store.getString(
        MediaPlaybackDiagnostics.storageKey,
      )!;
      final sample = (jsonDecode(raw) as List).single as Map;
      expect(sample['mime'], 'image/gif');
      expect(sample['animatedBytes'], isFalse);
      expect(sample['phase'], 'imageOriginal');
      expect(raw, isNot(contains('private-')));
      expect(raw, isNot(contains('example.invalid')));
      expect(raw, isNot(contains('mxc://')));
    },
  );
  test(
    'untrusted MIME strings are not retained and history is bounded',
    () async {
      MediaPlaybackDiagnostics.debugEnabled = true;
      event.content['info'] = {'mimetype': 'private-mime-with-data'};
      for (var i = 0; i < 60; i++) {
        MediaPlaybackDiagnostics.record(
          event,
          MediaPlaybackPhase.imageOriginal,
          animatedBytes: i.isEven,
        );
      }
      await MediaPlaybackDiagnostics.debugSettled;
      final raw = AppSettings.store.getString(
        MediaPlaybackDiagnostics.storageKey,
      )!;
      expect(jsonDecode(raw) as List, hasLength(32));
      expect(raw, isNot(contains('private-mime')));
    },
  );
}
