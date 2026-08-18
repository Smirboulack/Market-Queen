import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/asset_library.dart' show AssetKind;
import 'asset_library_page.dart';
import 'examples_page.dart';
import 'home_page.dart';
import 'icons.dart';
import 'library_page.dart';
import 'models_page.dart';
import 'scenario_page.dart';
import 'settings_page.dart';
import 'side_nav.dart';
import 'studio/ad_editor_page.dart';
import 'studio/ad_list.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'widgets/buttons.dart';
import 'widgets/mq_dialog.dart';

/// The window: navigation on the left, a crumb trail across the top, the
/// current page filling the rest.
///
/// Create UGC is the only section with somewhere to go -- the ad, then its run
/// -- and the only one you step *into*: opening it replaces the nav with its
/// own list of ads until the back arrow is pressed. The window owns that
/// position because the crumb trail is what walks back up it, and the trail
/// lives up here.
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.app});

  final AppState app;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  static const _home = 0;
  static const _studio = 1;
  static const _scenario = 2;
  static const _library = 3;
  static const _actors = 4;
  static const _scenes = 5;
  static const _examples = 6;
  static const _models = 7;
  static const _settings = 8;

  /// Home, not the studio. The app opens on a page that says what it is and
  /// what has to be set up before any of it works, rather than on an empty
  /// canvas with a prompt bar under it and no key behind either.
  int _currentPage = _home;

  /// The ad the editor is on, and the project it is filed under. The project is
  /// storage plumbing now -- see [Workspace.home] -- and is never shown.
  String _projectId = '';
  String _adId = '';

  /// Whether the nav has been stepped into Create UGC. While it is, the column
  /// is that section's own list and the back arrow is the way out.
  bool _inSection = false;

  AppState get app => widget.app;

  List<NavEntry> get _entries => [
    NavEntry(label: tr('Home'), icon: 'home-line', page: _home),
    NavEntry(
      label: tr('Create UGC'),
      icon: 'clapperboard-line',
      page: _studio,
      expansion: AdList(
        app: app,
        openAdId: _adId,
        onNew: _newAd,
        onOpen: _openAd,
        onRename: _renameAd,
      ),
    ),
    NavEntry(label: tr('Storyboard'), icon: 'layout-line', page: _scenario),
    NavEntry(label: tr('Library'), icon: 'movie-2-line', page: _library),
    NavEntry(label: tr('Actors'), icon: 'user-line', page: _actors),
    NavEntry(label: tr('Scenes'), icon: 'scene-line', page: _scenes),
    NavEntry(label: tr('Examples'), icon: 'lightbulb-line', page: _examples),
    NavEntry(label: tr('Models'), icon: 'sound-module-line', page: _models),
    NavEntry(label: tr('Settings'), icon: 'settings-3-line', page: _settings),
  ];

  /// The Create UGC entry, which is the only one you can step into.
  NavEntry get _section =>
      _entries.firstWhere((entry) => entry.page == _studio);

  // ---- studio navigation ---------------------------------------------------

  void _openAd(String projectId, String adId) {
    app.workspace.openAd(projectId, adId);
    setState(() {
      _currentPage = _studio;
      _projectId = projectId;
      _adId = adId;
    });
  }

  /// A nav row was pressed.
  ///
  /// Every one of them is "go to that section", plus this: Create UGC also
  /// steps the column into its own list of ads, because that list is what you
  /// are choosing between once you are in there and the other sections are
  /// not.
  void _pickPage(int index) {
    setState(() {
      _currentPage = index;
      _inSection = index == _studio;
    });
  }

  Future<void> _renameAd(String projectId, String adId) async {
    final ad = app.workspace.ad(projectId, adId);
    if (ad == null) return;

    final name = await askForName(
      context,
      title: tr('Rename the ad'),
      label: tr('Ad name'),
      placeholder: ad.name,
      confirmLabel: tr('Rename'),
      initial: ad.name,
    );
    if (name != null) app.workspace.renameAd(projectId, adId, name);
  }

  /// Starts a run and stays where it is.
  ///
  /// It used to navigate to a render view, which meant every generation threw
  /// you off the page you were working on for as long as it took. The progress
  /// is in the canvas now, as a tile filling itself in, and that screen is
  /// gone: everything it offered -- the file, another take, the cost -- is on
  /// the tile itself.
  void _generate() => app.pipeline.start(app.request());

  /// Asks for a name and opens the ad it made.
  ///
  /// One dialog, not two: there is no folder to make first any more, and the
  /// ad is filed wherever the workspace keeps them.
  Future<void> _newAd() async {
    final name = await askForName(
      context,
      title: tr('New UGC ad'),
      subtitle: tr('One ad. Write it, cast it, shoot it.'),
      label: tr('Ad name'),
      placeholder: tr('e.g. Morning routine hook'),
      confirmLabel: tr('Create'),
      initial: app.workspace.suggestedName(),
    );
    if (name == null) return;

    final home = app.workspace.home;
    final ad = app.workspace.createAd(home.id, name);
    _openAd(home.id, ad.id);
  }

  /// Which of the studio's two screens is showing: the invitation to make an
  /// ad, or the ad.
  int get _studioLevel => _adId.isEmpty ? 0 : 1;

  // ---- the trail -----------------------------------------------------------

  List<Crumb> _crumbs() {
    switch (_currentPage) {
      case _home:
        return [Crumb(tr('Home'))];
      case _scenario:
        return [Crumb(tr('Storyboard'))];
      case _library:
        return [Crumb(tr('Library'))];
      case _actors:
        return [Crumb(tr('Actors'))];
      case _scenes:
        return [Crumb(tr('Scenes'))];
      case _examples:
        return [Crumb(tr('Examples'))];
      case _models:
        return [Crumb(tr('Models'))];
      case _settings:
        return [Crumb(tr('Settings'))];
    }

    // One level now rather than four: the ad. The project that used to sit
    // above it was a folder nobody asked for, and the run that used to sit
    // below it is the canvas.
    final ad = app.workspace.ad(_projectId, _adId);

    return [
      Crumb(tr('Create UGC')),
      if (ad != null) Crumb(ad.name),
    ];
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ColoredBox(
      color: mq.background,
      child: Row(
        children: [
          SideNav(
            app: app,
            entries: _entries,
            currentPage: _currentPage,
            onPicked: _pickPage,
            openSection: _inSection ? _section : null,
            onCloseSection: () => setState(() => _inSection = false),
          ),
          Expanded(
            child: Column(
              children: [
                ListenableBuilder(
                  // The middle crumbs are names the pages underneath rename.
                  listenable: app.workspace,
                  builder: (context, _) => TopBar(crumbs: _crumbs()),
                ),
                Expanded(
                  // IndexedStack, not a switch: each page keeps its scroll
                  // position and its half-typed fields when you step away and
                  // come back.
                  child: IndexedStack(
                    index: _currentPage,
                    children: [
                      HomePage(
                        app: app,
                        onCreateUgc: () => _pickPage(_studio),
                        onStoryboard: () => _pickPage(_scenario),
                        onModels: () => _pickPage(_models),
                      ),
                      _studioStack(),
                      ScenarioPage(app: app),
                      LibraryPage(app: app),
                      AssetLibraryPage(app: app, kind: AssetKind.actor),
                      AssetLibraryPage(app: app, kind: AssetKind.scene),
                      ExamplesPage(app: app, onOpenAd: _openAd),
                      ModelsPage(app: app),
                      SettingsPage(app: app),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studioStack() {
    return IndexedStack(
      index: _studioLevel,
      children: [
        _NoAdYet(onNew: _newAd),
        if (_adId.isEmpty)
          const SizedBox.shrink()
        else
          // Keyed on the ad: opening a different one has to start the editor's
          // fields from that ad rather than resync them behind the user.
          AdEditorPage(
            key: ValueKey('ad:$_adId'),
            app: app,
            onGenerate: _generate,
          ),
      ],
    );
  }
}

/// What Create UGC shows before there is an ad open: one sentence and one
/// button, pointing at the same list that is already in the column beside it.
class _NoAdYet extends StatelessWidget {
  const _NoAdYet({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MqIcon('clapperboard-line', size: 28, color: mq.textTertiary),
            const SizedBox(height: MqTheme.gapLarge),
            Text(
              tr('Pick an ad on the left, or start a new one.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mq.textTertiary,
                fontSize: MqTheme.fontBody,
                height: MqTheme.lineBody,
              ),
            ),
            const SizedBox(height: MqTheme.gapLarge),
            PrimaryButton(text: tr('New UGC ad'), onPressed: onNew),
          ],
        ),
      ),
    );
  }
}
