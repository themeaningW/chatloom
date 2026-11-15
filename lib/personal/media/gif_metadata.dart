// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:matrix/matrix.dart';

/// Local presentation of GIF videos, independent of the bridge's send format.
/// Some bridges accept an MP4 only as an ordinary video; `fi.mau.gif` changes
/// capability routing, whereas our own hint is ignored by those bridges.
abstract final class GifMetadata {
  static const marker = 'pl.personal.chat.gif';

  static bool hinted(Map<String, Object?>? info) =>
      info?[marker] == true ||
      info?['fi.mau.gif'] == true ||
      (info?['fi.mau.autoplay'] == true && info?['fi.mau.loop'] == true);

  static bool isVideoLoop(Map<String, Object?> content) {
    if (content['msgtype'] != MessageTypes.Video) return false;
    final info = content.tryGetMap<String, Object?>('info');
    return hinted(info) || isLegacyPublicGif(content);
  }

  /// Previous ChatLoom builds dropped the GIF flags when adapting these two
  /// explicitly named search downloads. Recover existing sent messages too.
  /// Do not guess from duration, MP4 extension, or a generic "GIF" caption:
  /// ordinary videos and the search provider's audio clips stay tap-to-play.
  static bool isLegacyPublicGif(Map<String, Object?> content) {
    final info = content.tryGetMap<String, Object?>('info');
    if (info?['mimetype'] != 'video/mp4') return false;
    final name = content['filename'] ?? content['body'];
    return name == 'KLIPY GIF.mp4' || name == 'GIPHY GIF.mp4';
  }
}
