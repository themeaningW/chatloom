// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/chat_label_sheets.dart';
import 'package:chatloom/personal/ui/notion_network_filter.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

/// The one-tap views above the inbox list (UX-16; Messenger's "All · Unread
/// · Groups" chips, Telegram's folder tabs).
const notionInboxChipViews = [
  InboxFilter.inbox,
  InboxFilter.unread,
  InboxFilter.groups,
  InboxFilter.aside,
];

String notionInboxChipLabel(InboxFilter view) =>
    view == InboxFilter.inbox ? 'All' : inboxViewLabel(view);

/// A row of in-content pills (opaque, never glass: they scroll with the
/// list). They select the same view as the dock's "Show chats" menu, through
/// [onViewSelected]; the page keeps no view state of its own. A view chosen
/// elsewhere (Ignored, Archive, …) shows as one more selected chip so the
/// list stays labelled. The counts roll when they change; a badge that
/// appears after the first frame pops in (the first screen stays calm).
class NotionInboxViewChips extends StatefulWidget {
  const NotionInboxViewChips({
    super.key,
    required this.selected,
    required this.onViewSelected,
    this.unreadCount = 0,
    this.requestCount = 0,
    this.labels = const [],
    this.selectedLabel,
    this.onLabelSelected,
    this.onManageLabels,
  });

  final InboxFilter selected;
  final ValueChanged<InboxFilter>? onViewSelected;
  final List<PersonalLabel> labels;
  final String? selectedLabel;
  final ValueChanged<String>? onLabelSelected;
  final VoidCallback? onManageLabels;

  /// Unread chats of the current network selection; shown on "Unread".
  final int unreadCount;

  /// Message requests waiting for an answer (Instagram, Messenger): the
  /// "Requests" chip appears only while there are some (FX-02).
  final int requestCount;

  @override
  State<NotionInboxViewChips> createState() => _NotionInboxViewChipsState();
}

class _NotionInboxViewChipsState extends State<NotionInboxViewChips> {
  final _scroll = ScrollController();
  final _selectedLabelAnchor = GlobalKey();

  /// False during the first frame: badges present from the start appear as
  /// they are, later ones pop in.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settled = true);
    _revealSelectedLabel();
  }

  @override
  void didUpdateWidget(covariant NotionInboxViewChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        widget.selectedLabel != oldWidget.selectedLabel) {
      _revealSelectedLabel();
    }
  }

  void _revealSelectedLabel() {
    if (widget.selected != InboxFilter.label) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _selectedLabelAnchor.currentContext?.findRenderObject();
      if (target != null) _scroll.position.ensureVisible(target, alignment: .5);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final onViewSelected = widget.onViewSelected;
    final unreadCount = widget.unreadCount;
    final requestCount = widget.requestCount;
    final palette = context.notion.palette;
    final chips = [
      ...notionInboxChipViews,
      if (requestCount > 0) InboxFilter.requests,
    ];
    final views = [
      ...chips,
      if (!chips.contains(selected) && selected != InboxFilter.label) selected,
    ];
    return Semantics(
      container: true,
      label: 'Views',
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (index, view) in views.indexed) ...[
                    if (index > 0) const SizedBox(width: NotionSpace.xs),
                    NotionGlassPill(
                      compact: true,
                      key: ValueKey('notion_inbox_chip_${view.name}'),
                      label: notionInboxChipLabel(view),
                      selected: view == selected,
                      trailing: view == InboxFilter.requests && requestCount > 0
                          ? Semantics(
                              label: '$requestCount waiting',
                              child: ExcludeSemantics(
                                child: NotionAnimatedCount(
                                  count: requestCount,
                                  style: context.notion.typography.captionMuted,
                                ),
                              ),
                            )
                          : view == InboxFilter.unread && unreadCount > 0
                          ? NotionPop(
                              trigger: unreadCount,
                              playOnMount: _settled,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NotionSpace.xxs,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: palette.accentFill,
                                  borderRadius: NotionRadius.pillAll,
                                ),
                                child: Semantics(
                                  label: '$unreadCount unread',
                                  child: ExcludeSemantics(
                                    child: NotionAnimatedCount(
                                      count: unreadCount,
                                      format: (n) => n > 99 ? '99+' : '$n',
                                      style: NotionType.caption.copyWith(
                                        color: palette.onAccentFill,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : null,
                      onPressed: onViewSelected == null
                          ? null
                          : () {
                              if (view != selected) onViewSelected(view);
                            },
                    ),
                  ],
                  for (final label in widget.labels) ...[
                    const SizedBox(width: NotionSpace.xs),
                    KeyedSubtree(
                      key:
                          selected == InboxFilter.label &&
                              widget.selectedLabel == label.id
                          ? _selectedLabelAnchor
                          : null,
                      child: NotionGlassPill(
                        compact: true,
                        key: ValueKey('notion_label_chip:${label.id}'),
                        label: label.name,
                        selected:
                            selected == InboxFilter.label &&
                            widget.selectedLabel == label.id,
                        trailing: ChatLabelGlyph(label),
                        onPressed: widget.onLabelSelected == null
                            ? null
                            : () => widget.onLabelSelected!(label.id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.onManageLabels != null)
            NotionIconButton(
              icon: Icons.label_outline,
              label: 'Labels',
              onPressed: widget.onManageLabels,
            ),
        ],
      ),
    );
  }
}
