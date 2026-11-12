// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/ui/notion_inbox_pins.dart';
import 'package:chatloom/personal/ui/notion_inbox_view_chips.dart';
import 'package:chatloom/personal/ui/notion_network_filter.dart';
import 'package:chatloom/personal/ui/notion_network_selector.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

/// Production inbox composition. Account adapters supply rows and real actions.
///
/// Rows are either a prebuilt [rows] list (captures, small fixtures) or a lazy
/// [rowCount]/[rowBuilder] pair; [rowIndexOf] maps a row key to its index so
/// reordering keeps each row's element (avatars do not reload or fade).
/// When the order changes, rows glide to their new places and new rows fade
/// in ([NotionListMotion]); lazy rows name their order in [rowOrder].
class NotionInboxPage extends StatelessWidget {
  final List<Widget> rows;
  final int? rowCount;
  final IndexedWidgetBuilder? rowBuilder;
  final int? Function(Key key)? rowIndexOf;

  /// Identities of the lazy rows in order (for example room IDs); a change
  /// moves the rows. Prebuilt [rows] use their keys.
  final List<Object?>? rowOrder;
  final List<NotionPinnedShortcut> pins;
  final VoidCallback onSettings;

  /// Opens the full-screen search, the one place to find and start chats.
  final VoidCallback onSearch;
  final ValueChanged<String?> onNetworkSelected;
  final List<String> networks;
  final String? selectedNetwork;
  final InboxFilter selectedView;
  final ValueChanged<InboxFilter>? onViewSelected;
  final VoidCallback? onManageNetworks;

  /// "Mark all as read" in the dock's "Show chats" menu (FX-17).
  final VoidCallback? onMarkAllRead;
  final InboxSort sort;
  final ValueChanged<InboxSort>? onSortSelected;

  /// New order of the pin keys after a drag (FX-17); null: pins stay put.
  final Future<void> Function(List<String> keys)? onReorderPins;
  final ScrollController? scrollController;
  final Widget? status;

  /// A one-line status inside the glass header, under the title (for
  /// example "Connecting…"). Grows in and out; null hides it.
  final Widget? headerStatus;
  final bool loading;
  final VoidCallback? onRetryLoading;
  final String? emptyMessage;

  /// Unread chats of the current network selection, on the "Unread" chip.
  final int unreadCount;

