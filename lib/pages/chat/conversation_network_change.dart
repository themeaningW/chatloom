// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/notion_network_filter.dart';
import 'package:chatloom/personal/ui/notion_network_selector.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';

/// A network-run boundary, separate from the message bubble's grouping.
class ConversationNetworkChange extends StatelessWidget {
  const ConversationNetworkChange({super.key, required this.network});
  final String network;

  @override
  Widget build(BuildContext context) {
    final label = notionNetworkLabel(network);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NotionSpace.xs),
      child: Center(
        child: Semantics(
          label: 'Messages via $label',
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: ExcludeSemantics(
              child: NotionNetworkGlyph(
                network: network,
                size: NotionSize.iconSm,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
