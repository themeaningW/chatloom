// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:chatloom/pages/chat/conversation_source.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';

import 'public_gif_search.dart';
import 'sticker_panel.dart';

Future<void> showExpandedStickerPanel(
  BuildContext context,
  ConversationComposerHost host, {
  ValueChanged<ModalRoute<dynamic>?>? onRoute,
}) => showNotionSheet<void>(
  context: context,
  builder: (context) {
    onRoute?.call(ModalRoute.of(context));
    return ExpandedStickerPanel(host: host);
  },
);

/// A tall GIF browser with results above Search and the system keyboard.
/// The field and results keep their state through every keyboard inset frame.
class ExpandedStickerPanel extends StatefulWidget {
  const ExpandedStickerPanel({
    super.key,
    required this.host,
    this.gifSource,
    this.loadGifCredentials = true,
  });

  final ConversationComposerHost host;
  final PublicGifSearch? gifSource;
  final bool loadGifCredentials;

  @override
  State<ExpandedStickerPanel> createState() => _ExpandedStickerPanelState();
}

class _ExpandedStickerPanelState extends State<ExpandedStickerPanel> {
  final _searchFocus = FocusNode(debugLabel: 'expanded media search');
  late StickerPanelTab _tab = StickerPanel.lastTab;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final available = math.min(
        media.size.height * NotionComposerPanelSize.expandedScreenFraction,
        constraints.maxHeight,
      );
      final keyboard = media.viewInsets.bottom.clamp(0.0, available);
      final height = math.max(0.0, available - keyboard);
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          key: const ValueKey('expanded-media-panel'),
          height: height,
          child: Column(
            children: [
              if (height >= NotionComposerPanelSize.compactHeaderThreshold)
                SizedBox(
                  height: NotionSize.touchTarget,
                  child: Row(
                    children: [
                      NotionIconButton(
                        icon: Icons.close,
                        label: 'Close media search',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _tab.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.notion.typography.headline,
                        ),
                      ),
                      const SizedBox(width: NotionSize.touchTarget),
                    ],
                  ),
                ),
              Expanded(
                child: StickerPanel(
                  host: widget.host,
                  searchFocus: _searchFocus,
                  gifSource: widget.gifSource,
                  loadGifCredentials: widget.loadGifCredentials,
                  expandedGifs: true,
                  onTabChanged: (tab) => setState(() => _tab = tab),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
