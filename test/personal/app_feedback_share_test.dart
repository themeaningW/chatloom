// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:chatloom/personal/app_feedback_share.dart';
import 'package:chatloom/personal/media/media_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

class _Lease implements ManagedMediaFile {
  _Lease(this.directory);
  final Directory directory;
  bool closed = false;
  @override
  File get file => File('${directory.path}/media.png');
  @override
  File siblingFile(String name) => File('${directory.path}/$name');
  @override
  Future<void> close() async {
    if (closed) return;
    if (!directory.absolute.path.startsWith(
      '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}chatloom-feedback-test-',
    )) {
      throw StateError('Fixture cleanup escaped its temporary directory');
    }
    closed = true;
    await directory.delete(recursive: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected lease operation');
}

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  const origin = Rect.fromLTWH(16, 400, 250, 48);
  const dismissed = ShareResult('', ShareResultStatus.dismissed);

  Future<_Lease> create(Uint8List bytes) async {
    final lease = _Lease(
      await Directory.systemTemp.createTemp('chatloom-feedback-test-'),
    );
    addTearDown(lease.close);
    await lease.file.writeAsBytes(bytes);
    return lease;
  }

  test(
    'native handoff contains readable text and PNG; dismissal cleans the lease',
    () async {
      late _Lease lease;
      var calls = 0;
      await shareAppFeedback(
        'Fictional report',
        png,
        origin,
        isCurrent: () => true,
        createLease: (bytes) async => lease = await create(bytes),
        share: (params) async {
          calls++;
          expect(params.text, 'Fictional report');
          expect(params.sharePositionOrigin, origin);
          expect(params.files, hasLength(2));
          expect(params.files![0].mimeType, 'text/plain');
          expect(await params.files![0].readAsString(), 'Fictional report');
          expect(params.files![1].mimeType, 'image/png');
          expect(await params.files![1].readAsBytes(), png);
          expect(lease.closed, isFalse);
          return dismissed;
        },
      );
      expect(calls, 1);
      expect(lease.closed, isTrue);
      expect(await lease.directory.exists(), isFalse);
    },
  );

  test(
    'a native share failure still cleans its temporary attachments',
    () async {
      late _Lease lease;
      await expectLater(
        shareAppFeedback(
          'Fictional report',
          png,
          origin,
          isCurrent: () => true,
          createLease: (bytes) async => lease = await create(bytes),
          share: (_) async => throw StateError('Fixture native failure'),
        ),
        throwsStateError,
      );
      expect(lease.closed, isTrue);
    },
  );

  test(
    'privacy invalidated during preparation prevents handoff and closes the lease',
    () async {
      var current = true;
      var sent = false;
      late _Lease lease;
      await shareAppFeedback(
        'Fictional report',
        png,
        origin,
        isCurrent: () => current,
        createLease: (bytes) async {
          lease = await create(bytes);
          current = false;
          return lease;
        },
        share: (_) async {
          sent = true;
          return dismissed;
        },
      );
      expect(sent, isFalse);
      expect(lease.closed, isTrue);
    },
  );

  test(
    'removing the screenshot shares text only without staging files',
    () async {
      ShareParams? exported;
      await shareAppFeedback(
        'Text-only report',
        null,
        origin,
        isCurrent: () => true,
        createLease: (_) async => throw StateError('No files expected'),
        share: (params) async {
          exported = params;
          return dismissed;
        },
      );
      expect(exported!.text, 'Text-only report');
      expect(exported!.files, isNull);
    },
  );
}
