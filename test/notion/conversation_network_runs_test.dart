// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/pages/chat/conversation_network_runs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = ConversationNetworkItem('messenger');
  const b = ConversationNetworkItem('whatsapp');
  test('a loaded edge and a same-network run need no repeated marker', () {
    expect(conversationNetworkChanges([]), isEmpty);
    expect(conversationNetworkChanges([a]), isEmpty);
    expect(conversationNetworkChanges([a, a, a, a]), isEmpty);
  });
  test('newest-first A B A chronology marks only the actual changes', () {
    expect(conversationNetworkChanges([a, a, b, b, a, a]), {
      3: 'whatsapp',
      1: 'messenger',
    });
  });
  test('hidden album members and service rows never own or split a run', () {
    expect(
      conversationNetworkChanges([
        a,
        const ConversationNetworkItem('messenger', visible: false),
        const ConversationNetworkItem('whatsapp', visible: false),
        b,
      ]),
      {0: 'messenger'},
    );
    expect(
      conversationNetworkChanges([
        a,
        const ConversationNetworkItem('whatsapp', visible: false),
        a,
      ]),
      isEmpty,
    );
  });
  test('unknown visible history never implies a source change', () {
    expect(
      conversationNetworkChanges([a, const ConversationNetworkItem(null), b]),
      isEmpty,
    );
  });
  test('loading older same-network history does not add a marker', () {
    expect(conversationNetworkChanges([a, a]), isEmpty);
    expect(conversationNetworkChanges([a, a, a]), isEmpty);
    expect(conversationNetworkChanges([a, a, b]), {1: 'messenger'});
  });
}
