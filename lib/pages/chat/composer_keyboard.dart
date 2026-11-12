// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/pages/chat/conversation_source.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/utils/macos_desktop.dart';
import 'package:chatloom/utils/platform_infos.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' show maxPDUSize;
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

/// Enter commits an IME candidate before it can ever submit a message.
/// ⌘↩ ([metaPressed]) always sends (Telegram, Slack), also with "Send on
/// enter" off. With [onEditLast] (desktop, no reply or edit open), a bare ↑
/// in the empty composer edits the last own message, as in ordinary chats.
KeyEventResult conversationComposerKeyResult(
  KeyEvent event, {
  required TextEditingValue value,
  required bool sendOnEnter,
  required bool shiftPressed,
  required VoidCallback onSend,
  bool metaPressed = false,
  VoidCallback? onEditLast,
}) {
  if (onEditLast != null &&
      event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.arrowUp &&
      value.text.isEmpty &&
      !shiftPressed &&
      !metaPressed &&
      !HardwareKeyboard.instance.isAltPressed &&
      !HardwareKeyboard.instance.isControlPressed) {
    onEditLast();
    return KeyEventResult.handled;
  }
  final enter =
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
  if (!enter ||
      !(sendOnEnter || metaPressed) ||
      shiftPressed ||
      (value.composing.isValid && !value.composing.isCollapsed)) {
    return KeyEventResult.ignored;
  }
  if (event is KeyDownEvent) onSend();
  // A held key must not repeat a send or insert a newline on key-up.
  return KeyEventResult.handled;
}

/// The same grapheme-aware limits apply to native edits, menu/keyboard paste
/// and type-to-focus. Keep the protocol cap even when the display setting is
/// relaxed. TextField.maxLength additionally supplies its counter/semantics.
List<TextInputFormatter> composerTextInputFormatters() => [
  LengthLimitingTextInputFormatter((maxPDUSize / 3).floor()),
  LengthLimitingTextInputFormatter(AppSettings.textMessageMaxLength.value),
];

/// Replaces the selection of [controller] (or appends) with [text], applying
/// the editor's formatters before setting the caret; returns the accepted text.
String insertComposerText(TextEditingController controller, String text) {
  final value = controller.value;
  final selection =
      value.selection.isValid && value.selection.end <= value.text.length
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final next = value.text.replaceRange(selection.start, selection.end, text);
  var formatted = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
  for (final formatter in composerTextInputFormatters()) {
    formatted = formatter.formatEditUpdate(value, formatted);
  }
  controller.value = formatted;
  return formatted.text;
}

/// The native paste permission sheet may finish an IME composition without
/// changing the user's text or caret. Genuine edits/selection moves still win.
bool composerValueUnchangedForPaste(
  TextEditingValue current,
  TextEditingValue before,
) => current.text == before.text && current.selection == before.selection;

/// Image clipboard implementations may return PNG, JPEG or other encoded
/// image bytes. Keep the filename and MIME consistent with those bytes.
XFile composerClipboardImage(Uint8List bytes) {
  final mime =
      lookupMimeType('pasted-image', headerBytes: bytes) ?? 'image/png';
  final extension = switch (mime) {
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/bmp' => 'bmp',
    'image/tiff' => 'tif',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    'image/avif' => 'avif',
    _ => extensionFromMime(mime) ?? 'png',
  };
  final name = 'pasted-image.$extension';
  return XFile.fromData(bytes, name: name, path: name, mimeType: mime);
}

/// Type-to-focus (Telegram, WhatsApp, Messenger desktop): a character typed
/// while focus is elsewhere in the conversation (a clicked message, the
/// inbox) goes to the composer, which takes focus. False when the composer
/// cannot take it (not mounted, sending, no source).
bool typeIntoComposer(ConversationComposerHost host, String text) {
  final focus = host.inputFocus;
  if (!host.composerEnabled || focus.context == null) return false;
  final next = insertComposerText(host.sendController, text);
  focus.requestFocus();
  host.onInputBarChanged(next);
  return true;
}

/// Esc in the composer with nothing left to cancel (Mac, Telegram Desktop):
/// Back, which closes the chat. A text field turns Esc into a
/// [DismissIntent] (on the Mac through AppKit's `cancelOperation:` once the
/// input method has no candidates) and hands it to the nearest ancestor
/// action after its own toolbar and the mention list declined it; this is
/// that action. Enabled only while the composer itself has focus, so other
/// fields in the chat (search) keep Esc.
class ComposerBackAction extends Action<DismissIntent> {
  ComposerBackAction({
    required this.composer,
    required this.onBack,
    required this.enabled,
  });

  final FocusNode composer;
  final VoidCallback onBack;
  final bool enabled;

  @override
  bool isEnabled(DismissIntent intent) {
    if (!enabled || !composer.hasPrimaryFocus) return false;
    if (!PersonalPrivacy.surfaceUnlocked) return false;
    // An input method composing keeps Esc to cancel its candidate.
    final composing = composer.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.textEditingValue
        .composing;
    return composing == null || !composing.isValid || composing.isCollapsed;
  }

  @override
  Object? invoke(DismissIntent intent) {
    onBack();
    return null;
  }
}

/// One paste request: text is retained, never fetched a second time after
/// attachment checks. On macOS both type priority and text are captured
/// together, before a dictation tool can restore the previous clipboard.
/// Tests of the native menu/composer can supply bytes without involving the
/// host platform plugin's temporary-file I/O. Normal operation always uses
/// Pasteboard.image; this hook does not change clipboard policy or sending.
@visibleForTesting
Future<Uint8List?> Function()? debugReadComposerClipboardImage;

Future<({String? text, List<XFile>? media})> readComposerClipboard({
  bool allowMedia = true,
  TargetPlatform? platform,
}) async {
  final target = platform ?? defaultTargetPlatform;
  final snapshot = !PlatformInfos.isWeb && target == TargetPlatform.macOS
      ? await MacDesktopWindow.readPasteboard()
      : null;
  if (snapshot != null &&
      !snapshot.prefersMedia &&
      snapshot.text?.isNotEmpty == true) {
    return (text: snapshot.text, media: null);
  }
  if (allowMedia) {
    final media = await _readClipboardMedia(target);
    if (media != null) return (text: null, media: media);
  }
  final text = snapshot != null ? snapshot.text : await _readClipboardText();
  return (text: text?.isNotEmpty == true ? text : null, media: null);
}

Future<List<XFile>?> _readClipboardMedia(TargetPlatform platform) async {
  // iOS Pasteboard.files is deliberately not implemented. Other platforms
  // can also lack a representation/plugin; that must not swallow text paste.
  if (platform != TargetPlatform.iOS) {
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) return files.map(XFile.new).toList();
    } on MissingPluginException {
      // Continue with image/text representations.
    } on PlatformException {
      // A denied/unavailable file representation need not block plain text.
    } on UnsupportedError {
      // No file clipboard implementation on this platform.
    }
  }
  try {
    final image =
        await (debugReadComposerClipboardImage?.call() ?? Pasteboard.image);
    if (image != null && image.isNotEmpty) {
      return [composerClipboardImage(image)];
    }
  } on MissingPluginException {
    // Text still uses Flutter's own clipboard API.
  } on PlatformException {
    // A denied/unavailable image representation need not block plain text.
  } on UnsupportedError {
    // No image clipboard implementation on this platform.
  }
  return null;
}

Future<String?> _readClipboardText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException {
    return null; // A denied paste keeps the draft untouched.
  } on MissingPluginException {
    return null;
  }
}
