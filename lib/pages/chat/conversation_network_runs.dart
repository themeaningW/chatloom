// SPDX-License-Identifier: AGPL-3.0-or-later

/// A rendered message/album or an omitted timeline row, newest first.
/// Networks must already be canonical. A visible unknown network prevents
/// inventing a transition across history whose source is not known.
class ConversationNetworkItem {
  const ConversationNetworkItem(this.network, {this.visible = true});
  final String? network;
  final bool visible;
}

/// Real network changes, independent of sender, reply, date or bubble grouping.
/// No initial marker is inferred from the edge of the loaded history slice.
Map<int, String> conversationNetworkChanges(
  List<ConversationNetworkItem> rows,
) {
  final changes = <int, String>{};
  String? older;
  for (var i = rows.length - 1; i >= 0; i--) {
    final row = rows[i];
    if (!row.visible) continue;
    final network = row.network;
    if (network != null && older != null && network != older) {
      changes[i] = network;
    }
    older = network;
  }
  return changes;
}
