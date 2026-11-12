// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/personal/app_feedback.dart';
import 'package:chatloom/personal/app_feedback_share.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/app_feedback_capture.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/widgets/app_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

NavigatorState? _feedbackNavigator;
Object? _feedbackOwner;
bool get appFeedbackOpen => _feedbackNavigator?.mounted ?? false;

Future<void> showAppFeedback(BuildContext context) async {
  if (!context.mounted ||
      appFeedbackOpen ||
      !PersonalPrivacy.surfaceUnlocked ||
      !PersonalPrivacy.surfaceForeground ||
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    return;
  }
  final owner = _feedbackOwner = Object();
  _feedbackNavigator = Navigator.of(context);
  try {
    final generation = PersonalPrivacy.surfaceGeneration;
    final route = ModalRoute.of(context);
    final media = MediaQuery.of(context);
    final environment = AppFeedbackEnvironment.capture(
      width: media.size.width.round(),
      height: media.size.height.round(),
      textScale: media.textScaler.scale(16) / 16,
      dark: Theme.of(context).brightness == Brightness.dark,
      reducedMotion: NotionMotion.reduced(context),
    );
    final screenshot = await AppFeedbackCaptureScope.capture(context);
    if (!context.mounted ||
        generation != PersonalPrivacy.surfaceGeneration ||
        !PersonalPrivacy.surfaceUnlocked ||
        !PersonalPrivacy.surfaceForeground ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        (route != null && !route.isCurrent)) {
      return;
    }
    await showNotionSheet<void>(
      context: context,
      title: 'Report a problem',
      builder: (_) =>
          AppFeedbackSheet(environment: environment, screenshot: screenshot),
    );
  } finally {
    if (identical(_feedbackOwner, owner)) {
      _feedbackOwner = null;
      _feedbackNavigator = null;
    }
  }
}

class AppFeedbackSheet extends StatefulWidget {
  const AppFeedbackSheet({
    super.key,
    required this.environment,
    this.screenshot,
    @visibleForTesting this.share,
  });
  final Future<AppFeedbackEnvironment> environment;
  final Uint8List? screenshot;
  final Future<void> Function(String, Uint8List?, Rect)? share;
  @override
  State<AppFeedbackSheet> createState() => _AppFeedbackSheetState();
}

class _AppFeedbackSheetState extends State<AppFeedbackSheet> {
  final _description = TextEditingController();
  String? _error;
  bool _busy = false;
  Uint8List? _screenshot;
  bool _expanded = false;
  bool _removed = false;
  AppLockController? _lock;

  @override
  void initState() {
    super.initState();
    _screenshot = widget.screenshot;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lock = context.findAncestorStateOfType<AppLock>()?.controller;
    if (!identical(lock, _lock)) {
      _lock?.removeListener(_privacyChanged);
      _lock = lock?..addListener(_privacyChanged);
    }
    if (_lock?.isLocked == true) _dropScreenshot();
  }

  void _dropScreenshot() {
    final bytes = _screenshot;
    _screenshot = null;
    _expanded = false;
    _removed = true;
    if (bytes != null) unawaited(MemoryImage(bytes).evict());
  }

  void _privacyChanged() {
    if (_lock?.isLocked == true && mounted) setState(_dropScreenshot);
  }

  bool get _allowed =>
      mounted &&
      PersonalPrivacy.surfaceUnlocked &&
      PersonalPrivacy.surfaceForeground &&
      _lock?.isLocked != true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      ModalRoute.of(context)?.isCurrent == true;
  @override
  void dispose() {
    _lock?.removeListener(_privacyChanged);
    _dropScreenshot();
    _description.dispose();
    super.dispose();
  }

  Future<void> _copy(AppFeedbackEnvironment environment) async {
    if (_busy || !_allowed) return;
    try {
      final report = environment.report(_description.text);
      setState(() {
        _busy = true;
        _error = null;
      });
      await Clipboard.setData(ClipboardData(text: report));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: NotionMotion.feedbackHold,
          content: Text('Text report copied.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Couldn’t copy the report. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(
    AppFeedbackEnvironment environment,
    BuildContext anchor,
  ) async {
    if (_busy || !_allowed) return;
    try {
      final bytes = _screenshot;
      final report = environment.report(
        _description.text,
        screenshotAttached: bytes != null,
      );
      final box = anchor.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize || box.size.isEmpty
          ? Rect.fromCenter(
              center: MediaQuery.sizeOf(context).center(Offset.zero),
              width: 1,
              height: 1,
            )
          : box.localToGlobal(Offset.zero) & box.size;
      final generation = PersonalPrivacy.surfaceGeneration;
      setState(() {
        _busy = true;
        _error = null;
      });
      if (widget.share case final share?) {
        await share(report, bytes, origin);
      } else {
        await shareAppFeedback(
          report,
          bytes,
          origin,
          isCurrent: () =>
              _allowed && generation == PersonalPrivacy.surfaceGeneration,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Couldn’t share the report. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(NotionSpace.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NotionTextField(
            key: const ValueKey('feedback-description'),
            label: 'What went wrong?',
            hint: 'What happened, what you expected, and how to repeat it.',
            controller: _description,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            minLines: 4,
            maxLines: 8,
            error: _error,
          ),
          const SizedBox(height: NotionSpace.md),
          if (_screenshot case final bytes?) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Screenshot',
                    style: context.notion.typography.captionMuted,
                  ),
                ),
                NotionIconButton(
                  icon: Icons.close,
                  label: 'Remove screenshot',
                  onPressed: _busy ? null : () => setState(_dropScreenshot),
                ),
              ],
            ),
            Semantics(
              button: true,
              label: _expanded ? 'Collapse screenshot' : 'Preview screenshot',
              child: NotionPressable(
                onTap: _busy
                    ? null
                    : () => setState(() => _expanded = !_expanded),
                child: ClipRRect(
                  borderRadius: NotionRadius.smAll,
                  child: SizedBox(
                    height: _expanded
                        ? NotionSize.sheetDialogMaxHeight / 2
                        : NotionSize.touchTarget * 2,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: NotionSpace.md),
          ] else if (!_removed) ...[
            Text(
              'Screenshot unavailable',
              style: context.notion.typography.captionMuted,
            ),
            const SizedBox(height: NotionSpace.md),
          ],
          FutureBuilder<AppFeedbackEnvironment>(
            future: widget.environment,
            builder: (context, snapshot) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  snapshot.data?.summary ?? 'Reading app version…',
                  style: context.notion.typography.captionMuted,
                ),
                const SizedBox(height: NotionSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (anchor) => NotionButton.primary(
                          icon: Icons.ios_share,
                          label: 'Share report',
                          busy: _busy,
                          onPressed: _busy || snapshot.data == null
                              ? null
                              : () => _share(snapshot.data!, anchor),
                        ),
                      ),
                    ),
                    const SizedBox(width: NotionSpace.xs),
                    NotionIconButton(
                      icon: Icons.copy_outlined,
                      label: 'Copy text report',
                      onPressed: _busy || snapshot.data == null
                          ? null
                          : () => _copy(snapshot.data!),
                    ),
                  ],
                ),
                const SizedBox(height: NotionSpace.xs),
                Text(
                  _screenshot != null
                      ? 'Review the screenshot before sharing. No logs attached.'
                      : 'Includes display settings. No logs attached.',
                  style: context.notion.typography.captionMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
