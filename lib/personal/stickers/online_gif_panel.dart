// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/pages/chat/conversation_source.dart';
import 'package:chatloom/pages/chat/trust_user_key_dialog.dart';
import 'package:chatloom/personal/media/outgoing_media.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/round_video/round_playback_coordinator.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'gif_result_tile.dart';
import 'gif_search.dart';
import 'gif_tab.dart';
import 'public_gif_search.dart';
import 'sticker_library.dart';

typedef GifSendRequest = ({
  Room room,
  MatrixVideoFile file,
  Event? reply,
  String? thread,
  String? last,
  Map<String, dynamic> extraContent,
});

/// One GIF tab: online GIFs/clips, with the existing saved/Telegram library
/// behind the bookmark. No provider/account data is mixed in a result grid.
class OnlineGifPanel extends StatefulWidget {
  const OnlineGifPanel({
    super.key,
    required this.host,
    this.searchFocus,
    this.library,
    this.source,
    this.loadCredentials = true,
    this.send,
  });
  final ConversationComposerHost host;
  final FocusNode? searchFocus;
  final StickerLibrary? library;
  final PublicGifSearch? source;
  final bool loadCredentials;

  /// The shared outgoing queue by default; injectable for offline acceptance.
  final Future<void> Function(GifSendRequest)? send;
  @override
  State<OnlineGifPanel> createState() => _OnlineGifPanelState();
}

