// SPDX-License-Identifier: AGPL-3.0-or-later
// Real composers, fictional offline rooms. No messages or system clipboard IO.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/l10n/l10n.dart';
import 'package:chatloom/pages/chat/chat.dart';
import 'package:chatloom/pages/chat/composer_keyboard.dart';
import 'package:chatloom/pages/chat/input_bar.dart';
import 'package:chatloom/pages/chat/send_file_dialog.dart';
import 'package:chatloom/personal/merged_chat_page.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/utils/macos_desktop.dart';
import 'package:chatloom/utils/markdown_context_builder.dart';
import 'package:chatloom/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show maxPDUSize;
import 'package:personal_core/personal_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conversation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String clipboard;
  late int reads;
  late bool restoreAfterRead;
  Completer<void>? readGate;
  late Directory clipboardImageDirectory;
  var clipboardImageCount = 0;

  // The package's iOS/macOS/Android image channel returns bytes, whereas its
  // Windows channel returns the path of a temporary image and deletes it after
  // reading. Match the real host adapter instead of assuming iOS wire format.
  Object hostImageResponse(Uint8List bytes) {
    if (!Platform.isWindows) return bytes;
    final file = File(
      '${clipboardImageDirectory.path}/image-${clipboardImageCount++}.png',
    );
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  Future<String> readText() async {
    reads++;
    final text = clipboard;
    if (restoreAfterRead) clipboard = 'previous clipboard';
    final gate = readGate;
    if (gate != null) await gate.future;
    return text;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });
  setUp(() {
    clipboard = 'zażółć 🗣️';
    reads = 0;
    restoreAfterRead = false;
    readGate = null;
    clipboardImageDirectory = Directory.systemTemp.createTempSync(
      'chatloom_clipboard_fixture_',
    );
    debugReadComposerClipboardImage = null;
    PersonalPrivacy.surfaceUnlocked = true;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': await readText()};
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => call.method == 'files' ? <String>[] : null,
    );
    messenger.setMockMethodCallHandler(MacDesktopWindow.channel, (call) async {
      if (call.method == 'readPasteboard') {
        return {'prefersMedia': false, 'text': await readText()};
      }
      return null;
    });
  });
  tearDown(() {
    debugReadComposerClipboardImage = null;
    if (clipboardImageDirectory.existsSync()) {
      clipboardImageDirectory.deleteSync(recursive: true);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), null);
    messenger.setMockMethodCallHandler(MacDesktopWindow.channel, null);
    PersonalPrivacy.surfaceUnlocked = true;
  });

  test(
    'native snapshot retains dictation when the clipboard is restored',
    () async {
      final snapshot = await MacDesktopWindow.readPasteboard();
      clipboard = 'previous clipboard';
      expect(snapshot, (prefersMedia: false, text: 'zażółć 🗣️'));
      expect(reads, 1);
    },
  );

  test('a missing native snapshot falls back without throwing', () async {
    messenger.setMockMethodCallHandler(MacDesktopWindow.channel, null);
    expect(await MacDesktopWindow.readPasteboard(), isNull);
    expect((await readComposerClipboard()).text, clipboard);
  });

  test('files keep priority over image and text representations', () async {
    messenger.setMockMethodCallHandler(
      MacDesktopWindow.channel,
      (_) async => {'prefersMedia': true, 'text': null},
    );
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
      call,
    ) async {
      expect(call.method, 'files');
      return ['/fictional/example.txt'];
    });
    final paste = await readComposerClipboard();
    expect(paste.media!.single.path, '/fictional/example.txt');
    expect(paste.text, isNull);
    expect(reads, 0);
  });

  test('an image-only paste stays an attachment', () async {
    messenger.setMockMethodCallHandler(
      MacDesktopWindow.channel,
      (_) async => {'prefersMedia': true, 'text': null},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => call.method == 'files'
          ? <String>[]
          : hostImageResponse(Uint8List.fromList([1, 2, 3])),
    );
    final paste = await readComposerClipboard();
    expect(await paste.media!.single.readAsBytes(), [1, 2, 3]);
    expect(paste.text, isNull);
    expect(reads, 0);
  });

  test(
    'iOS reads images without requesting an unsupported file clipboard',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'files') throw MissingPluginException();
        return hostImageResponse(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]));
      });
      final paste = await readComposerClipboard(platform: TargetPlatform.iOS);
      expect(calls, ['image']);
      expect(paste.media!.single.name, 'pasted-image.jpg');
      expect(paste.media!.single.mimeType, 'image/jpeg');
      expect(reads, 0);
    },
  );

  test('missing or denied media APIs do not swallow plain text', () async {
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
      call,
    ) async {
      if (call.method == 'files') throw MissingPluginException();
      throw PlatformException(code: 'clipboard-unavailable');
    });
    final paste = await readComposerClipboard(platform: TargetPlatform.windows);
    expect(paste.text, clipboard);
    expect(paste.media, isNull);
    expect(reads, 1);
  });

  test(
    'paste insertion clamps an invalid stale selection to the draft end',
    () {
      final editor = TextEditingController(text: 'abc');
      editor.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(insertComposerText(editor, 'x'), 'abcx');
      expect(editor.selection.baseOffset, 4);
      editor.dispose();
    },
  );

  test(
    'paste replacement uses the editor limit without splitting emoji graphemes',
    () async {
      final previous = AppSettings.textMessageMaxLength.value;
      addTearDown(() => AppSettings.textMessageMaxLength.setItem(previous));
      await AppSettings.textMessageMaxLength.setItem(5);
      final editor = TextEditingController();
      addTearDown(editor.dispose);
      editor.value = const TextEditingValue(
        text: 'ABCD',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      const family = '👨‍👩‍👧‍👦';
      const expected = 'A$familyéxy';
      expect(insertComposerText(editor, '$familyéxyz'), expected);
      expect(
        editor.selection,
        TextSelection.collapsed(offset: expected.length),
      );
    },
  );

  test(
    'paste retains the protocol limit when the display limit is larger',
    () async {
      final previous = AppSettings.textMessageMaxLength.value;
      addTearDown(() => AppSettings.textMessageMaxLength.setItem(previous));
      await AppSettings.textMessageMaxLength.setItem(maxPDUSize);
      final editor = TextEditingController();
      addTearDown(editor.dispose);
      final wireLimit = (maxPDUSize / 3).floor();
      expect(
        insertComposerText(editor, 'x' * (wireLimit + 10)),
        'x' * wireLimit,
      );
      expect(editor.selection.baseOffset, wireLimit);
    },
  );

  for (final merged in [false, true]) {
    group(merged ? 'merged composer' : 'ordinary composer', () {
      late ConversationPersonal personal;

      Future<TextField> mount(WidgetTester tester) async {
        final client = ConversationClient();
        final a = ConversationRoom(client, '!paste-a:example.invalid');
        final b = ConversationRoom(
          client,
          '!paste-b:example.invalid',
          network: 'telegram',
        );
        a.message(r'$hello', 'Fictional message');
        personal = ConversationPersonal(client);
        PersonalClient.debugUse(client, personal);
        addTearDown(personal.dispose);
        final matrix = ConversationMatrix(
          client,
          await SharedPreferences.getInstance(),
        );
        await tester.pumpWidget(
          Provider<MatrixState>.value(
            value: matrix,
            child: MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: merged
                  ? MergedChatPage(
                      personal: personal,
                      group: PersonGroup(
                        id: 'paste-person',
                        name: 'Fictional person',
                        members: [personal.ref(a), personal.ref(b)],
                        defaultRoomId: a.id,
                      ),
                    )
                  : ChatPageWithRoom(room: a),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(TextField),
        );
        await tester.tap(finder);
        await tester.pump();
        return tester.widget<TextField>(finder);
      }

      Future<void> paste(WidgetTester tester) async {
        final editor = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(EditableText),
        );
        Actions.invoke(
          tester.element(editor),
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
      }

      Future<void> unmount(WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }

      testWidgets('dictation replaces the selection and keeps focus', (
        tester,
      ) async {
        final field = await mount(tester);
        field.controller!.value = const TextEditingValue(
          text: 'Hello world!',
          selection: TextSelection(baseOffset: 6, extentOffset: 11),
        );
        await paste(tester);
        expect(field.controller!.text, 'Hello zażółć 🗣️!');
        expect(field.focusNode!.hasFocus, isTrue);
        expect(field.controller!.selection.baseOffset, 6 + clipboard.length);
        expect(find.byType(SendFileDialog), findsNothing);
        expect(personal.sends, isEmpty);
        expect(reads, 1);
        await unmount(tester);
      });

      testWidgets(
        'native paste respects the configured limit when replacing a selection',
        (tester) async {
          final previous = AppSettings.textMessageMaxLength.value;
          addTearDown(() => AppSettings.textMessageMaxLength.setItem(previous));
          await AppSettings.textMessageMaxLength.setItem(6);
          final field = await mount(tester);
          field.controller!.value = const TextEditingValue(
            text: 'ABCD',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
          );
          clipboard = '12345678';
          await paste(tester);
          expect(field.controller!.text, 'A12345');
          expect(field.controller!.selection.baseOffset, 6);
          expect(personal.sends, isEmpty);
          expect(find.byType(SendFileDialog), findsNothing);
          await unmount(tester);
        },
      );

      testWidgets('an active composition does not discard pasted text', (
        tester,
      ) async {
        final field = await mount(tester);
        field.controller!.value = const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        );
        await paste(tester);
        expect(field.controller!.text, 'abc$clipboard');
        expect(field.focusNode!.hasFocus, isTrue);
        await unmount(tester);
      });

      testWidgets('a temporary dictation clipboard is read only once', (
        tester,
      ) async {
        final field = await mount(tester);
        restoreAfterRead = true;
        final dictated = clipboard;
        await paste(tester);
        expect(clipboard, 'previous clipboard');
        expect(field.controller!.text, dictated);
        expect(reads, 1);
        await unmount(tester);
      });

      if (!merged) {
        testWidgets('text can be pasted while editing a sent message', (
          tester,
        ) async {
          final field = await mount(tester);
          final controller = tester.state<ChatController>(
            find.byType(ChatPageWithRoom),
          );
          final original = (controller.room as ConversationRoom).message(
            r'$own',
            'Original message',
            outgoing: true,
          );
          controller.editEventAction(original);
          field.controller!.selection = TextSelection.collapsed(
            offset: field.controller!.text.length,
          );
          await tester.pump();
          await paste(tester);
          expect(controller.editEvent, same(original));
          expect(field.controller!.text, 'Original message$clipboard');
          expect(personal.sends, isEmpty);
          await unmount(tester);
        });
      }

      testWidgets('typing during a delayed paste keeps the new draft', (
        tester,
      ) async {
        final field = await mount(tester);
        final gate = readGate = Completer<void>();
        await paste(tester);
        field.controller!.text = 'New draft';
        gate.complete();
        await tester.pump();
        expect(field.controller!.text, 'New draft');
        await unmount(tester);
      });

      testWidgets('empty clipboard never deletes the selected draft', (
        tester,
      ) async {
        final field = await mount(tester);
        field.controller!.value = const TextEditingValue(
          text: 'Keep this text',
          selection: TextSelection(baseOffset: 0, extentOffset: 14),
        );
        clipboard = '';
        await paste(tester);
        expect(field.controller!.text, 'Keep this text');
        expect(personal.sends, isEmpty);
        await unmount(tester);
      });

      testWidgets(
        'finishing composition while paste is pending keeps the paste',
        (tester) async {
          final field = await mount(tester);
          field.controller!.value = const TextEditingValue(
            text: 'abc',
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: 0, end: 3),
          );
          final gate = readGate = Completer<void>();
          await paste(tester);
          field.controller!.value = field.controller!.value.copyWith(
            composing: TextRange.empty,
          );
          gate.complete();
          await tester.pump();
          expect(field.controller!.text, 'abc$clipboard');
          expect(personal.sends, isEmpty);
          await unmount(tester);
        },
      );

      testWidgets(
        'native toolbar offers image-only Paste and opens a preview without sending',
        (tester) async {
          final field = await mount(tester);
          var imageReads = 0;
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': false};
            if (call.method == 'Clipboard.getData') return null;
            return null;
          });
          messenger.setMockMethodCallHandler(
            const MethodChannel('pasteboard'),
            (call) async {
              if (call.method == 'files') return <String>[];
              throw StateError(
                'The widget fixture must not call the host image adapter',
              );
            },
          );
          debugReadComposerClipboardImage = () async {
            imageReads++;
            return base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
            );
          };
          final editableFinder = find.descendant(
            of: find.byType(InputBar),
            matching: find.byType(EditableText),
          );
          final editable = tester.state<EditableTextState>(editableFinder);
          final toolbar =
              field.contextMenuBuilder!(
                    tester.element(editableFinder),
                    editable,
                  )
                  as MarkdownContextBuilder;
          expect(toolbar.onPaste, isNotNull);
          expect(
            imageReads,
            0,
            reason: 'opening a menu never reads private clipboard content',
          );
          toolbar.onPaste!();
          await tester.pumpAndSettle();
          expect(imageReads, 1);
          expect(find.byType(SendFileDialog), findsOneWidget);
          expect(
            personal.sends,
            isEmpty,
            reason: 'paste is not permission to send',
          );
          await unmount(tester);
        },
      );

      testWidgets(
        'keyboard image insertion stages attachment instead of immediately sending',
        (tester) async {
          final field = await mount(tester);
          field.contentInsertionConfiguration!.onContentInserted(
            KeyboardInsertedContent(
              mimeType: 'image/png',
              uri: 'content://fictional/pasted.png',
              data: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SendFileDialog), findsOneWidget);
          expect(personal.sends, isEmpty);
          await unmount(tester);
        },
      );

      testWidgets(
        'leaving the conversation cancels an outstanding text paste',
        (tester) async {
          await mount(tester);
          final gate = readGate = Completer<void>();
          await paste(tester);
          await unmount(tester);
          gate.complete();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(personal.sends, isEmpty);
        },
      );

      testWidgets('lock and unlock invalidate an outstanding paste', (
        tester,
      ) async {
        final field = await mount(tester);
        final gate = readGate = Completer<void>();
        await paste(tester);
        PersonalPrivacy.surfaceUnlocked = false;
        PersonalPrivacy.surfaceUnlocked = true;
        gate.complete();
        await tester.pump();
        expect(field.controller!.text, isEmpty);
        await unmount(tester);
      });
    });
  }
}