  /// Message requests waiting for an answer; the "Requests" chip shows
  /// while there are some (FX-02).
  final int requestCount;
  const NotionInboxPage({
    super.key,
    this.rows = const [],
    this.rowCount,
    this.rowBuilder,
    this.rowIndexOf,
    this.rowOrder,
    required this.pins,
    required this.onSettings,
    required this.onSearch,
    required this.onNetworkSelected,
    required this.networks,
    this.selectedNetwork,
    this.selectedView = InboxFilter.inbox,
    this.onViewSelected,
    this.onManageNetworks,
    this.onMarkAllRead,
    this.sort = InboxSort.latestActivity,
    this.onSortSelected,
    this.onReorderPins,
    this.scrollController,
    this.status,
    this.headerStatus,
    this.loading = false,
    this.onRetryLoading,
    this.emptyMessage,
    this.unreadCount = 0,
    this.requestCount = 0,
  });
  int? _indexOfRow(Key key) {
    final index = rows.indexWhere((row) => row.key == key);
    return index < 0 ? null : index;
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final builder = rowBuilder ?? ((context, index) => rows[index]);
    final unavailable = loading || onRetryLoading != null;
    final count = unavailable
        ? 0
        : rowBuilder == null
        ? rows.length
        : rowCount ?? 0;
    final bottomClearance = safe.bottom + NotionSpace.xl;
    final showPins = !unavailable && pins.isNotEmpty;
    final emptyText =
        emptyMessage ??
        (selectedView == InboxFilter.aside
            ? 'No chats in Aside. Hold a chat and choose Move to Aside.'
            : 'No chats yet. Use Search to find people.');
    // Stable solid chrome keeps the inbox readable and leaves every last row
    // unobscured; the network selector uses the shared anchored popup.
    return BackdropGroup(
      child: Scaffold(
        // No floating navigation covers the last conversation or a snackbar.
        extendBody: false,
        // The first screenful of pins and rows rises in once per page; rows
        // built later by scrolling or filtering appear as they are.
        body: NotionEntranceScope(
          // A chat that moves (new message) glides to its place while the
          // rows it passes slide aside; another view or network, or the end
          // of the first load, swaps the list without motion.
          child: NotionListMotion(
            order:
                rowOrder ??
                (rowBuilder == null
                    ? [for (final row in rows) row.key]
                    : const []),
            epoch: (selectedView, selectedNetwork, loading),
            background: Theme.of(context).scaffoldBackgroundColor,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                PinnedHeaderSliver(
                  child: ColoredBox(
                    color: context.notion.colors.background,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        NotionSpace.inset,
                        safe.top + NotionSpace.xs,
                        NotionSpace.inset,
                        NotionSpace.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Chats',
                                  style: context.notion.typography.title,
                                ),
                              ),
                              _InboxToolbarButton(
                                key: const ValueKey('notion_dock_settings'),
                                label: 'Settings',
                                icon: Icons.settings_outlined,
                                onPressed: onSettings,
                              ),
                              _InboxToolbarButton(
                                key: const ValueKey('inbox_new_message'),
                                label: 'New message',
                                icon: Icons.edit_square,
                                onPressed: unavailable ? null : onSearch,
                              ),
                            ],
                          ),
                          _RetainedReveal(
                            revealOnMount: false,
                            child: headerStatus,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    NotionSpace.inset,
                    NotionSpace.xxs,
                    NotionSpace.inset,
                    NotionSpace.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _InboxSearchButton(
                      onPressed: unavailable ? null : onSearch,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: NotionSpace.page,
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: _InboxNetworkPicker(
                            networks: networks,
                            selectedNetwork: selectedNetwork,
                            selectedView: selectedView,
                            onNetworkSelected: onNetworkSelected,
                            onViewSelected: onViewSelected,
                            onManageNetworks: onManageNetworks,
                            onMarkAllRead: unavailable ? null : onMarkAllRead,
                          ),
                        ),
                        if (onSortSelected != null)
                          _InboxToolbarButton(
                            key: const ValueKey('inbox_sort'),
                            label: 'Sort chats',
                            icon: Icons.sort,
                            onPressed: () async {
                              final choice = await showNotionChoiceSheet<InboxSort>(
                                context,
                                title: 'Sort chats',
                                selected: sort,
                                options: const [
                                  NotionChoice(
                                    InboxSort.latestActivity,
                                    'Latest activity',
                                    subtitle: 'Newest changes first',
                                  ),
                                  NotionChoice(
                                    InboxSort.oldestActivity,
                                    'Oldest activity',
                                    subtitle: 'Oldest changes first',
                                  ),
                                  NotionChoice(
                                    InboxSort.unreadFirst,
                                    'Unread first',
                                    subtitle:
                                        'Unread chats first, then latest activity',
                                  ),
                                ],
                              );
                              if (choice != null && choice.value != sort) {
                                onSortSelected?.call(choice.value);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (status != null)
                  SliverPadding(
                    padding: NotionSpace.page,
                    sliver: SliverToBoxAdapter(child: status),
                  ),
                // Pins grow in and out instead of jumping.
                SliverToBoxAdapter(
                  child: _RetainedReveal(
                    revealOnMount: false,
                    child: showPins
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(
                              NotionSpace.inset,
                              NotionSpace.sm,
                              NotionSpace.inset,
                              0,
                            ),
                            child: NotionEntrance(
                              rise: NotionMotion.riseList,
                              child: NotionPinnedShortcuts(
                                pins: pins,
                                onReorder: onReorderPins,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                // One-tap views (UX-16) instead of a second large title; the
                // same state as the dock's "Show chats" menu.
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    NotionSpace.inset,
                    showPins ? NotionSpace.md : NotionSpace.sm,
                    NotionSpace.inset,
                    NotionSpace.xs,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: NotionInboxViewChips(
                      selected: selectedView,
                      onViewSelected: onViewSelected,
                      unreadCount: unavailable ? 0 : unreadCount,
                      requestCount: unavailable ? 0 : requestCount,
                    ),
                  ),
                ),
                if (loading)
                  SliverPadding(
                    padding: NotionSpace.page,
                    sliver: SliverToBoxAdapter(
                      child: Semantics(
                        label: 'Loading chats',
                        child: ExcludeSemantics(
                          child: NotionSkeleton(
                            child: Column(
                              children: List.filled(
                                _skeletonRows,
                                const NotionSkeletonRow(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!loading && count == 0)
                  SliverToBoxAdapter(
                    child: NotionFadeThrough(
                      alignment: AlignmentDirectional.topCenter,
                      child: NotionEmptyState(
                        key: ValueKey(emptyText),
                        icon: onRetryLoading == null
                            ? Icons.chat_bubble_outline
                            : Icons.storage_outlined,
                        title: onRetryLoading == null
                            ? emptyText
                            : 'Saved chats could not be loaded',
                        message: onRetryLoading == null ? null : emptyText,
                        action: onRetryLoading == null
                            ? null
                            : NotionButton(
                                label: 'Retry',
                                onPressed: onRetryLoading,
                              ),
                      ),
                    ),
                  ),
                _SliverFadeOnChange(
                  signal: (selectedView, selectedNetwork, loading),
                  sliver: SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      NotionSpace.inset,
                      0,
                      NotionSpace.inset,
                      bottomClearance,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final row = builder(context, index);
                          // Same key as the row, so reordering keeps elements
                          // (a GlobalKey keeps its element on its own).
                          final key = row.key;
                          return NotionListMotionItem(
                            key: key is GlobalKey ? null : key,
                            index: index,
                            // The gap belongs to the item, so reorder offsets
                            // include it and highlights never touch.
                            child: Padding(
                              padding: NotionSpace.listItem,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  NotionEntrance(
                                    playKey: row.key,
                                    rise: NotionMotion.riseList,
                                    child: row,
                                  ),
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start:
                                          NotionSize.avatarLg +
                                          NotionSpace.xs +
                                          NotionSpace.sm,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      thickness: .5,
                                      color: context.notion.colors.border,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: count,
                        findChildIndexCallback: rowIndexOf ?? _indexOfRow,
                        // The motion item adds the boundary and semantic
                        // index itself; it must sit directly in the list.
                        addRepaintBoundaries: false,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while the first inbox load runs (about one screenful).
const _skeletonRows = 8;

class _InboxToolbarButton extends StatelessWidget {
  const _InboxToolbarButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: NotionSize.touchTarget,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: NotionSize.iconMd),
      color: context.notion.colors.accent,
    ),
  );
}

/// A real button rather than a fake text field: activates the existing search
/// route, where users can search chats, messages and start a conversation.
class _InboxSearchButton extends StatelessWidget {
  const _InboxSearchButton({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('notion_dock_search'),
    button: true,
    enabled: onPressed != null,
    label: 'Search chats and messages',
    child: Material(
      color: context.notion.colors.surface,
      borderRadius: NotionRadius.smAll,
      child: InkWell(
        onTap: onPressed,
        borderRadius: NotionRadius.smAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: NotionSize.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NotionSpace.sm,
              vertical: NotionSpace.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: NotionSize.iconMd,
                  color: context.notion.colors.textSecondary,
                ),
                const SizedBox(width: NotionSpace.xs),
                Expanded(
                  child: Text(
                    'Search',
                    maxLines: 1,
                    softWrap: false,
                    style: context.notion.typography.body.copyWith(
                      color: context.notion.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _InboxNetworkPicker extends StatefulWidget {
  const _InboxNetworkPicker({
    required this.networks,
    required this.onNetworkSelected,
    required this.selectedView,
    this.selectedNetwork,
    this.onViewSelected,
    this.onManageNetworks,
    this.onMarkAllRead,
  });
  final List<String> networks;
  final String? selectedNetwork;
  final InboxFilter selectedView;
  final ValueChanged<String?> onNetworkSelected;
  final ValueChanged<InboxFilter>? onViewSelected;
  final VoidCallback? onManageNetworks;
  final VoidCallback? onMarkAllRead;
  @override
  State<_InboxNetworkPicker> createState() => _InboxNetworkPickerState();
}

class _InboxNetworkPickerState extends State<_InboxNetworkPicker> {
  final _anchor = GlobalKey();
  bool _expanded = false;
  Future<void> _show() async {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _expanded) return;
    setState(() => _expanded = true);
    try {
      await showNotionNetworkSelector(
        context,
        anchor: Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        ),
        networks: widget.networks,
        selected: widget.selectedNetwork,
        onSelected: widget.onNetworkSelected,
        selectedView: widget.selectedView,
        onViewSelected: widget.onViewSelected,
        onManageNetworks: widget.onManageNetworks,
        onMarkAllRead: widget.onMarkAllRead,
      );
    } finally {
      if (mounted) setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.selectedNetwork == null
        ? 'All networks'
        : notionNetworkLabel(widget.selectedNetwork!);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        key: const ValueKey('notion_dock_network'),
        button: true,
        expanded: _expanded,
        label: 'Show chats, $label',
        child: InkWell(
          key: _anchor,
          onTap: _show,
          borderRadius: NotionRadius.smAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: NotionSize.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NotionSpace.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.notion.typography.callout.copyWith(
                        color: context.notion.colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: NotionSpace.xxs),
                  Icon(
                    Icons.expand_more,
                    size: NotionSize.iconMd,
                    color: context.notion.colors.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps showing the last non-null [child] while it collapses, so a section
/// that goes away (pins, the header status) shrinks out instead of vanishing.
class _RetainedReveal extends StatefulWidget {
  const _RetainedReveal({required this.child, this.revealOnMount = true});

  final Widget? child;
  final bool revealOnMount;

  @override
  State<_RetainedReveal> createState() => _RetainedRevealState();
}

class _RetainedRevealState extends State<_RetainedReveal> {
  Widget? _last;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child != null) _last = child;
    final shown = _last;
    if (shown == null) return const SizedBox.shrink();
    return NotionSizeReveal(
      visible: child != null,
      revealOnMount: widget.revealOnMount,
      // The reveal loosens width; keep sections full width.
      child: SizedBox(width: double.infinity, child: shown),
    );
  }
}

/// Fades the row list in again whenever [signal] changes (another view,
/// network or the end of the first load), instead of a hard cut, from
/// [NotionMotion.refreshFrom] (never blank). Settles at full opacity;
/// nothing under reduced motion.
class _SliverFadeOnChange extends StatefulWidget {
  const _SliverFadeOnChange({required this.signal, required this.sliver});

  final Object signal;
  final Widget sliver;

  @override
  State<_SliverFadeOnChange> createState() => _SliverFadeOnChangeState();
}

class _SliverFadeOnChangeState extends State<_SliverFadeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NotionMotion.medium,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: NotionMotion.standard,
  );
  // Never from 0: an empty first frame flashed the bare page through the
  // glass dock and header.
  late final Animation<double> _opacity = _curve.drive(
    Tween(begin: NotionMotion.refreshFrom, end: 1),
  );

  @override
  void didUpdateWidget(_SliverFadeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signal != widget.signal && !NotionMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
}
