// SPDX-License-Identifier: AGPL-3.0-or-later
// Actual merged-chat composer, fictional offline rooms. No sends or recording.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/l10n/l10n.dart';
import 'package:chatloom/pages/chat/input_bar.dart';
import 'package:chatloom/pages/chat/voice_record_button.dart';
import 'package:chatloom/personal/merged_chat_page.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:chatloom/utils/platform_infos.dart';
import 'package:chatloom/widgets/matrix.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart'
    show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_core/personal_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conversation_test_support.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    PlatformInfos.debugPlatformCanRecord = true;
    PersonalPrivacy.surfaceUnlocked = true;
    PersonalPrivacy.surfaceForeground = true;
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    PlatformInfos.debugPlatformCanRecord = null;
  });

  Finder field() => find.descendant(
    of: find.byType(InputBar),
    matching: find.byType(TextField),
  );

  Future<ConversationPersonal> mount(
    WidgetTester tester, {
    required double width,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.reset);
    final client = ConversationClient();
    final messenger = ConversationRoom(
      client,
      '!space-messenger:example.invalid',
      network: 'messenger',
    );
    final instagram = ConversationRoom(
      client,
      '!space-instagram:example.invalid',
      network: 'instagram',
    );
    messenger.message(r'$hello', 'See you tomorrow!');
    final personal = ConversationPersonal(client);
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
          debugShowCheckedModeBanner: false,
          theme: NotionTheme.build(
            brightness,
          ).copyWith(platform: TargetPlatform.iOS),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture-input-space'),
            child: MergedChatPage(
              personal: personal,
              group: PersonGroup(
                id: 'space-person',
                name: 'Fictional person',
                members: [personal.ref(messenger), personal.ref(instagram)],
                defaultRoomId: messenger.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return personal;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('phone input has room at $width / $scale text', (
        tester,
      ) async {
        final personal = await mount(tester, width: width, scale: scale);
        expect(
          tester.getSize(field()).width,
          // Includes the full conversation frame and source selector, not
          // just the composer's own row padding.
          greaterThanOrEqualTo(width - 208),
        );
        expect(
          tester.getSize(find.byTooltip('More message actions')),
          const Size.square(48),
        );
        expect(
          tester.getSize(find.byType(VoiceRecordButton)),
          const Size.square(48),
        );
        expect(find.byTooltip('Dictate a message').hitTestable(), findsNothing);
        expect(
          find.byTooltip('Emoji, GIFs and stickers').hitTestable(),
          findsNothing,
        );
        await tester.tap(field());
        await tester.pump();
        final editor = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(EditableText),
        );
        final editorState = tester.state(editor);
        final input = tester.widget<TextField>(field());
        final widthBefore = tester.getSize(field()).width;
        await tester.tap(find.byTooltip('More message actions'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Hide message actions'), findsOneWidget);
        expect(tester.state(editor), same(editorState));
        expect(input.focusNode!.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Fictional draft',
            selection: TextSelection(baseOffset: 3, extentOffset: 8),
            composing: TextRange(start: 0, end: 8),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('More message actions'), findsOneWidget);
        expect(tester.state(editor), same(editorState));
        expect(input.focusNode!.hasFocus, isTrue);
        expect(input.controller!.text, 'Fictional draft');
        expect(
          input.controller!.selection,
          const TextSelection(baseOffset: 3, extentOffset: 8),
        );
        expect(
          input.controller!.value.composing,
          const TextRange(start: 0, end: 8),
        );
        expect(
          tester.getSize(field()).width,
          greaterThanOrEqualTo(widthBefore),
        );
        expect(personal.sends, isEmpty);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  }

  testWidgets('responsive controls preserve the active editor and IME', (
    tester,
  ) async {
    final personal = await mount(tester, width: 599);
    await tester.tap(field());
    await tester.pump();
    final editor = find.descendant(
      of: find.byType(InputBar),
      matching: find.byType(EditableText),
    );
    final state = tester.state(editor);
    final input = tester.widget<TextField>(field());
    const value = TextEditingValue(
      text: 'Fictional draft',
      selection: TextSelection(baseOffset: 3, extentOffset: 8),
      composing: TextRange(start: 0, end: 8),
    );
    input.controller!.value = value;
    await tester.pump();
    for (final width in [600.0, 599.0, 430.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      expect(tester.state(editor), same(state));
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.value, value);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    }
    expect(personal.sends, isEmpty);
    await unmount(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('production composer capture in ${brightness.name}', (
      tester,
    ) async {
      await mount(tester, width: 390, brightness: brightness);
      final directory = Platform.environment['CHATLOOM_COMPOSER_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-input-space')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/composer-input-space-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
