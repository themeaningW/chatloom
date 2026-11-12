// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:chatloom/personal/media/media_access.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The text file preserves the report even if a receiving app ignores captions.
/// Native exports reuse the app's protected temporary-file leases.
Future<void> shareAppFeedback(
  String report,
  Uint8List? screenshot,
  Rect origin, {
  required bool Function() isCurrent,
  @visibleForTesting Future<ManagedMediaFile?> Function(Uint8List)? createLease,
  @visibleForTesting Future<ShareResult> Function(ShareParams)? share,
}) async {
  final send = share ?? SharePlus.instance.share;
  ShareParams params(List<XFile>? files) => ShareParams(
    title: 'ChatLoom report',
    subject: 'ChatLoom report',
    text: report,
    files: files,
    sharePositionOrigin: origin,
  );
  if (!isCurrent()) return;
  if (screenshot == null) {
    await send(params(null));
    return;
  }
  if (kIsWeb) {
    await send(
      params([
        XFile.fromData(
          utf8.encode(report),
          name: 'report.txt',
          mimeType: 'text/plain',
        ),
        XFile.fromData(
          screenshot,
          name: 'screenshot.png',
          mimeType: 'image/png',
        ),
      ]),
    );
    return;
  }
  Future<ManagedMediaFile?> nativeLease(Uint8List bytes) async {
    final temporary = await getTemporaryDirectory();
    if (!isCurrent()) return null;
    final access = await MediaAccess.open(
      directory: Directory('${temporary.path}/personal_media'),
    );
    if (!isCurrent()) return null;
    return access.create(bytes, extension: '.png');
  }

  final lease = await (createLease ?? nativeLease)(screenshot);
  if (lease == null) return;
  var keepForService = false;
  try {
    if (!isCurrent()) return;
    final text = lease.siblingFile('report.txt');
    await text.writeAsString(report, encoding: utf8, flush: true);
    if (!isCurrent()) return;
    final result = await send(
      params([
        XFile(text.path, mimeType: 'text/plain'),
        XFile(lease.file.path, mimeType: 'image/png'),
      ]),
    );
    // macOS returns before the chosen service has read its attachments.
    keepForService =
        Platform.isMacOS && result.status == ShareResultStatus.success;
  } finally {
    if (keepForService) {
      Timer(const Duration(minutes: 5), () => unawaited(lease.close()));
    } else {
      await lease.close();
    }
  }
}
