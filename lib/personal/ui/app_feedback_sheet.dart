// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/app_feedback.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showAppFeedback(BuildContext context) {
  final media = MediaQuery.of(context);
  final environment = AppFeedbackEnvironment.capture(
    width: media.size.width.round(),
    height: media.size.height.round(),
    textScale: media.textScaler.scale(16) / 16,
    dark: Theme.of(context).brightness == Brightness.dark,
    reducedMotion: NotionMotion.reduced(context),
  );
  return showNotionSheet<void>(
    context: context,
    title: 'Report a problem',
    builder: (_) => AppFeedbackSheet(environment: environment),
  );
}

class AppFeedbackSheet extends StatefulWidget {
  const AppFeedbackSheet({super.key, required this.environment});
  final Future<AppFeedbackEnvironment> environment;
  @override
  State<AppFeedbackSheet> createState() => _AppFeedbackSheetState();
}

class _AppFeedbackSheetState extends State<AppFeedbackSheet> {
  final _description = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _copy(AppFeedbackEnvironment environment) async {
    if (_busy) return;
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
          content: Text(
            'Copied. Add a screenshot or recording when sharing it.',
          ),
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
                NotionButton.primary(
                  icon: Icons.copy_outlined,
                  label: 'Copy report',
                  busy: _busy,
                  onPressed: _busy || snapshot.data == null
                      ? null
                      : () => _copy(snapshot.data!),
                ),
                const SizedBox(height: NotionSpace.xs),
                Text(
                  'Includes display settings. No chats or logs are collected.',
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
