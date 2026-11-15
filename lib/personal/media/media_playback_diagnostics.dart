// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:chatloom/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'gif_metadata.dart';

enum MediaPlaybackPhase {
  imageRoute,
  loopRoute,
  videoRoute,
  imageOriginal,
  imageThumbnail,
  imageFirstFrame,
  imageAnimating,
  loopGated,
  loopStarting,
  loopPlaying,
  loopFailed,
}

/// Opt-in beta diagnostics, stored locally for USB/support inspection. Only
/// fixed categories and booleans are collected: no message text, filenames,
/// URLs, IDs, keys, image bytes, or exception payloads. Release builds are off
/// unless explicitly built with CHATLOOM_MEDIA_DIAGNOSTICS=true.
abstract final class MediaPlaybackDiagnostics {
  static const storageKey = 'pl.personal.media.playback_diagnostics';
  static const _enabled = bool.fromEnvironment('CHATLOOM_MEDIA_DIAGNOSTICS');
  static const _mimes = {
    'image/gif',
    'image/webp',
    'image/apng',
    'image/png',
    'image/jpeg',
    'video/mp4',
    'video/webm',
    'application/octet-stream',
  };
  static final _entries = <Map<String, Object?>>[];
  static String? _last;
  static Future<void> _pending = Future.value();

  @visibleForTesting
  static bool? debugEnabled;
  @visibleForTesting
  static Future<void> get debugSettled => _pending;
  @visibleForTesting
  static void debugReset() {
    _entries.clear();
    _last = null;
    debugEnabled = null;
  }

  static void record(
    Event event,
    MediaPlaybackPhase phase, {
    bool? animatedBytes,
    bool? supported,
    bool? reduced,
    bool? visible,
    bool? tickers,
    bool? route,
    bool? active,
    bool? suspended,
    bool? appReduceMotion,
    bool? systemReduceMotion,
    bool? animatedImages,
    bool? flutterDisableAnimations,
    bool? mediaReduced,
    bool? manualPlayback,
  }) {
    if (!(debugEnabled ?? _enabled)) return;
    final info = event.infoMap;
    final mime = event.attachmentMimetype.toLowerCase().split(';').first.trim();
    final size = info['size'];
    final sample = <String, Object?>{
      'phase': phase.name,
      'media': switch (event.messageType) {
        MessageTypes.Image => 'image',
        MessageTypes.Video => 'video',
        MessageTypes.Sticker => 'sticker',
        _ => 'other',
      },
      'mime': _mimes.contains(mime) ? mime : 'other',
      'own': event.senderId == event.room.client.userID,
      'thumbnail': event.hasThumbnail,
      'gif': info['fi.mau.gif'] == true,
      'loop': info['fi.mau.loop'] == true,
      'autoplayHint': info['fi.mau.autoplay'] == true,
      'localHint': info[GifMetadata.marker] == true,
      'legacyGif': GifMetadata.isLegacyPublicGif(event.content),
      'size': size is! num || size <= 0
          ? 'unknown'
          : size > 2 * 1024 * 1024
          ? 'over2MiB'
          : 'under2MiB',
      'autoplay': AppSettings.autoplayImages.value,
      'dataSaver': AppSettings.personalDataSaver.value,
      'animatedBytes': ?animatedBytes,
      'supported': ?supported,
      'reduced': ?reduced,
      'visible': ?visible,
      'tickers': ?tickers,
      'route': ?route,
      'active': ?active,
      'suspended': ?suspended,
      'appReduceMotion': ?appReduceMotion,
      'systemReduceMotion': ?systemReduceMotion,
      'animatedImages': ?animatedImages,
      'flutterDisableAnimations': ?flutterDisableAnimations,
      'mediaReduced': ?mediaReduced,
      'manualPlayback': ?manualPlayback,
    };
    final encoded = jsonEncode(sample);
    if (_last == encoded) return;
    _last = encoded;
    _entries.add(sample);
    if (_entries.length > 32) _entries.removeAt(0);
    final snapshot = jsonEncode(_entries);
    _pending = _pending.then((_) async {
      try {
        await AppSettings.store.setString(storageKey, snapshot);
      } catch (_) {
        // Diagnostics must not affect loading or playback.
      }
    });
  }
}
