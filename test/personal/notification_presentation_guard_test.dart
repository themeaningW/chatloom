// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/personal/hidden_messages.dart';
import 'package:chatloom/personal/notification_presentation_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No database access in notification guard fixtures');
}

class _Client extends Client {
  _Client() : super('fictional notification session', database: _Database()) {
    accessToken = 'synthetic-session-one';
    homeserver = Uri.parse('https://example.invalid');
  }
  String user = '@owner:example.invalid';
  String device = 'synthetic-device';
  @override
  String get userID => user;
  @override
  String get deviceID => device;
}

void main() {
  test(
    'active conversation suppression understands merged and source routes, scoped to the account',
    () {
      bool visible(
        String path, {
        bool sameAccount = true,
        String? group = 'p',
      }) => notificationConversationVisible(
        location: Uri.parse(path),
        sameAccount: sameAccount,
        roomId: '!one:example.invalid',
        groupId: group,
      );
      expect(visible('/rooms/!one:example.invalid'), isTrue);
      expect(visible('/rooms/!one:example.invalid/details'), isTrue);
      expect(visible('/rooms/person/p'), isTrue);
      expect(visible('/rooms/person/p/!one:example.invalid'), isTrue);
      expect(visible('/rooms/person/p/!other:example.invalid'), isFalse);
      expect(visible('/rooms/person/another'), isFalse);
      expect(visible('/rooms/person/p', sameAccount: false), isFalse);
      expect(visible('/rooms/person/p', group: null), isFalse);
      expect(visible('/rooms/settings'), isFalse);
    },
  );
  late _Client client;
  late Event event;
  var owned = true;
  setUp(() {
    client = _Client();
    owned = true;
    event = Event(
      type: EventTypes.Message,
      room: Room(id: '!fixture:example.invalid', client: client),
      eventId: r'$fixture',
      senderId: '@sender:example.invalid',
      originServerTs: DateTime.utc(2026),
      content: {
        'msgtype': MessageTypes.Text,
        'body': 'Fictional private message',
      },
    );
    HiddenMessages.instance.storageFor = (_) => null;
  });
  tearDown(() {
    HiddenMessages.instance.storageFor = HiddenMessages.defaultStorage;
  });

  Future<int> deferredPresentation(
    NotificationPresentationGuard guard,
    Future<void> read,
  ) async {
    if (!guard.current) return 0;
    await read;
    return guard.current ? 1 : 0;
  }

  test('logout during a deferred private read prevents presentation', () async {
    final gate = Completer<void>();
    final guard = NotificationPresentationGuard(
      event,
      ownerCurrent: () => owned,
    );
    final alert = deferredPresentation(guard, gate.future);
    client.accessToken = null;
    gate.complete();
    expect(await alert, 0);
  });

  test(
    'a removed Matrix owner cannot publish an already queued alert',
    () async {
      final gate = Completer<void>();
      final guard = NotificationPresentationGuard(
        event,
        ownerCurrent: () => owned,
      );
      final alert = deferredPresentation(guard, gate.future);
      owned = false;
      gate.complete();
      expect(await alert, 0);
    },
  );

  test(
    'relogin with the same account does not revive the prior session alert',
    () {
      final guard = NotificationPresentationGuard(event);
      client.accessToken = 'synthetic-session-two';
      expect(guard.current, isFalse);
    },
  );

  test(
    'device, account and homeserver replacement revoke a captured alert',
    () {
      final account = NotificationPresentationGuard(event);
      client.user = '@other:example.invalid';
      expect(account.current, isFalse);
      client.user = '@owner:example.invalid';
      final device = NotificationPresentationGuard(event);
      client.device = 'replacement-device';
      expect(device.current, isFalse);
      final server = NotificationPresentationGuard(event);
      client.homeserver = Uri.parse('https://other.invalid');
      expect(server.current, isFalse);
    },
  );

  test(
    'redaction or local hiding during a deferred read prevents presentation',
    () async {
      final gate = Completer<void>();
      final guard = NotificationPresentationGuard(event);
      final alert = deferredPresentation(guard, gate.future);
      HiddenMessages.instance.hide(event);
      gate.complete();
      expect(await alert, 0);
      HiddenMessages.instance.unhide(event);
      expect(guard.current, isTrue);
      event.setRedactionEvent(
        Event(
          type: EventTypes.Redaction,
          room: event.room,
          eventId: r'$redaction',
          senderId: client.userID,
          originServerTs: DateTime.utc(2026),
          content: {},
        ),
      );
      expect(guard.current, isFalse);
    },
  );

  test(
    'an unchanged signed-in session remains eligible and logs no identity',
    () async {
      final guard = NotificationPresentationGuard(event);
      expect(await deferredPresentation(guard, Future.value()), 1);
      expect(guard.toString(), 'NotificationPresentationGuard(private)');
    },
  );
}
