// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

import 'package:chatloom/personal/ui/notion_network_filter.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';

String? _networkGlyphKey(String? network) => switch (network?.toLowerCase()) {
  'facebookgo' || 'facebook' => 'messenger',
  'instagramgo' => 'instagram',
  final value => value,
};

IconData notionNetworkIcon(String? network) =>
    switch (_networkGlyphKey(network)) {
      null => Icons.hub_outlined,
      'slack' => Icons.tag,
      'instagram' => Icons.camera_alt_outlined,
      'telegram' => Icons.send_outlined,
      'whatsapp' ||
      'messenger' ||
      'facebook' ||
      'signal' => Icons.chat_bubble_outline,
      'discord' => Icons.headset_mic_outlined,
      'sms' || 'imessage' => Icons.sms_outlined,
      _ => Icons.language_outlined,
    };

/// Restrained monochrome identifiers, with the actual network kept in text.
class NotionNetworkGlyph extends StatelessWidget {
  final String? network;
  final double size;
  const NotionNetworkGlyph({super.key, this.network, this.size = 24});
  @override
  Widget build(BuildContext context) {
    final glyph = _networkGlyphKey(network);
    // Vivid intensity draws the mark in its brand colour; otherwise it
    // follows the surrounding icon colour (monochrome).
    final brand = context.notion.palette.network(glyph);
    if (![
      'whatsapp',
      'slack',
      'instagram',
      'messenger',
      'facebook',
    ].contains(glyph)) {
      return Icon(notionNetworkIcon(network), size: size, color: brand);
    }
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _NetworkGlyphPainter(
          glyph!,
          brand ?? Theme.of(context).colorScheme.onSurface,
          Theme.of(context).colorScheme.surfaceContainer,
        ),
      ),
    );
  }
}

