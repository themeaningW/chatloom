// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:chatloom/personal/stickers/composer_panel.dart';
import 'package:chatloom/personal/stickers/expanded_sticker_panel.dart';
import 'package:chatloom/personal/stickers/sticker_panel.dart';
import 'package:material_ui/material_ui.dart';

import 'conversation_source.dart';

/// Emoji and stickers replace the keyboard. GIFs open a tall browser so its
/// results retain their space above Search and the system keyboard.
/// Shared by ordinary and merged chats.
class ChatEmojiPicker extends StatefulWidget {
  final ConversationComposerHost controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  State<ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<ChatEmojiPicker> {
  bool _sheetQueued = false;
  bool _sheetOpen = false;
  ModalRoute<dynamic>? _sheetRoute;
  Object? _sheetRoom;

  /// The panel's own search fields (stickers, GIFs).
  final _searchFocus = FocusNode(debugLabel: 'composer panel search');

  /// Holds every field of the panel (the emoji search has its own node):
  /// while any of them is focused the slot stays above the keyboard.
  final _panelScope = FocusScopeNode(debugLabel: 'composer panel');

  @override
  void didUpdateWidget(ChatEmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sheetOpen &&
        (!identical(oldWidget.controller, widget.controller) ||
            !widget.controller.showEmojiPicker ||
            !identical(_sheetRoom, widget.controller.room))) {
      _removeSheet();
    }
  }

  void _removeSheet() {
    final route = _sheetRoute;
    _sheetRoute = null;
    if (route == null) return;
    final navigator = route.navigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && route.isActive) {
        navigator!.removeRoute(route);
      }
    });
  }

  void _scheduleSheet() {
    if (_sheetQueued || _sheetOpen) return;
    _sheetQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetQueued = false;
      if (mounted &&
          widget.controller.showEmojiPicker &&
          StickerPanel.lastTab == StickerPanelTab.gifs) {
        unawaited(_openSheet());
      }
    });
  }

  Future<void> _openSheet() async {
    final host = widget.controller;
    final room = host.room;
    _sheetRoom = room;
    _panelScope.unfocus();
    setState(() => _sheetOpen = true);
    try {
      await showExpandedStickerPanel(
        context,
        host,
        onRoute: (route) => _sheetRoute = route,
      );
    } finally {
      _sheetRoute = null;
      if (mounted) {
        // Closing a previous account's browser must not close the new one's.
        if (identical(host, widget.controller) &&
            identical(room, widget.controller.room)) {
          host.hideEmojiPicker();
        }
        setState(() => _sheetOpen = false);
      }
    }
  }

  @override
  void dispose() {
    _removeSheet();
    _searchFocus.dispose();
    _panelScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.showEmojiPicker &&
        (_sheetOpen || StickerPanel.lastTab == StickerPanelTab.gifs)) {
      _scheduleSheet();
      return const SizedBox.shrink();
    }
    return ComposerPanelSlot(
      visible: widget.controller.showEmojiPicker,
      inputFocus: widget.controller.inputFocus,
      searchFocus: _panelScope,
      builder: (context, height) => FocusScope(
        node: _panelScope,
        child: StickerPanel(
          host: widget.controller,
          searchFocus: _searchFocus,
          onTabChanged: (tab) {
            if (tab == StickerPanelTab.gifs) setState(_scheduleSheet);
          },
        ),
      ),
    );
  }
}