class _OnlineGifPanelState extends State<OnlineGifPanel> {
  late final _source = widget.source ?? PublicGifSearch();
  final _query = TextEditingController();
  final _scroll = ScrollController();
  List<GifSearchResult> _results = const [];
  String? _next;
  String? _error;
  bool _busy = false, _saved = false;
  bool _previewing = false;
  int _generation = 0;
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    if (widget.source == null) {
      try {
        if (AppSettings.store.getString('chatloom.gif.provider') == 'giphy') {
          _source.provider = GifProvider.giphy;
        }
      } catch (_) {
        /* Preference is optional until settings are ready. */
      }
    }
    _source.addListener(_configurationChanged);
    if (widget.loadCredentials) unawaited(_source.loadKey());
  }

  void _configurationChanged() {
    if (!mounted) return;
    _typing?.cancel();
    _generation++;
    setState(() {
      _results = const [];
      _next = null;
      _busy = false;
      _error = null;
    });
  }

  @override
  void didUpdateWidget(OnlineGifPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host.room, widget.host.room)) {
      _typing?.cancel();
      _generation++;
      _query.clear();
      _results = const [];
      _next = null;
      _error = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _typing?.cancel();
    _source.removeListener(_configurationChanged);
    if (widget.source == null) _source.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _unlocked =>
      PersonalPrivacy.surfaceUnlocked && PersonalPrivacy.surfaceForeground;

  void _typed(String value) {
    _typing?.cancel();
    // Invalidate now, not after the debounce, so an older response cannot win.
    _generation++;
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _next = null;
        _busy = false;
        _error = null;
      });
      return;
    }
    _typing = Timer(GifTab.debounce, () => unawaited(_search()));
  }

  Future<void> _search({bool more = false}) async {
    _typing?.cancel();
    if (!_unlocked || !_source.configured || _query.text.trim().isEmpty) return;
    if (more && (_busy || _next == null)) return;
    final generation = ++_generation;
    final surface = PersonalPrivacy.surfaceGeneration;
    final room = widget.host.room;
    final session = (room.client.userID, room.client.accessToken);
    final query = _query.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _next = null;
    });
    try {
      final page = await _source.search(
        room,
        query,
        offset: more ? _next : null,
      );
      if (!mounted ||
          generation != _generation ||
          !_unlocked ||
          surface != PersonalPrivacy.surfaceGeneration ||
          !identical(room, widget.host.room) ||
          session != (room.client.userID, room.client.accessToken)) {
        return;
      }
      setState(() {
        final seen = more ? _results.map((r) => r.id).toSet() : <String>{};
        _results = [
          if (more) ..._results,
          for (final r in page.results)
            if (seen.add(r.id)) r,
        ];
        _next = page.nextOffset;
      });
      if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e is GifSearchException
              ? e.message
              : 'Couldn’t search KLIPY.';
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _select(GifSearchKind kind) {
    _typing?.cancel();
    _generation++;
    setState(() {
      _saved = false;
      _source.kind = kind;
      _results = const [];
      _next = null;
      _error = null;
      _busy = false;
    });
    if (_query.text.trim().isNotEmpty) unawaited(_search());
  }

  void _selectProvider(GifProvider provider) {
    _source.provider = provider;
    try {
      AppSettings.store.setString('chatloom.gif.provider', provider.name);
    } catch (_) {
      /* Keep this panel's selection when preferences are unavailable. */
    }
    _select(GifSearchKind.gifs);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _configure() async {
    var entry = '';
    final key = await showNotionDialog<String>(
      context: context,
      title: _source.label,
      message:
          'Add your API key. Searches and previews go to ${_source.label}; chat history stays in ChatLoom.',
      content: TextField(
        onChanged: (value) => entry = value,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'API key'),
      ),
      actions: (dialog) => [
        NotionButton.ghost(
          label: 'Get a key',
          onPressed: () => launchUrl(Uri.parse(_source.documentationUrl)),
        ),
        NotionButton.ghost(
          label: 'Cancel',
          onPressed: () => Navigator.of(dialog).pop(),
        ),
        NotionButton(
          label: 'Save',
          onPressed: () => Navigator.of(dialog).pop(entry.trim()),
        ),
      ],
    );
    if (key == null || !mounted) return;
    try {
      await _source.setKey(key);
    } on GifSearchException catch (e) {
      _say(e.message);
    }
  }

  Future<void> _preview(GifSearchResult item) async {
    if (_previewing) return;
    _previewing = true;
    try {
      await _previewItem(item);
    } finally {
      _previewing = false;
    }
  }

  Future<void> _previewItem(GifSearchResult item) async {
    if (_busy || !_unlocked) return;
    widget.searchFocus?.unfocus();
    final host = widget.host;
    final room = host.room;
    final session = (room.client.userID, room.client.accessToken);
    final surface = PersonalPrivacy.surfaceGeneration;
    final reply = host.replyEvent;
    final thread = host.activeThreadId, last = host.threadLastEventId;
    final plan = PublicGifSearch.sendPlan(room, item, size: item.size);
    final send = await showNotionSheet<bool>(
      context: context,
      builder: (_) => _PublicGifPreview(item: item, reason: plan.reason),
    );
    bool current() =>
        mounted &&
        _unlocked &&
        surface == PersonalPrivacy.surfaceGeneration &&
        identical(room, widget.host.room) &&
        session == (room.client.userID, room.client.accessToken);
    if (send != true || !current() || !plan.possible) return;
    if (!mounted ||
        !await showTrustUserInRoomDialog(context, room) ||
        !current()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await _source.download(item);
      if (!current()) return;
      final actual = PublicGifSearch.sendPlan(room, item, size: file.size);
      if (!actual.possible) {
        throw GifSearchException(
          actual.reason ?? 'This chat cannot receive this item.',
        );
      }
      final info = Map<String, dynamic>.from(actual.content!['info'] as Map);
      final request = (
        room: room,
        file: file,
        reply: reply,
        thread: thread,
        last: last,
        extraContent: <String, dynamic>{
          'info': {...file.info, ...info},
        },
      );
      final send = widget.send;
      if (send != null) {
        await send(request);
      } else {
        final ticket = await OutgoingMedia.send(
          room,
          file,
          inReplyTo: reply,
          threadRootEventId: thread,
          threadLastEventId: last,
          extraContent: request.extraContent,
        );
        ticket.accepted.then<void>(
          (_) {},
          onError: (Object _) =>
              _say('Couldn’t send. Retry the message in the chat.'),
        );
      }
      if (reply != null && current() && identical(host.replyEvent, reply)) {
        host.cancelReplyEventAction();
      }
      NotionHaptics.send();
    } catch (e) {
      _say(
        e is GifSearchException
            ? e.message
            : 'Couldn’t send this item. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NotionSpace.xs),
              child: NotionChoicePill<GifProvider>(
                title: 'GIF source',
                value: _source.provider,
                neutral: GifProvider.klipy,
                onChanged: _selectProvider,
                options: const [
                  NotionChoice(GifProvider.klipy, 'KLIPY'),
                  NotionChoice(GifProvider.giphy, 'GIPHY'),
                ],
              ),
            ),
            const Spacer(),
            NotionIconButton(
              icon: Icons.bookmark_outline,
              label: 'Saved GIFs and Telegram',
              onPressed: () {
                _typing?.cancel();
                _generation++;
                setState(() {
                  _saved = !_saved;
                  _busy = false;
                });
              },
            ),
            NotionIconButton(
              icon: Icons.settings_outlined,
              label: '${_source.label} settings',
              onPressed: _configure,
            ),
          ],
        ),
        if (_source.provider == GifProvider.klipy && !_saved)
          Row(
            children: [
              const SizedBox(width: NotionSpace.xs),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final kind in GifSearchKind.values)
                        Padding(
                          padding: const EdgeInsets.only(right: NotionSpace.xs),
                          child: NotionGlassPill(
                            label: kind == GifSearchKind.gifs
                                ? 'GIFs'
                                : 'Clips',
                            selected: !_saved && _source.kind == kind,
                            onPressed: () => _select(kind),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (_saved)
          Expanded(
            child: GifTab(
              host: widget.host,
              searchFocus: widget.searchFocus,
              library: widget.library,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NotionSpace.xs),
            child: TextField(
              key: const ValueKey('klipy-search'),
              controller: _query,
              focusNode: widget.searchFocus,
              enabled: _source.configured,
              textInputAction: TextInputAction.search,
              onChanged: _typed,
              onSubmitted: (_) => unawaited(_search()),
              decoration: InputDecoration(
                hintText: _source.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busy
                    ? const NotionDelayedSpinner(size: NotionSize.iconSm)
                    : NotionIconButton(
                        icon: Icons.close,
                        label: 'Clear search',
                        onPressed: () {
                          _query.clear();
                          _typed('');
                        },
                      ),
                helperMaxLines: 2,
              ),
            ),
          ),
          Expanded(child: _body(context)),
          Padding(
            padding: const EdgeInsets.all(NotionSpace.xxs),
            child: _source.provider == GifProvider.giphy
                ? Image.asset(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'assets/giphy-powered-dark.png'
                        : 'assets/giphy-powered-light.png',
                    height: NotionSize.icon,
                    semanticLabel: 'Powered by GIPHY',
                  )
                : Text(
                    'Powered by ${_source.label}',
                    style: context.notion.typography.captionMuted,
                  ),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (!_source.configured) {
      return SingleChildScrollView(
        child: NotionEmptyState(
          icon: Icons.gif_box_outlined,
          title: _source.provider == GifProvider.giphy
              ? 'GIFs'
              : 'GIFs & clips',
          action: NotionButton.ghost(
            label: 'Set up ${_source.label}',
            onPressed: _configure,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return SingleChildScrollView(
        child: NotionEmptyState(
          icon: Icons.gif_box_outlined,
          title: _busy
              ? 'Searching…'
              : _error ??
                    (_query.text.trim().isEmpty
                        ? 'Find a GIF or clip'
                        : 'No results'),
          action: _error == null
              ? null
              : NotionButton.ghost(
                  label: 'Try again',
                  onPressed: () => unawaited(_search()),
                ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth < 350 ? 2 : 3;
        final size = (box.maxWidth - NotionSpace.xxs * (columns + 1)) / columns;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(NotionSpace.xxs),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: NotionSpace.xxs,
                  crossAxisSpacing: NotionSpace.xxs,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = _results[index];
                  return GifResultTile(
                    key: ValueKey(item.id),
                    result: item,
                    source: _source,
                    room: widget.host.room,
                    size: size,
                    onTap: () => _preview(item),
                    onLongPress: () => _preview(item),
                  );
                }, childCount: _results.length),
              ),
            ),
            if (_next != null || _error != null)
              SliverToBoxAdapter(
                child: NotionButton.ghost(
                  label: _error ?? 'More',
                  onPressed: _busy
                      ? null
                      : () => unawaited(_search(more: true)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PublicGifPreview extends StatefulWidget {
  const _PublicGifPreview({required this.item, this.reason});
  final GifSearchResult item;
  final String? reason;
  @override
  State<_PublicGifPreview> createState() => _PublicGifPreviewState();
}

class _PublicGifPreviewState extends State<_PublicGifPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _player;
  bool _muted = true;
  late final RoundPlaybackHandle _handle;
  Future<void> _pause() async {
    await _player?.pause();
  }

  @override
  void initState() {
    super.initState();
    _handle = RoundPlaybackCoordinator.shared.register(
      pause: _pause,
      stop: _pause,
    );
    WidgetsBinding.instance.addObserver(this);
    final player = VideoPlayerController.networkUrl(widget.item.remoteVideo!);
    _player = player;
    unawaited(() async {
      try {
        await player.initialize();
        await player.setLooping(true);
        await player.setVolume(0);
        if (!mounted ||
            !PersonalPrivacy.surfaceUnlocked ||
            RoundPlaybackCoordinator.shared.suspended) {
          return;
        }
        setState(() {});
        await player.play();
      } catch (_) {
        /* Thumbnail stays usable when the player fails. */
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handle.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(NotionSpace.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: widget.item.aspectRatio.clamp(.7, 2),
              child: ClipRRect(
                borderRadius: NotionRadius.mdAll,
                child: _player?.value.isInitialized == true
                    ? VideoPlayer(_player!)
                    : widget.item.remoteThumbnail != null
                    ? Image.network(
                        widget.item.remoteThumbnail.toString(),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.gif_box_outlined),
                      )
                    : const Icon(Icons.gif_box_outlined),
              ),
            ),
          ),
          const SizedBox(height: NotionSpace.sm),
          if (widget.reason != null)
            Text(widget.reason!, style: context.notion.typography.captionMuted),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: NotionSpace.xs,
            children: [
              if (widget.item.hasAudio)
                NotionIconButton(
                  icon: _muted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: _muted ? 'Play sound' : 'Mute',
                  onPressed: () async {
                    if (!PersonalPrivacy.surfaceUnlocked ||
                        RoundPlaybackCoordinator.shared.suspended) {
                      return;
                    }
                    if (_muted && !await _handle.acquireAudible()) return;
                    if (!mounted) return;
                    setState(() => _muted = !_muted);
                    if (_muted) _handle.releaseAudible();
                    await _player?.setVolume(_muted ? 0 : 1);
                    if (mounted &&
                        (!_muted
                            ? _handle.isCurrent
                            : !RoundPlaybackCoordinator.shared.suspended)) {
                      await _player?.play();
                    }
                  },
                ),
              NotionButton.ghost(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              NotionButton(
                label: 'Send',
                icon: Icons.send_outlined,
                onPressed: widget.reason == null
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
