// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:chatloom/utils/personal_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'gif_search.dart';
import 'sticker_models.dart';
import 'sticker_send_plan.dart';

enum GifSearchKind { gifs, clips }

enum GifProvider { klipy, giphy }

/// Client-side requests only. No Matrix identity, token, room or message is
/// attached to a search. Provider URLs are never rewritten or disk-cached.
class PublicGifSearch extends ChangeNotifier implements GifSearchSource {
  PublicGifSearch({
    http.Client? client,
    String? apiKey,
    this.provider = GifProvider.klipy,
  }) : _client = client ?? http.Client(),
       _keys = {
         GifProvider.klipy: provider == GifProvider.klipy
             ? apiKey ?? const String.fromEnvironment('CHATLOOM_KLIPY_API_KEY')
             : const String.fromEnvironment('CHATLOOM_KLIPY_API_KEY'),
         GifProvider.giphy: provider == GifProvider.giphy
             ? apiKey ?? const String.fromEnvironment('CHATLOOM_GIPHY_API_KEY')
             : const String.fromEnvironment('CHATLOOM_GIPHY_API_KEY'),
       };

  String get storageKey => 'chatloom.${provider.name}.api_key';
  static const maxMediaBytes = 16 * 1024 * 1024;
  final http.Client _client;
  final Map<GifProvider, String> _keys;
  String get _key => _keys[provider] ?? '';
  GifProvider provider;
  String get label => provider == GifProvider.klipy ? 'KLIPY' : 'GIPHY';
  String get hint =>
      provider == GifProvider.klipy ? 'Search KLIPY' : 'Search GIPHY';
  String get documentationUrl => provider == GifProvider.klipy
      ? 'https://docs.klipy.com/'
      : 'https://developers.giphy.com/docs/';
  Future<void>? _loaded;
  bool _disposed = false;
  int _keyRevision = 0;
  GifSearchKind kind = GifSearchKind.gifs;
  bool get configured => _key.isNotEmpty;

  Future<void> loadKey() => _loaded ??= () async {
    final revision = _keyRevision;
    try {
      for (final source in GifProvider.values) {
        final saved = await personalSecureStorage.read(
          key: 'chatloom.${source.name}.api_key',
        );
        if (_disposed || revision != _keyRevision) return;
        if (saved != null) _keys[source] = saved;
      }
    } catch (_) {
      // A build key still works when secure storage is unavailable.
    }
    if (!_disposed) notifyListeners();
  }();

  Future<void> setKey(String value) async {
    ++_keyRevision;
    final selected = provider;
    final next = value.trim();
    if (next.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(next)) {
      throw GifSearchException('Check the $label API key.');
    }
    try {
      await personalSecureStorage.write(key: storageKey, value: next);
    } catch (_) {
      throw const GifSearchException('The key could not be saved securely.');
    }
    if (_disposed) return;
    _keys[selected] = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }

  @override
  Listenable get changes => this;
  @override
  String get privacyNote => 'Searches and previews go to $label.';
  @override
  void prepare(Room room) => loadKey().ignore();
  @override
  void forget(Room room) {}
  @override
  GifSearchAvailability availability(Room room) => configured
      ? GifSearchAvailability.enabled(hint)
      : GifSearchAvailability.disabled(hint, 'Set up $label to search.');