class _NetworkGlyphPainter extends CustomPainter {
  final String network;
  final Color color;
  final Color background;
  const _NetworkGlyphPainter(this.network, this.color, this.background);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (network == 'slack') {
      stroke.strokeWidth = 5;
      for (final endpoints in [
        [const Offset(13, 3), const Offset(13, 14)],
        [const Offset(21, 18), const Offset(21, 29)],
        [const Offset(18, 13), const Offset(29, 13)],
        [const Offset(3, 21), const Offset(14, 21)],
      ]) {
        canvas.drawLine(endpoints[0], endpoints[1], stroke);
      }
      final dot = Paint()..color = color;
      for (final center in [
        const Offset(5, 13),
        const Offset(21, 5),
        const Offset(27, 21),
        const Offset(13, 27),
      ]) {
        canvas.drawCircle(center, 2.5, dot);
      }
    } else if (network == 'instagram') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 3, 26, 26),
          const Radius.circular(7),
        ),
        stroke,
      );
      canvas.drawCircle(const Offset(16, 16), 6, stroke);
      canvas.drawCircle(const Offset(24, 8), 1.2, Paint()..color = color);
    } else {
      final filled = network == 'messenger' || network == 'facebook';
      final outline = Path()
        ..moveTo(5, 24)
        ..lineTo(3, 29)
        ..lineTo(10, 27)
        ..arcTo(const Rect.fromLTWH(3, 2, 26, 26), 2.05, -5.75, false)
        ..close();
      canvas.drawPath(outline, filled ? (Paint()..color = color) : stroke);
      if (filled) {
        final bolt = Path()
          ..moveTo(8, 20)
          ..lineTo(15, 11)
          ..lineTo(19, 15)
          ..lineTo(25, 10)
          ..lineTo(18, 21)
          ..lineTo(14, 17)
          ..close();
        canvas.drawPath(bolt, Paint()..color = background);
      } else {
        final phone = Path()
          ..moveTo(11, 8)
          ..lineTo(9, 10)
          ..quadraticBezierTo(8, 15, 16, 22)
          ..quadraticBezierTo(21, 26, 24, 20)
          ..lineTo(19, 17)
          ..lineTo(17, 19)
          ..quadraticBezierTo(12, 16, 12, 13)
          ..lineTo(14, 12)
          ..close();
        canvas.drawPath(phone, Paint()..color = color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NetworkGlyphPainter oldDelegate) =>
      oldDelegate.network != network ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}

/// Production selector; [anchor] is in global logical coordinates. The modal
/// route's barrier consumes the outside tap.
Future<String?> showNotionNetworkSelector(
  BuildContext context, {
  required Rect anchor,
  required List<String> networks,
  required String? selected,
  required ValueChanged<String?> onSelected,
  InboxFilter selectedView = InboxFilter.inbox,
  ValueChanged<InboxFilter>? onViewSelected,
  VoidCallback? onManageNetworks,
  VoidCallback? onMarkAllRead,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final window = overlay?.size ?? MediaQuery.sizeOf(context);
  // The inbox header and the legacy bottom dock both provide global anchors.
  // Convert both corners into the same overlay space used to lay out the menu;
  // a navigator may itself be offset or scaled inside a desktop/tablet pane.
  final rect = overlay == null
      ? anchor
      : Rect.fromPoints(
          overlay.globalToLocal(anchor.topLeft),
          overlay.globalToLocal(anchor.bottomRight),
        );
  final fromTop = rect.center.dy < window.height / 2;
  final origin = Offset(rect.center.dx, fromTop ? rect.bottom : rect.top);
  return showNotionPopover<String>(
    context: context,
    alignment: window.isEmpty
        ? Alignment.bottomRight
        : Alignment(
            (origin.dx / window.width * 2 - 1).clamp(-1.0, 1.0),
            (origin.dy / window.height * 2 - 1).clamp(-1.0, 1.0),
          ),
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final padding = MediaQuery.paddingOf(context);
        final insets = MediaQuery.viewInsetsOf(context);
        final left = math.max(padding.left, insets.left) + NotionSpace.md;
        final top = math.max(padding.top, insets.top) + NotionSpace.md;
        final safe = Rect.fromLTWH(
          left,
          top,
          math.max(
            0.0,
            constraints.maxWidth -
                left -
                math.max(padding.right, insets.right) -
                NotionSpace.md,
          ),
          math.max(
            0.0,
            constraints.maxHeight -
                top -
                math.max(padding.bottom, insets.bottom) -
                NotionSpace.md,
          ),
        );
        final width = math.min(safe.width, scale > 1.4 ? 300.0 : 196.0);
        final above = (rect.top - NotionSpace.xs - safe.top).clamp(
          0.0,
          safe.height,
        );
        final below = (safe.bottom - rect.bottom - NotionSpace.xs).clamp(
          0.0,
          safe.height,
        );
        final space = math.max(above, below);
        // In a very short viewport, overlap the anchor rather than leave no
        // reachable row. Otherwise keep the menu entirely on the roomier side.
        final maxHeight = space < NotionSize.touchTarget ? safe.height : space;
        return CustomSingleChildLayout(
          delegate: _NetworkSelectorLayout(
            anchor: rect,
            safe: safe,
            width: width,
            maxHeight: maxHeight,
            preferAbove: above > below,
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Show chats',
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      Navigator.of(context).pop();
                      return null;
                    },
                  ),
                },
                child: Focus(
                  autofocus: true,
                  child: NotionGlassPanel(
                    key: const ValueKey('notion_network_selector_panel'),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: SingleChildScrollView(
                        key: const ValueKey('notion_network_selector_scroll'),
                        child: NotionNetworkMenu(
                          networks: networks,
                          selected: selected,
                          selectedView: selectedView,
                          onViewSelected: onViewSelected == null
                              ? null
                              : (view) {
                                  Navigator.of(context).pop();
                                  onViewSelected(view);
                                },
                          onManageNetworks: onManageNetworks == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  onManageNetworks();
                                },
                          onMarkAllRead: onMarkAllRead == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  onMarkAllRead();
                                },
                          onSelected: (network) {
                            onSelected(network);
                            Navigator.of(context).pop(network);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Uses the menu's actual height so short menus stay beside their trigger and
/// long menus scroll within the safe viewport, above a dock or below a header.
class _NetworkSelectorLayout extends SingleChildLayoutDelegate {
  const _NetworkSelectorLayout({
    required this.anchor,
    required this.safe,
    required this.width,
    required this.maxHeight,
    required this.preferAbove,
  });

  final Rect anchor;
  final Rect safe;
  final double width;
  final double maxHeight;
  final bool preferAbove;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: maxHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = anchor.top - NotionSpace.xs - childSize.height;
    final below = anchor.bottom + NotionSpace.xs;
    final fitsAbove = above >= safe.top;
    final fitsBelow = below + childSize.height <= safe.bottom;
    final top = fitsAbove && (preferAbove || !fitsBelow)
        ? above
        : fitsBelow
        ? below
        : above;
    final left = anchor.center.dx > size.width / 2
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(
      left.clamp(safe.left, math.max(safe.left, safe.right - childSize.width)),
      top.clamp(safe.top, math.max(safe.top, safe.bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_NetworkSelectorLayout old) =>
      old.anchor != anchor ||
      old.safe != safe ||
      old.width != width ||
      old.maxHeight != maxHeight ||
      old.preferAbove != preferAbove;
}

class NotionNetworkMenu extends StatelessWidget {
  final List<String> networks;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final InboxFilter selectedView;
  final ValueChanged<InboxFilter>? onViewSelected;
  final VoidCallback? onManageNetworks;

  /// Marks every chat of the current view and network read (FX-17,
  /// Telegram's folder "Mark as read").
  final VoidCallback? onMarkAllRead;
  const NotionNetworkMenu({
    super.key,
    required this.networks,
    required this.selected,
    required this.onSelected,
    this.selectedView = InboxFilter.inbox,
    this.onViewSelected,
    this.onManageNetworks,
    this.onMarkAllRead,
  });
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    // Rows settle in one after another while the popover grows.
    children: NotionEntrance.stagger(
      _children(context),
      rise: NotionMotion.rise / 2,
      afterRoute: false,
    ),
  );

  List<Widget> _children(BuildContext context) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
      child: Text(
        'Show chats',
        style: NotionTokens.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    if (onViewSelected != null) ...[
      for (final view in [
        InboxFilter.inbox,
        InboxFilter.groups,
        InboxFilter.aside,
        InboxFilter.ignored,
        InboxFilter.technical,
      ])
        NotionGlassMenuRow(
          selected: selectedView == view,
          title: view == InboxFilter.inbox ? 'Main list' : inboxViewLabel(view),
          leading: Icon(switch (view) {
            InboxFilter.groups => Icons.group_outlined,
            InboxFilter.aside => Icons.move_to_inbox_outlined,
            InboxFilter.ignored => Icons.visibility_off_outlined,
            InboxFilter.technical => Icons.build_outlined,
            _ => Icons.chat_bubble_outline,
          }),
          trailing: selectedView == view
              ? const Icon(Icons.check, size: NotionSize.icon)
              : null,
          onTap: () => onViewSelected!(view),
        ),
      const NotionGlassDivider(vertical: false),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          NotionSpace.sm,
          NotionSpace.xs,
          NotionSpace.sm,
          NotionSpace.xxs,
        ),
        child: Text('Networks', style: context.notion.typography.sectionLabel),
      ),
    ],
    _option(context, null),
    for (final network in networks.toSet()) _option(context, network),
    if (onManageNetworks != null) ...[
      const NotionGlassDivider(vertical: false),
      NotionGlassMenuRow(
        leading: const Icon(Icons.tune),
        title: 'Manage networks',
        onTap: onManageNetworks,
      ),
    ],
    if (onMarkAllRead != null) ...[
      const NotionGlassDivider(vertical: false),
      NotionGlassMenuRow(
        key: const ValueKey('notion_mark_all_read'),
        leading: const Icon(Icons.done_all),
        title: 'Mark all as read',
        onTap: onMarkAllRead,
      ),
    ],
    const SizedBox(height: NotionSpace.xxs + 2),
  ];

  Widget _option(BuildContext context, String? network) {
    final active = selected == network;
    final name = network == null ? 'All networks' : notionNetworkLabel(network);
    return NotionGlassMenuRow(
      selected: active,
      leading: NotionNetworkGlyph(network: network, size: 23),
      title: name,
      trailing: active ? const Icon(Icons.check, size: NotionSize.icon) : null,
      onTap: () => onSelected(network),
    );
  }
}
