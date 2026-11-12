// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:chatloom/personal/bridge_contact_search_provisioning.dart';
import 'package:chatloom/personal/conversation_classification.dart';
import 'package:chatloom/personal/ui/notion_network_filter.dart';
import 'package:http/http.dart' as http;

typedef BridgeOpenIdToken = ({String token, DateTime expiresAt});

/// Standard mautrix discovery, not a guessed bot-name-to-URL mapping.
/// Discovery is unauthenticated. The Matrix session token stays on the
/// homeserver origin; advertised cross-origin bridges receive only OpenID.
class DiscoveredBridgeProvisioningTransport
    implements BridgeProvisioningTransport, BridgeProvisioningDiscovery {
  DiscoveredBridgeProvisioningTransport({
    required this.httpClient,
    required this.homeserver,
    required this.userId,
    required this.accessToken,
    this.openId,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final http.Client httpClient;
  final Uri homeserver;
  final String userId;
  final String? Function() accessToken;
  final Future<BridgeOpenIdToken> Function()? openId;
  final Duration timeout;
  final DateTime Function() _clock;
  final _routes = <String, Uri>{};
  final _identities = <String, Map>{};
  List<BridgeEndpoint> _bridges = const [];
  Future<List<BridgeEndpoint>>? _discovering;
  DateTime? _discoveredAt;
  BridgeOpenIdToken? _identityToken;
  Future<BridgeOpenIdToken>? _requestingToken;

  DiscoveredBridgeProvisioningTransport withTimeout(Duration value) =>
      DiscoveredBridgeProvisioningTransport(
        httpClient: httpClient,
        homeserver: homeserver,
        userId: userId,
        accessToken: accessToken,
        openId: openId,
        timeout: value,
        clock: _clock,
      );

  static const _sessionChanged = BridgeProvisioningException(
    401,
    errcode: 'M_UNKNOWN_TOKEN',
  );

  String _session() {
    final token = accessToken();
    if (token == null || token.isEmpty) throw _sessionChanged;
    return token;
  }

  void _check(String session) {
    if (accessToken() != session) throw _sessionChanged;
  }

  Iterable<Uri> get _wellKnownUris sync* {
    final colon = userId.indexOf(':');
    final authority = colon < 0 ? '' : userId.substring(colon + 1);
    final server = Uri.tryParse('https://$authority');
    if (server != null &&
        server.host.isNotEmpty &&
        server.userInfo.isEmpty &&
        server.path.isEmpty &&
        !server.hasQuery &&
        !server.hasFragment) {
      yield server.replace(path: '/.well-known/matrix/mautrix');
    }
    final fallback = homeserver.replace(
      path: '/.well-known/matrix/mautrix',
      query: null,
      fragment: null,
    );
    if (server == null ||
        server.host.isEmpty ||
        server.origin != fallback.origin) {
      yield fallback;
    }
  }

  Uri? _bridgeBase(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && uri.origin == homeserver.origin))) {
      return null;
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Uri? _externalWellKnown(Object? value) {
    // The documented entries are server authorities, not arbitrary URLs.
    if (value is! String ||
        value.isEmpty ||
        value.endsWith(':') ||
        RegExp(r'[/\\?#@\s]').hasMatch(value)) {
      return null;
    }
    final server = Uri.tryParse('https://$value');
    if (server == null ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.path.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment ||
        (server.hasPort && (server.port < 1 || server.port > 65535))) {
      return null;
    }
    return server.replace(path: '/.well-known/matrix/mautrix');
  }

  @override
  Future<List<BridgeEndpoint>> discover({bool force = false}) {
    _session();
    if (_discovering case final running?) return running;
    if (!force &&
        _discoveredAt != null &&
        _clock().difference(_discoveredAt!) < const Duration(minutes: 5)) {
      return Future.value(_bridges);
    }
    final request = _discover();
    _discovering = request;
    return request.whenComplete(() => _discovering = null);
  }

  Future<List<BridgeEndpoint>> _discover() async {
    final session = _session();
    final bases = <Uri>{};
    final primary = _wellKnownUris.toList(growable: false);
    final external = <Uri>{};
    Future<void> readWellKnown(Uri uri, {required bool readExternal}) async {
      try {
        // Never attach authentication to discovery or follow an authenticated
        // redirect. Public well-known redirects contain no session token.
        final response = await httpClient.get(uri).timeout(timeout);
        _check(session);
        if (response.statusCode != 200 || response.bodyBytes.length > 262144) {
          return;
        }
        final json = jsonDecode(response.body);
        final entries = json is Map ? json['fi.mau.bridges'] : null;
        if (entries is List) {
          for (final entry in entries) {
            if (bases.length >= 16) break;
            if (_bridgeBase(entry) case final base?) {
              bases.add(base);
            }
          }
        }
        final servers = readExternal && json is Map
            ? json['fi.mau.external_bridge_servers']
            : null;
        if (servers is List) {
          for (final entry in servers) {
            if (external.length >= 8) break;
            if (_externalWellKnown(entry) case final server?) {
              if (!primary.contains(server)) external.add(server);
            }
          }
        }
      } catch (_) {
        _check(session);
      }
    }

    for (final uri in primary) {
      await readWellKnown(uri, readExternal: true);
    }
    // External publications contribute bridges, never further servers.
    for (final uri in external) {
      await readWellKnown(uri, readExternal: false);
    }
    final routes = <String, Uri>{};
    final identities = <String, Map>{};
    final bridges = <String, BridgeEndpoint>{};
    // Keep discovery bounded; other endpoints continue if one is unavailable.
    final candidates = bases.take(16).toList();
    for (var i = 0; i < candidates.length; i += 4) {
      await Future.wait([
        for (final base in candidates.skip(i).take(4))
          () async {
            try {
              final json = await _request(
                base,
                const BridgeProvisioningRequest('GET', '/v3/whoami'),
                session,
              );
              final whoami = BridgeWhoami.fromJson(json);
              if (whoami == null ||
                  !RegExp(r'^@[^:]+:.+$').hasMatch(whoami.bridgeBot)) {
                return;
              }
              final network =
                  canonicalNetwork(whoami.networkId) ??
                  canonicalNetwork(whoami.networkName) ??
                  whoami.networkId.toLowerCase();
              if (network.isEmpty || network == 'matrix') return;
              bridges.putIfAbsent(
                whoami.bridgeBot,
                () => BridgeEndpoint(
                  botId: whoami.bridgeBot,
                  network: network,
                  label: notionNetworkLabel(network),
                ),
              );
              routes.putIfAbsent(whoami.bridgeBot, () => base);
              identities.putIfAbsent(whoami.bridgeBot, () => json as Map);
            } catch (_) {
              _check(session);
            }
          }(),
      ]);
    }
    _check(session);
    _routes
      ..clear()
      ..addAll(routes);
    _identities
      ..clear()
      ..addAll(identities);
    _bridges = List.unmodifiable(bridges.values);
    _discoveredAt = _clock();
    return _bridges;
  }

  Future<String> _authorization(Uri base, String session) async {
    if (base.origin == homeserver.origin) return 'Bearer $session';
    final create = openId;
    if (create == null) throw _sessionChanged;
    var identity = _identityToken;
    if (identity == null ||
        !identity.expiresAt.isAfter(_clock().add(const Duration(seconds: 5)))) {
      final pending = _requestingToken ??= create();
      try {
        identity = await pending;
        _check(session);
        if (identity.token.isEmpty || !identity.expiresAt.isAfter(_clock())) {
          throw _sessionChanged;
        }
        _identityToken = identity;
      } catch (_) {
        throw _sessionChanged;
      } finally {
        if (identical(_requestingToken, pending)) _requestingToken = null;
      }
    }
    _check(session);
    return 'Bearer openid:${identity.token}';
  }

  Future<Object?> _request(
    Uri base,
    BridgeProvisioningRequest request,
    String session,
  ) async {
    final authorization = await _authorization(base, session);
    _check(session);
    final uri = base.replace(
      path: '${base.path}/_matrix/provision${request.path}',
      queryParameters: {'user_id': userId, ...request.query},
    );
    final outgoing = http.Request(request.method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = authorization
      ..headers['Accept'] = 'application/json';
    if (request.body != null) {
      outgoing
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(request.body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(outgoing).timeout(timeout),
      ).timeout(timeout);
    } catch (_) {
      _check(session);
      throw const BridgeProvisioningException(0);
    }
    _check(session);
    Object? json;
    try {
      json = jsonDecode(response.body);
    } catch (_) {
      throw BridgeProvisioningException(response.statusCode);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    final code = json is Map ? json['errcode'] : null;
    throw BridgeProvisioningException(
      response.statusCode,
      errcode:
          code is String &&
              RegExp(r'^(M_[A-Z0-9_]+|FI\.MAU\.[A-Z0-9_.]+)$').hasMatch(code)
          ? code
          : null,
    );
  }

  @override
  Future<Object?> send(
    BridgeEndpoint bridge,
    BridgeProvisioningRequest request,
  ) async {
    final session = _session();
    await discover();
    _check(session);
    final base = _routes[bridge.botId];
    if (base == null) {
      throw const BridgeProvisioningException(
        503,
        errcode: 'CHATLOOM_BRIDGE_NOT_PUBLISHED',
        message: 'Your server has not published this bridge API.',
      );
    }
    if (request.method == 'GET' && request.path == '/v3/whoami') {
      return _identities.remove(bridge.botId) ??
          _request(base, request, session);
    }
    return _request(base, request, session);
  }

  @override
  String toString() => 'DiscoveredBridgeProvisioningTransport(private)';
}