  static Uri? mediaUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !(uri.host == 'klipy.com' ||
            uri.host.endsWith('.klipy.com') ||
            uri.host == 'giphy.com' ||
            uri.host.endsWith('.giphy.com'))) {
      return null;
    }
    return uri;
  }

  static GifSearchResult? parseItem(Object? value, GifSearchKind kind) {
    if (value is! Map || value['type'] == 'ad') return null;
    final id = value['slug'];
    final file = value['file'];
    if (id is! String || id.isEmpty || file is! Map) return null;
    Map? rendition(String format, List<String> sizes) {
      // Clips expose flat formats; GIFs expose a size/format hierarchy.
      final flat = file[format];
      if (flat is String) return {'url': flat};
      if (flat is Map && mediaUri(flat['url']) != null) return flat;
      for (final size in sizes) {
        final group = file[size];
        final entry = group is Map ? group[format] : null;
        if (entry is Map && mediaUri(entry['url']) != null) return entry;
      }
      return null;
    }

    final video = rendition('mp4', const ['md', 'hd', 'sm', 'xs']);
    final thumb = rendition('jpg', const ['sm', 'xs', 'md', 'hd']);
    final url = mediaUri(video?['url']);
    if (url == null) return null;
    int? integer(Object? v) => v is num ? v.toInt() : null;
    return GifSearchResult(
      id: '${kind.name}:$id',
      width: integer(video?['width']),
      height: integer(video?['height']),
      size: integer(video?['size']),
      title: value['title'] is String ? value['title'] as String : null,
      remoteVideo: url,
      remoteThumbnail: mediaUri(thumb?['url']),
      hasAudio: kind == GifSearchKind.clips,
    );
  }

  @override
  Future<GifSearchPage> search(
    Room room,
    String query, {
    String? offset,
  }) async {
    final key = _key;
    final selected = kind;
    final selectedProvider = provider;
    final providerLabel = label;
    if (key.isEmpty) throw GifSearchException('Set up $label first.');
    if (provider == GifProvider.giphy && selected == GifSearchKind.clips) {
      throw const GifSearchException('Choose KLIPY to search clips.');
    }
    final page = int.tryParse(offset ?? '1');
    if (page == null || page < 1) {
      throw const GifSearchException('Invalid page.');
    }
    if (query.trim().isEmpty) return const GifSearchPage([]);
    final uri = provider == GifProvider.giphy
        ? Uri.https('api.giphy.com', '/v1/gifs/search', {
            'api_key': key,
            'q': query.trim(),
            'limit': '24',
            'offset': '${(page - 1) * 24}',
            'rating': 'pg-13',
            'lang': PlatformDispatcher.instance.locale.languageCode,
          })
        : Uri.https('api.klipy.com', '/api/v1/$key/${selected.name}/search', {
            'q': query.trim(),
            'page': '$page',
            'per_page': '24',
            'locale':
                PlatformDispatcher.instance.locale.countryCode?.toLowerCase() ??
                'us',
            'content_filter': 'medium',
            if (selected == GifSearchKind.gifs) 'format_filter': 'mp4,jpg',
          });
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      if (key != _key || selected != kind || selectedProvider != provider) {
        throw const GifSearchException('Search changed. Try again.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw GifSearchException('Check your $providerLabel API key.');
      }
      if (response.statusCode == 429) {
        throw GifSearchException(
          '$providerLabel’s search limit was reached. Try later.',
        );
      }
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        throw GifSearchException('$providerLabel is unavailable. Try again.');
      }
      final json = jsonDecode(response.body);
      if (selectedProvider == GifProvider.giphy) {
        final items = json is Map ? json['data'] : null;
        if (items is! List) {
          throw const GifSearchException(
            'GIPHY returned an unexpected answer.',
          );
        }
        final pagination = json['pagination'];
        final total = pagination is Map ? pagination['total_count'] : null;
        return GifSearchPage(
          [for (final item in items) ?parseGiphyItem(item)],
          nextOffset: items.isNotEmpty && total is num && page * 24 < total
              ? '${page + 1}'
              : null,
        );
      }
      final data = json is Map ? json['data'] : null;
      final items = data is Map ? data['data'] : null;
      if (json is! Map || json['result'] != true || items is! List) {
        throw const GifSearchException('KLIPY returned an unexpected answer.');
      }
      return GifSearchPage([
        for (final item in items) ?parseItem(item, selected),
      ], nextOffset: data['has_next'] == true ? '${page + 1}' : null);
    } on GifSearchException {
      rethrow;
    } catch (_) {
      // Never surface URLs (the key is in their path) or raw server errors.
      throw GifSearchException('Couldn’t search $providerLabel. Try again.');
    }
  }

  static GifSearchResult? parseGiphyItem(Object? value) {
    if (value is! Map || value['id'] is! String || value['images'] is! Map) {
      return null;
    }
    final images = value['images'] as Map;
    Map? image(String name) => images[name] is Map ? images[name] as Map : null;
    final video = image('original');
    final preview = image('fixed_height_still') ?? image('original_still');
    final uri = mediaUri(video?['mp4']);
    if (uri == null || !uri.host.endsWith('.giphy.com')) return null;
    int? integer(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    return GifSearchResult(
      id: 'giphy:${value['id']}',
      title: value['title'] is String ? value['title'] as String : null,
      width: integer(video?['width']),
      height: integer(video?['height']),
      size: integer(video?['mp4_size']),
      remoteVideo: uri,
      remoteThumbnail: mediaUri(preview?['url']),
    );
  }

  @override
  Future<GifMedia> media(
    Room room,
    GifSearchResult result, {
    bool video = false,
  }) async => GifMedia(
    thumbnail: result.remoteThumbnail,
    remoteVideo: video ? result.remoteVideo : null,
  );

  /// Only an explicit Send downloads the original. Room.sendFileEvent's normal
  /// encrypted upload path owns the selected copy, never a search-result cache.
  Future<MatrixVideoFile> download(GifSearchResult result) async {
    final url = result.remoteVideo;
    if (url == null || mediaUri(url.toString()) == null) {
      throw const GifSearchException('This item is unavailable.');
    }
    try {
      final response = await _client
          .send(http.Request('GET', url)..followRedirects = false)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxMediaBytes) {
        throw const GifSearchException('This item cannot be downloaded.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > maxMediaBytes) {
          throw const GifSearchException('This item is too large to send.');
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      if (data.length < 12 ||
          ascii.decode(data.sublist(4, 8), allowInvalid: true) != 'ftyp') {
        throw const GifSearchException('This item is not a valid video.');
      }
      return MatrixVideoFile(
        bytes: data,
        name: result.hasAudio
            ? 'KLIPY clip.mp4'
            : result.id.startsWith('giphy:')
            ? 'GIPHY GIF.mp4'
            : 'KLIPY GIF.mp4',
        mimeType: 'video/mp4',
        width: result.width,
        height: result.height,
      );
    } on GifSearchException {
      rethrow;
    } catch (_) {
      throw const GifSearchException('Couldn’t download this item. Try again.');
    }
  }

  static StickerSendPlan sendPlan(
    Room room,
    GifSearchResult result, {
    int? size,
  }) => StickerSendPlan.forRoom(
    room,
    StickerItem.fromJson({
      // Capability planning only. This placeholder is never sent or fetched.
      'url': 'mxc://placeholder.invalid/klipy',
      'body': 'KLIPY',
      'msgtype': MessageTypes.Video,
      'info': {
        'mimetype': 'video/mp4',
        'w': ?result.width,
        'h': ?result.height,
        'size': ?size,
        if (!result.hasAudio) ...{
          'fi.mau.gif': true,
          'fi.mau.loop': true,
          'fi.mau.autoplay': true,
          'fi.mau.hide_controls': true,
          'fi.mau.no_audio': true,
        },
      },
    }, StickerKind.gif)!,
  );
}
