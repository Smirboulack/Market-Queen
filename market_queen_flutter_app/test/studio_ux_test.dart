import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:market_queen/app_state.dart';
import 'package:market_queen/i18n/translator.dart';
import 'package:market_queen/core/clipboard_media.dart';
import 'package:market_queen/models/asset_library.dart';
import 'package:market_queen/models/canvas_feed.dart';
import 'package:market_queen/ui/main_window.dart';
import 'package:market_queen/ui/side_nav.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/canvas_view.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/studio/mentions.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/top_bar.dart';
import 'package:market_queen/ui/widgets/media_drop.dart';
import 'package:market_queen/ui/widgets/skeleton.dart';
import 'package:market_queen/ui/widgets/video_poster.dart';

import 'support/sandbox.dart';

/// The six studio complaints, each pinned by the thing that was actually wrong.
///
/// Four of them are only visible in a laid-out tree -- a caption under a tile,
/// a padding that has to track a bar's height, a glyph on a skeleton -- which is
/// exactly the kind of thing that regresses silently. The clipboard and the
/// reveal-in-folder calls end in the operating system and are not asserted here;
/// what can be is the decision made before the call.
void main() {
  // Never the real profile: see useSandboxConfig.
  useSandboxConfig();

  const window = Size(1420, 940);

  late AppState app;
  late Directory scratch;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The labels asserted below are the English sources. Without this the
    // catalogue follows the machine's own locale, and the whole file fails on
    // a French one.
    // The stored language too, not just the translator. AppState reapplies
    // `settings.uiLanguage` on every preference write, so a test that changes
    // any setting would otherwise snap the interface back to whatever this
    // machine has saved -- and every label asserted below is the English one.
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
    scratch = Directory.systemTemp.createTempSync('mq-studio-ux');
    // A reference clip would otherwise pull its poster frame with ffmpeg, and
    // a subprocess started under a test's fake clock outlives the test.
    VideoPosterImage.extraction = false;
  });

  tearDownAll(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  setUp(() => app.project.feed.clear());

  /// Points the clip shelf at a model the app has no schema for yet.
  ///
  /// Only fal's endpoints are read at run time, and nothing reads them in a
  /// test, so this is how to get the composer into the state it is in for the
  /// first second of a real session: the shelf offering everything it can take
  /// because no model has said otherwise yet. Restored afterwards -- the
  /// preference is written to disk and shared by every test in this file.
  Future<void> onUnreadModel(WidgetTester tester) async {
    app.settings
      ..setPref('videoProvider', 'fal-video')
      ..setPref(
        'videoModel',
        'fal-ai/kling-video/v3/standard/image-to-video',
      );
    addTearDown(() => app.settings
      ..setPref('videoProvider', null)
      ..setPref('videoModel', null));
  }

  // A real 1x1 PNG: the tiles put it through the image decoder, and a file of
  // random bytes turns the test into an exercise in error builders.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKm'
    'MIQAAAABJRU5ErkJggg==',
  );

  String file(String name) {
    final path = p.join(scratch.path, name);
    File(path).writeAsBytesSync(pixel);
    return path;
  }

  Future<void> pumpEditor(WidgetTester tester, {Size size = window}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            backgroundColor: theme.background,
            body: AdEditorPage(
              app: app,
              onGenerate: () {},
              onOpenRender: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Switches to a tab by its pill.
  Future<void> pickTab(WidgetTester tester, ComposerTab tab) async {
    await tester.tap(find.text(ComposerSpec.of(tab).label));
    await tester.pump();
    // A second frame, because the bar reports its own height after it has been
    // laid out and the canvas takes the new reserve on the frame after that.
    // Switching tabs changes which setting chips are on the bar, so the height
    // genuinely moves now where it used to be the same on every tab.
    await tester.pump();
  }

  /// Fires the drop the composer is wrapped in, which is the only way into its
  /// session-local reference list from outside.
  Future<void> drop(WidgetTester tester, List<String> paths) async {
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [for (final path in paths) DropItemFile(path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
  }

  TextEditingController promptController(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText).first).controller;

  group('handles', () {
    test('are numbered within their own kind, in the order sent', () {
      // The order the runner uploads in: every picture, then every clip, then
      // every recording. Numbering them in drop order instead would point the
      // prompt at the wrong file, which is worse than not naming them.
      expect(
        referenceHandles([
          'a.png',
          'b.mp4',
          'c.jpg',
          'd.mp3',
          'e.mov',
        ]),
        ['@Image1', '@Video1', '@Image2', '@Audio1', '@Video2'],
      );
    });

    test('the longest name wins, and a handle ends where a word ends', () {
      const handles = ['@Image1', '@Image10', '@Marie', '@Marie Curie'];

      String lit(String text) {
        final found = findMentions(text, handles);
        return [
          for (final match in found)
            text.substring(match.start, match.start + match.length),
        ].join('|');
      }

      expect(lit('a shot of @Marie Curie in the lab'), '@Marie Curie');
      expect(lit('@Marie walks in'), '@Marie');
      expect(lit('use @Image10 not @Image1'), '@Image10|@Image1');
      // Not a handle: a longer word that merely starts like one.
      expect(lit('@Image1x is nothing'), '');
      expect(lit('@Mariette is somebody else'), '');
      // Punctuation closes it.
      expect(lit('put @Marie, then @Image1.'), '@Marie|@Image1');
    });

    test('a prompt that names nothing mentions nothing', () {
      expect(promptMentions('a red car', '@Image1'), isFalse);
      expect(promptMentions('a red car like @Image1', '@Image1'), isTrue);
    });
  });

  group('the prompt colours what it recognises', () {
    testWidgets('a known handle is blue and an unknown one is not', (
      tester,
    ) async {
      final controller = MentionController(text: 'put @Image1 next to @Nobody')
        ..handles = ['@Image1'];

      final theme = MqTheme(dark: false);
      late BuildContext captured;
      await tester.pumpWidget(
        AppTheme(
          theme: theme,
          child: MaterialApp(
            theme: theme.material,
            home: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final span = controller.buildTextSpan(
        context: captured,
        style: const TextStyle(color: Color(0xFF171717)),
        withComposing: false,
      );

      final coloured = <String, Color?>{};
      span.visitChildren((child) {
        if (child is TextSpan && child.text != null) {
          coloured[child.text!] = child.style?.color;
        }
        return true;
      });

      expect(coloured['@Image1'], theme.info);
      // Everything else is left exactly as the field styled it -- an @word that
      // points at nothing has to look like it points at nothing.
      expect(coloured.keys.where((text) => text.contains('@Nobody')), isNotEmpty);
      for (final entry in coloured.entries) {
        if (entry.key == '@Image1') continue;
        expect(entry.value, isNot(theme.info), reason: entry.key);
      }
    });
  });

  group('the composer names what is attached to it', () {
    testWidgets('a dropped picture and clip carry their handles', (
      tester,
    ) async {
      // On a model whose schema has not landed: the bar takes all three kinds
      // until something says otherwise, which is the only state in which a
      // clip and a picture are in the well together. A model that has declared
      // itself narrows the well to what it will actually accept, and every
      // declared one takes a single opening frame and no clips at all.
      await onUnreadModel(tester);

      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.video);
      await drop(tester, [file('face.png'), file('take.mp4')]);

      expect(find.text('@Image1'), findsOneWidget);
      expect(find.text('@Video1'), findsOneWidget);

      // And the field knows them, which is what turns them blue as they are
      // typed rather than only labelling the tile.
      final controller = promptController(tester);
      expect(controller, isA<MentionController>());
      expect(
        (controller as MentionController).handles,
        containsAll(['@Image1', '@Video1']),
      );
    });

    testWidgets('pressing the handle types it into the prompt', (tester) async {
      // The handle and the thumbnail are two targets on purpose: one types the
      // name, the other opens the file. This is the typing half.
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await drop(tester, [file('one.png')]);

      await tester.tap(find.text('@Image1'));
      await tester.pump();

      expect(promptController(tester).text.trim(), '@Image1');
    });

    testWidgets('pressing the thumbnail opens it instead of typing', (
      tester,
    ) async {
      // The other half, and the one that could have gone wrong: a thumbnail and
      // the handle under it are two targets on the same little object, and a
      // press meant for one must never fire the other.
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await drop(tester, [file('open-me.png')]);

      final before = find.byType(LocalImage).evaluate().length;
      await tester.tap(find.byType(MediaTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The lightbox is up, and not one character was typed.
      expect(find.byType(LocalImage).evaluate().length, greaterThan(before));
      expect(promptController(tester).text, isEmpty);
    });

    testWidgets('the picture shelf refuses a clip outright', (tester) async {
      // Not a full shelf -- a category error. A picture model is handed one
      // still and drops everything else on the way out, so attaching a clip
      // there was an invitation to be ignored.
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await drop(tester, [file('kept.png'), file('refused.mp4')]);

      expect(find.text('@Image1'), findsOneWidget);
      expect(find.text('@Video1'), findsNothing);
    });

    testWidgets('the cast is addressable in the talking-actor mode only', (
      tester,
    ) async {
      // The modes do not mix: the talking actor runs on an avatar model that is
      // handed the actor and the scene, and the picture and clip shelves have
      // never heard of either. A blue "@Marie" on those would be a promise
      // nothing keeps.
      final actorId = app.actors.save(LibraryAsset(name: 'Marie Testeuse'));
      app.project.setActor(actorId);
      addTearDown(() {
        app.project.clearActor();
        app.actors.remove(actorId);
      });

      await pumpEditor(tester);
      const handle = '@Marie Testeuse';

      expect(
        (promptController(tester) as MentionController).handles,
        contains(handle),
        reason: 'talking actors',
      );

      await pickTab(tester, ComposerTab.image);
      expect(
        (promptController(tester) as MentionController).handles,
        isNot(contains(handle)),
        reason: 'pictures',
      );

      await pickTab(tester, ComposerTab.video);
      expect(
        (promptController(tester) as MentionController).handles,
        isNot(contains(handle)),
        reason: 'clips',
      );
    });
  });

  group('the feed clears the bar', () {
    testWidgets('the canvas reserves exactly the height the composer took', (
      tester,
    ) async {
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);

      double reserve() =>
          tester.widget<CanvasView>(find.byType(CanvasView)).bottomInset;
      double covered() =>
          window.height - tester.getRect(find.byType(ComposerTabBar)).top;

      expect(reserve(), moreOrLessEquals(covered(), epsilon: 0.5));

      // A reference row makes the bar taller. This is the bug: the reserve used
      // to be a constant, so anything that grew the bar grew it over the newest
      // result with no way to scroll it clear.
      final before = reserve();
      await drop(tester, [file('grow.png')]);
      await tester.pump();

      expect(reserve(), greaterThan(before));
      expect(reserve(), moreOrLessEquals(covered(), epsilon: 0.5));
    });

    testWidgets('opening the settings column moves nothing', (tester) async {
      // The panel is allowed to grow over the canvas and must cost the feed
      // nothing: it changes what the *next* generation will look like, so
      // shifting the ones already on screen is pure noise. Asserted at both
      // widths, because the panel is laid out two different ways -- beside the
      // bar when there is room, stacked over it when there is not -- and the
      // stacked one is what actually regressed.
      for (final size in [window, const Size(1040, 900)]) {
        // A fresh tree each time: re-pumping the editor keeps the composer's
        // own state, and the panel left open by the first pass would make the
        // second one measure a bar that was never shut.
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpEditor(tester, size: size);

        double reserve() =>
            tester.widget<CanvasView>(find.byType(CanvasView)).bottomInset;
        Rect feed() => tester.getRect(find.byType(CanvasView));

        final beforeReserve = reserve();
        final beforeFeed = feed();

        // Whichever shape the settings are in at this width: a row of text
        // buttons when there is room, one folded button when there is not.
        // Either way what opens lives in the overlay and costs the feed
        // underneath nothing, which is what this test has always been about.
        final folded = find.byTooltip('Settings');
        await tester.tap(
          folded.evaluate().isEmpty
              ? find.byTooltip('Change the model')
              : folded,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          reserve(),
          moreOrLessEquals(beforeReserve, epsilon: 0.5),
          reason: '$size',
        );
        expect(feed(), beforeFeed, reason: '$size');
      }
    });
  });

  group('a pending tile says what it is waiting for', () {
    testWidgets('a clip on its way shows its kind and a mark that turns', (
      tester,
    ) async {
      await pumpEditor(tester);

      app.project.feed.add(
        CanvasBatch(
          id: 'batch',
          kind: CanvasKind.video,
          prompt: 'a cat on a windowsill',
          createdAt: DateTime.now(),
          aspectRatio: '9:16',
          items: [CanvasItem(id: 'item')],
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonTile), findsOneWidget);
      // The two things a wait has to say: what is coming, and that something is
      // still happening. A shimmer alone read as "stuck" for minutes at a time.
      expect(find.text('Filming...'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SkeletonTile),
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a voice-over on its way gets the same treatment', (
      tester,
    ) async {
      await pumpEditor(tester);

      app.project.feed.add(
        CanvasBatch(
          id: 'voice',
          kind: CanvasKind.audio,
          prompt: 'read this',
          createdAt: DateTime.now(),
          items: [CanvasItem(id: 'item')],
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonBar), findsOneWidget);
      expect(find.text('Recording...'), findsOneWidget);
    });
  });

  group('the feed shows the work and nothing else', () {
    /// One finished picture in the canvas.
    Future<CanvasBatch> putResult(WidgetTester tester, {int items = 1}) async {
      final batch = CanvasBatch(
        id: 'done',
        kind: CanvasKind.image,
        prompt: 'a horse with wings',
        createdAt: DateTime.now(),
        modelLabel: 'Nano Banana 2',
        aspectRatio: '1:1',
        items: [
          for (var i = 0; i < items; ++i)
            CanvasItem(
              id: 'item$i',
              status: CanvasStatus.done,
              path: file('result$i.png'),
            ),
        ],
      );
      app.project.feed.add(batch);
      await tester.pump();
      return batch;
    }

    testWidgets('a single result is drawn the size of a chat picture', (
      tester,
    ) async {
      // It used to take its share of the whole column, so one 16:9 clip was
      // nine hundred pixels wide and a square still five hundred -- two results
      // and you were scrolling. A generation in the feed is a thumbnail you
      // open, the way a picture in a chat thread is.
      await pumpEditor(tester);

      for (final ratio in ['16:9', '1:1', '9:16']) {
        app.project.feed
          ..clear()
          ..add(
            CanvasBatch(
              id: 'one-$ratio',
              kind: CanvasKind.image,
              prompt: 'a horse with wings',
              createdAt: DateTime.now(),
              aspectRatio: ratio,
              items: [
                CanvasItem(
                  id: 'item',
                  status: CanvasStatus.done,
                  path: file('single-${ratio.replaceAll(':', '-')}.png'),
                ),
              ],
            ),
          );
        await tester.pump();

        final tile = tester.getRect(find.byType(LocalImage).first);
        expect(tile.width, lessThanOrEqualTo(330), reason: ratio);
        expect(tile.height, lessThanOrEqualTo(330), reason: ratio);
        // And not so small it is useless.
        expect(tile.shortestSide, greaterThan(150), reason: ratio);
      }
    });

    testWidgets('the prompt is not repeated over the result', (tester) async {
      // It is still sitting in the bar three inches below. A feed of pictures
      // with a caption over every one of them is a feed you read instead of
      // look at; the only text left is the text of something that failed.
      await pumpEditor(tester);
      await putResult(tester);

      // Scoped to the feed, and it has to be: the model name is also the value
      // on the settings row above the bar, which is a different claim about a
      // different thing.
      Finder inTheFeed(String text) =>
          find.descendant(of: find.byType(CanvasView), matching: find.text(text));

      expect(inTheFeed('a horse with wings'), findsNothing);

      // The model name *is* on the tile, and deliberately: it is the head of
      // the facts strip -- what made this, how long it is, what it cost -- which
      // is the one thing you cannot work out by looking at the picture. The
      // prompt is the thing that must not be repeated, because it is still
      // sitting in the bar three inches below.
      expect(inTheFeed('Nano Banana 2'), findsOneWidget);
    });

    testWidgets('an error still says what went wrong', (tester) async {
      await pumpEditor(tester);
      app.project.feed.add(
        CanvasBatch(
          id: 'broken',
          kind: CanvasKind.image,
          prompt: 'a horse with wings',
          createdAt: DateTime.now(),
          items: [
            CanvasItem(
              id: 'item',
              status: CanvasStatus.failed,
              error: 'HTTP 400 - image/png is not supported',
            ),
          ],
        ),
      );
      await tester.pump();

      expect(
        find.text('HTTP 400 - image/png is not supported'),
        findsOneWidget,
      );
      expect(find.text('a horse with wings'), findsNothing);
    });

    testWidgets('right-click offers the four file actions', (tester) async {
      await pumpEditor(tester);
      await putResult(tester);

      await tester.tapAt(
        tester.getCenter(find.byType(LocalImage).first),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      for (final label in [
        'Show file',
        'Save as...',
        'Copy the picture',
        'Remove from the canvas',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('removing takes the one tile, not the whole batch', (
      tester,
    ) async {
      // The unit somebody acts on is the tile: asking for three pictures and
      // wanting rid of the second is the ordinary case.
      await pumpEditor(tester);
      final batch = await putResult(tester, items: 3);

      await tester.tapAt(
        tester.getCenter(find.byType(LocalImage).at(1)),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Remove from the canvas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(batch.items.map((item) => item.id), ['item0', 'item2']);
      expect(app.project.feed.byId('done'), isNotNull);
    });
  });

  group('the clip shelf says how much it will take', () {
    testWidgets('the well offers what the chosen model actually takes', (
      tester,
    ) async {
      // The wells used to be drawn from fal's platform ceiling -- thirty
      // pictures, ten clips, ten recordings -- because that was the answer
      // while a model's schema had not been read. Called directly, every model
      // states its own limits before anything is dropped, so the well is now
      // built from the model rather than from a platform.
      app.settings
        ..setPref('videoProvider', 'bytedance-video')
        ..setPref('videoModel', 'dreamina-seedance-2-5-260628');
      // Put back afterwards. The preference is written to disk and shared by
      // every test in the file, so a model picked here to prove a point was
      // still picked three tests later -- which is what made the two that
      // follow fail on a clean checkout.
      addTearDown(() => app.settings
        ..setPref('videoProvider', null)
        ..setPref('videoModel', null));

      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.video);

      // Seedance 2.5 takes thirty stills and ten recordings, both as base64.
      // It declares a reference-clip list as well, but only as a hosted link,
      // and this app has nowhere to put one -- so that is the one drop the well
      // does not offer, because it would have to be refused at send.
      //
      // Which of the three is closed is read off `inlinesImages` /
      // `inlinesAudios` / `inlinesVideos` in `ModelCapabilities.declared`, not
      // out of this test: a provider that starts accepting inline clips should
      // gain the button, and this line is what says which way round it is today.
      //
      // Looked up through `tr` rather than written out: the catalogue that
      // happens to be loaded depends on the machine's language, and this is a
      // test about which buttons are there, not about which language they are
      // labelled in.
      expect(find.byTooltip(tr('Add pictures')), findsOneWidget);
      expect(find.byTooltip(tr('Add clips')), findsNothing);
      expect(find.byTooltip(tr('Add a recording')), findsOneWidget);

      await drop(tester, [file('a.png'), file('b.png')]);
      expect(find.textContaining('2/'), findsOneWidget);
    });

    testWidgets('each kind has a button of its own, and only its own', (
      tester,
    ) async {
      await onUnreadModel(tester);
      await pumpEditor(tester);

      // The shelf's own ceiling, before a model narrows it.
      await pickTab(tester, ComposerTab.video);
      expect(find.byTooltip('Add pictures'), findsOneWidget);
      expect(find.byTooltip('Add clips'), findsOneWidget);
      expect(find.byTooltip('Add a recording'), findsOneWidget);

      // The picture shelf takes pictures. A clip handed to it is dropped on
      // the way out, so there is no button offering to attach one.
      await pickTab(tester, ComposerTab.image);
      expect(find.byTooltip('Add pictures'), findsOneWidget);
      expect(find.byTooltip('Add clips'), findsNothing);
      expect(find.byTooltip('Add a recording'), findsNothing);
    });
  });

  group('the nav is a way back to the work', () {
    late String projectId;

    Future<void> pumpWindow(WidgetTester tester) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final theme = MqTheme(dark: false);
      await tester.pumpWidget(
        AppTheme(
          theme: theme,
          child: MaterialApp(
            theme: theme.material,
            home: Scaffold(body: MainWindow(app: app)),
          ),
        ),
      );
      await tester.pump();
    }

    Finder navRow(String label) =>
        find.descendant(of: find.byType(SideNav), matching: find.text(label));

    Finder crumb(String label) =>
        find.descendant(of: find.byType(TopBar), matching: find.text(label));

    setUp(() {
      projectId = app.workspace.createProject('Nav project').id;
      app.workspace.createAd(projectId, 'Nav ad');
    });

    tearDown(() => app.workspace.removeProject(projectId));

    /// Into Create UGC, then onto the ad.
    ///
    /// It used to be two steps down a tree of projects. The tree is gone -- the
    /// nav's expansion is one flat list of every ad there is, newest first, and
    /// the project an ad is filed under is storage plumbing that is never shown
    /// -- so the first press is stepping into the section rather than opening a
    /// folder.
    ///
    /// Scoped to the nav, because the list in the middle of the page carries the
    /// same names.
    Future<void> openTheAd(WidgetTester tester) async {
      await tester.tap(navRow('Create UGC'));
      await tester.pump();
      await tester.tap(navRow('Nav ad'));
      await tester.pump();
    }

    testWidgets('Create UGC goes back to the ad you were in', (tester) async {
      // It used to be a way to the top of the tree and nothing else, so
      // stepping out to Settings meant walking back down two screens to the ad
      // you had been working on all morning.
      await pumpWindow(tester);
      await openTheAd(tester);
      expect(crumb('Nav ad'), findsOneWidget);

      // Out of the section first: while the nav is stepped into Create UGC it
      // shows that list and nothing else, so the other rows are not reachable
      // until the back arrow puts them back. That is the section's whole point
      // and not something to route around.
      await tester.tap(find.byTooltip('Back to the menu'));
      await tester.pump();

      await tester.tap(navRow('Settings'));
      await tester.pump();

      await tester.tap(navRow('Create UGC'));
      await tester.pump();
      expect(crumb('Nav ad'), findsOneWidget);
    });

    testWidgets('an ad row renames itself where it stands', (tester) async {
      await pumpWindow(tester);
      await openTheAd(tester);

      await tester.tap(find.byTooltip('Rename this ad'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rename the ad'), findsOneWidget);
    });
  });

  group('pasted text that is really a file', () {
    test('a media path is picked out, prose is left alone', () {
      final picture = file('pasted.png');

      expect(ClipboardMedia.pathsIn(picture), [picture]);
      // Quoted the way a shell or a browser hands it over.
      expect(ClipboardMedia.pathsIn('"$picture"'), [picture]);
      expect(ClipboardMedia.pathsIn(Uri.file(picture).toString()), [picture]);

      expect(ClipboardMedia.pathsIn('a sentence about a cat'), isEmpty);
      // Right shape, no such file: still a sentence as far as the bar knows.
      expect(
        ClipboardMedia.pathsIn(p.join(scratch.path, 'missing.png')),
        isEmpty,
      );
      // A file that is not media stays text.
      expect(ClipboardMedia.pathsIn(file('notes.txt')), isEmpty);
    });
  });
}
