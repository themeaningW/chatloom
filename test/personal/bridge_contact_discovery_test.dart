// SPDX-License-Identifier: AGPL-3.0-or-later
// Synthetic servers and credentials only. No request leaves these fixtures.
import 'dart:async';
import 'dart:convert';

import 'package:chatloom/personal/bridge_contact_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _wa = BridgeEndpoint(
  botId: '@whatsappbot:example.invalid',
  network: 'whatsapp',
  label: 'WhatsApp',
);
const _ig = BridgeEndpoint(
  botId: '@instagrambot:example.invalid',
  network: 'instagram',
  label: 'Instagram',
);

Map<String, Object?> _identity(BridgeEndpoint bridge) => {
  'bridge_bot': bridge.botId,
  'network': {'network_id': bridge.network, 'displayname': bridge.label},
  'logins': [
    {'id': 'fictional-login', 'name': 'Fixture', 'state_event': 'CONNECTED'},
  ],
};
http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

void main() {
  DiscoveredBridgeProvisioningTransport transport(
    Future<http.Response> Function(http.Request) handler, {
    String? Function()? token,
    Future<BridgeOpenIdToken> Function()? openId,
  }) => DiscoveredBridgeProvisioningTransport(
    httpClient: MockClient(handler),
    homeserver: Uri.parse('https://matrix.example.invalid'),
    userId: '@fixture:example.invalid',
    accessToken: token ?? () => 'synthetic-session',
    openId: openId,
  );

  test(
    'discovers zero-portal bridges, binds bot identity and routes capabilities',
    () async {
      final calls = <http.Request>[];
      final service = transport((request) async {
        calls.add(request);
        if (request.url.path == '/.well-known/matrix/mautrix') {
          expect(request.headers['Authorization'], isNull);
          return _json({
            'fi.mau.bridges': [
              'https://matrix.example.invalid/bridges/wa',
              'https://matrix.example.invalid/bridges/instagram',
            ],
          });
        }
        expect(request.headers['Authorization'], 'Bearer synthetic-session');
        expect(request.followRedirects, isFalse);
        expect(
          request.url.queryParameters['user_id'],
          '@fixture:example.invalid',
        );
        final bridge = request.url.path.contains('/instagram/') ? _ig : _wa;
        if (request.url.path.endsWith('/whoami')) {
          return _json(_identity(bridge));
        }
        if (request.url.path.endsWith('/capabilities')) {
          return _json({
            'resolve_identifier': {
              'create_dm': true,
              'contact_list': bridge == _wa,
              'search': bridge == _ig,
            },
          });
        }
        if (request.url.path.endsWith('/contacts')) {
          return _json({'contacts': []});
        }
        if (request.url.path.endsWith('/search_users')) {
          expect(jsonDecode(request.body), {'query': 'Fictional person'});
          return _json({'results': []});
        }
        throw StateError('Unexpected fixture request');
      });
      final directory = BridgeDirectory(BridgeProvisioningApi(service));
      addTearDown(directory.dispose);
      await directory.probe(const []);
      expect(
        directory.discoveredBridges.map((b) => b.botId),
        unorderedEquals([_wa.botId, _ig.botId]),
      );
      expect(directory.stateOf(_wa).status, BridgeRemoteStatus.ready);
      expect(directory.stateOf(_wa).capabilities.contactList, isTrue);
      expect(directory.stateOf(_ig).capabilities.search, isTrue);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await directory.loadContacts([_wa]);
      await directory.searchUsers(_ig, 'Fictional person');
      expect(calls.where((r) => r.method == 'POST').length, 1);
      expect(calls.any((r) => r.url.path.contains('create_dm')), isFalse);
    },
  );

  test(
    'advertised cross-origin bridge gets OpenID, never the Matrix session',
    () async {
      var identityRequests = 0;
      final service = transport(
        (request) async {
          if (request.url.path == '/.well-known/matrix/mautrix') {
            expect(request.headers['Authorization'], isNull);
            return _json({
              'fi.mau.bridges': ['https://bridges.example.invalid/meta'],
            });
          }
          expect(request.url.host, 'bridges.example.invalid');
          expect(
            request.headers['Authorization'],
            'Bearer openid:synthetic-identity',
          );
          if (request.url.path.endsWith('/whoami')) {
            return _json(_identity(_ig));
          }
          return _json({'results': []});
        },
        openId: () async {
          identityRequests++;
          return (
            token: 'synthetic-identity',
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          );
        },
      );
      await service.discover();
      await service.send(
        _ig,
        const BridgeProvisioningRequest(
          'POST',
          '/v3/search_users',
          body: {'query': 'Fixture'},
        ),
      );
      expect(identityRequests, 1);
    },
  );

  test(
    'external-only publication discovers once without following nested servers',
    () async {
      final calls = <http.Request>[];
      final service = transport(
        (request) async {
          calls.add(request);
          if (request.url.path == '/.well-known/matrix/mautrix') {
            expect(request.headers['Authorization'], isNull);
            if (request.url.host == 'external.example.invalid') {
              expect(request.url.scheme, 'https');
              expect(request.url.port, 8448);
              return _json({
                'fi.mau.bridges': ['https://external.example.invalid:8448/ig'],
                'fi.mau.external_bridge_servers': ['nested.example.invalid'],
              });
            }
            return _json({
              'fi.mau.external_bridge_servers': [
                'external.example.invalid:8448',
                'external.example.invalid:8448',
              ],
            });
          }
          expect(request.url.host, 'external.example.invalid');
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['Authorization'],
            'Bearer openid:synthetic-identity',
          );
          if (request.url.path.endsWith('/whoami')) {
            return _json(_identity(_ig));
          }
          return _json({'results': []});
        },
        openId: () async => (
          token: 'synthetic-identity',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
      );
      expect(await service.discover(), [_ig]);
      await service.send(
        _ig,
        const BridgeProvisioningRequest(
          'POST',
          '/v3/search_users',
          body: {'query': 'Fixture'},
        ),
      );
      final discoveryCalls = calls.where(
        (request) => request.url.path == '/.well-known/matrix/mautrix',
      );
      expect(discoveryCalls.map((request) => request.url.host), [
        'example.invalid',
        'matrix.example.invalid',
        'external.example.invalid',
      ]);
      expect(
        calls.any((request) => request.url.host == 'nested.example.invalid'),
        isFalse,
      );
    },
  );

  test(
    'external discovery rejects URLs and caps servers and bridge bases',
    () async {
      final calls = <http.Request>[];
      final service = transport(
        (request) async {
          calls.add(request);
          if (request.url.path == '/.well-known/matrix/mautrix') {
            expect(request.headers['Authorization'], isNull);
            if (request.url.host.startsWith('external')) {
              return _json({
                'fi.mau.bridges': [
                  for (var i = 0; i < 4; i++)
                    'https://${request.url.host}/bridge$i',
                ],
              });
            }
            return _json({
              'fi.mau.external_bridge_servers': [
                'http://http.example.invalid',
                'https://url.example.invalid',
                'user:password@credentials.example.invalid',
                'path.example.invalid/bridge',
                'query.example.invalid?query=true',
                'fragment.example.invalid#fragment',
                'port.example.invalid:',
                'port.example.invalid:65536',
                ' spaced.example.invalid',
                for (var i = 0; i < 12; i++) 'external$i.example.invalid',
              ],
            });
          }
          expect(
            request.headers['Authorization'],
            'Bearer openid:synthetic-identity',
          );
          return _json(_identity(_ig));
        },
        openId: () async => (
          token: 'synthetic-identity',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
      );
      await service.discover();
      final externalReads = calls.where(
        (request) =>
            request.url.path == '/.well-known/matrix/mautrix' &&
            request.url.host.startsWith('external'),
      );
      expect(externalReads, hasLength(8));
      expect(
        calls.where((request) => request.url.path.endsWith('/whoami')),
        hasLength(16),
      );
      expect(
        calls.every(
          (request) =>
              request.url.host == 'example.invalid' ||
              request.url.host == 'matrix.example.invalid' ||
              RegExp(
                r'^external[0-7]\.example\.invalid$',
              ).hasMatch(request.url.host),
        ),
        isTrue,
      );
    },
  );

  test(
    'authenticated redirect responses are rejected without forwarding tokens',
    () async {
      final calls = <http.Request>[];
      final service = transport((request) async {
        calls.add(request);
        if (request.url.path == '/.well-known/matrix/mautrix') {
          return _json({
            'fi.mau.bridges': ['https://matrix.example.invalid/wa'],
          });
        }
        expect(request.url.host, 'matrix.example.invalid');
        expect(request.headers['Authorization'], 'Bearer synthetic-session');
        expect(request.followRedirects, isFalse);
        if (request.url.path.endsWith('/whoami')) {
          return _json(_identity(_wa));
        }
        return http.Response(
          '{}',
          302,
          headers: {'location': 'https://redirect.example.invalid/collect'},
        );
      });
      expect(await service.discover(), [_wa]);
      await expectLater(
        service.send(
          _wa,
          const BridgeProvisioningRequest('GET', '/v3/contacts'),
        ),
        throwsA(
          isA<BridgeProvisioningException>().having(
            (error) => error.status,
            'status',
            302,
          ),
        ),
      );
      expect(
        calls.any((request) => request.url.host == 'redirect.example.invalid'),
        isFalse,
      );
    },
  );

  test(
    'missing publication does not guess endpoints or forward authentication',
    () async {
      final calls = <http.Request>[];
      final service = transport((request) async {
        calls.add(request);
        expect(request.headers['Authorization'], isNull);
        return http.Response('Not found', 404);
      });
      expect(await service.discover(), isEmpty);
      await expectLater(
        service.send(
          _wa,
          const BridgeProvisioningRequest('GET', '/v3/contacts'),
        ),
        throwsA(isA<BridgeProvisioningException>()),
      );
      expect(
        calls.every((r) => r.url.path == '/.well-known/matrix/mautrix'),
        isTrue,
      );
    },
  );

  test(
    'foreign bot identity cannot receive a request intended for another bridge',
    () async {
      final paths = <String>[];
      final service = transport((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/.well-known/matrix/mautrix') {
          return _json({
            'fi.mau.bridges': ['https://matrix.example.invalid/one-bridge'],
          });
        }
        return _json(_identity(_ig));
      });
      await expectLater(
        service.send(
          _wa,
          const BridgeProvisioningRequest('POST', '/v3/create_dm/fixture'),
        ),
        throwsA(isA<BridgeProvisioningException>()),
      );
      expect(paths.any((path) => path.contains('create_dm')), isFalse);
    },
  );

  test(
    'logout while discovery is pending rejects results and later requests',
    () async {
      String? token = 'synthetic-session';
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final service = transport((request) async {
        if (request.url.path == '/.well-known/matrix/mautrix') {
          return _json({
            'fi.mau.bridges': ['https://matrix.example.invalid/wa'],
          });
        }
        if (!started.isCompleted) started.complete();
        return response.future;
      }, token: () => token);
      final pending = service.discover();
      await started.future;
      token = null;
      response.complete(_json(_identity(_wa)));
      await expectLater(pending, throwsA(isA<BridgeProvisioningException>()));
      await expectLater(
        service.send(
          _wa,
          const BridgeProvisioningRequest('GET', '/v3/contacts'),
        ),
        throwsA(isA<BridgeProvisioningException>()),
      );
    },
  );

  test(
    'force refresh replaces routes rather than retaining removed endpoints',
    () async {
      var published = true;
      var discoveryReads = 0;
      final service = transport((request) async {
        if (request.url.path == '/.well-known/matrix/mautrix') {
          discoveryReads++;
          return _json({
            'fi.mau.bridges': [
              if (published) 'https://matrix.example.invalid/wa',
            ],
          });
        }
        return _json(_identity(_wa));
      });
      expect(await service.discover(), hasLength(1));
      published = false;
      expect(await service.discover(), hasLength(1));
      expect(await service.discover(force: true), isEmpty);
      expect(discoveryReads, 4); // Account authority and homeserver origin.
      await expectLater(
        service.send(
          _wa,
          const BridgeProvisioningRequest('GET', '/v3/contacts'),
        ),
        throwsA(isA<BridgeProvisioningException>()),
      );
    },
  );

  test(
    'expired session suppresses cached contact state and discovery',
    () async {
      var current = true;
      final directory = BridgeDirectory.disabled('Fixture');
      addTearDown(directory.dispose);
      final active = BridgeDirectory(null, sessionCurrent: () => current);
      addTearDown(active.dispose);
      active.stateOf(_wa).contacts = [
        const BridgeRemoteContact(
          BridgeContact(id: 'fixture', name: 'Fictional'),
          null,
        ),
      ];
      current = false;
      expect(active.stateOf(_wa).contacts, isNull);
      expect(active.discoveredBridges, isEmpty);
    },
  );
}
