import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'asset_library_page.dart';
import 'dialogs/asset_editor.dart';
import 'examples_page.dart';
import 'library_page.dart';
import 'models_page.dart';
import 'render_view.dart';
import 'settings_page.dart';
import 'side_nav.dart';
import 'studio/ad_editor_page.dart';
import 'studio/ads_page.dart';
import 'studio/projects_page.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'widgets/mq_dialog.dart';

/// The window: navigation on the left, a crumb trail across the top, the
/// current page filling the rest.
///
/// The studio is the only page with somewhere to go: projects, then the ads in
/// one, then the ad itself, then the run. The window owns that position because
/// the crumb trail is what walks back up it, and the trail lives up here.
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.app});

  final AppState app;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  static const _studio = 0;
  static const _library = 1;
  static const _actors = 2;
  static const _decors = 3;
  static const _examples = 4;
  static const _models = 5;
  static const _settings = 6;

  int _currentPage = _studio;

  /// Where in the studio we are. Empty project means the project list; a
  /// project with no ad means that project's ads.
  String _projectId = '';
  String _adId = '';

  /// Whether the studio is showing the run rather than the ad.
  bool _rendering = false;

  AppState get app => widget.app;

  List<NavEntry> get _entries => [
    NavEntry(label: tr('Studio'), icon: 'clapperboard-line', page: _studio),
    NavEntry(label: tr('Library'), icon: 'movie-2-line', page: _library),
    NavEntry(label: tr('Actors'), icon: 'user-line', page: _actors),
    NavEntry(label: tr('Décors'), icon: 'image-line', page: _decors),
    NavEntry(label: tr('Examples'), icon: 'lightbulb-line', page: _examples),
    NavEntry(label: tr('Models'), icon: 'layout-line', page: _models),
    NavEntry(label: tr('Settings'), icon: 'settings-3-line', page: _settings),
  ];

  // ---- studio navigation ---------------------------------------------------

  void _openProject(String id) {
    app.workspace.closeAd();
    setState(() {
      _projectId = id;
      _adId = '';
      _rendering = false;
    });
  }

  void _openAd(String projectId, String adId) {
    app.workspace.openAd(projectId, adId);
    setState(() {
      _currentPage = _studio;
      _projectId = projectId;
      _adId = adId;
      _rendering = false;
    });
  }

  void _backToProjects() {
    app.workspace.closeAd();
    setState(() {
      _projectId = '';
      _adId = '';
      _rendering = false;
    });
  }

  void _generate() {
    setState(() => _rendering = true);
    app.pipeline.start(app.request());
  }

  /// A second ad in the same project, from the render view. The one that just
  /// rendered stays exactly as it was.
  Future<void> _newSiblingAd() async {
    final projectId = _projectId;
    if (projectId.isEmpty) return;

    final name = await askForName(
      context,
      title: tr('New UGC ad'),
      subtitle: tr('A second angle on the same product, in this project.'),
      label: tr('Ad name'),
      placeholder: tr('e.g. Morning routine hook'),
      confirmLabel: tr('Create'),
      initial: app.workspace.suggestedAdName(projectId),
    );
    if (name == null) return;

    final ad = app.workspace.createAd(projectId, name);
    _openAd(projectId, ad.id);
  }

  /// Which of the studio's four screens is showing.
  int get _studioLevel {
    if (_projectId.isEmpty) return 0;
    if (_adId.isEmpty) return 1;
    return _rendering ? 3 : 2;
  }

  // ---- the trail -----------------------------------------------------------

  List<Crumb> _crumbs() {
    switch (_currentPage) {
      case _library:
        return [Crumb(tr('Library'))];
      case _actors:
        return [Crumb(tr('Actors'))];
      case _decors:
        return [Crumb(tr('Décors'))];
      case _examples:
        return [Crumb(tr('Examples'))];
      case _models:
        return [Crumb(tr('Models'))];
      case _settings:
        return [Crumb(tr('Settings'))];
    }

    final project = app.workspace.project(_projectId);
    final ad = project?.ad(_adId);

    return [
      Crumb(
        tr('Studio'),
        onTap: _projectId.isEmpty ? null : _backToProjects,
      ),
      if (project != null)
        Crumb(
          project.name,
          onTap: _adId.isEmpty
              ? null
              : () {
                  app.workspace.closeAd();
                  setState(() {
                    _adId = '';
                    _rendering = false;
                  });
                },
        ),
      if (ad != null)
        Crumb(
          ad.name,
          onTap: _rendering ? () => setState(() => _rendering = false) : null,
        ),
      if (_rendering) Crumb(tr('Render')),
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
            onPicked: (index) => setState(() => _currentPage = index),
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
                      _studioStack(),
                      LibraryPage(app: app),
                      AssetLibraryPage(app: app, kind: AssetKind.actor),
                      AssetLibraryPage(app: app, kind: AssetKind.decor),
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
        ProjectsPage(app: app, onOpen: _openProject),
        // Built only once there is a project to build them for; an IndexedStack
        // builds every child, and both of these are meaningless without one.
        if (_projectId.isEmpty)
          const SizedBox.shrink()
        else
          AdsPage(
            key: ValueKey('ads:$_projectId'),
            app: app,
            projectId: _projectId,
            onOpen: (adId) => _openAd(_projectId, adId),
          ),
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
        RenderView(
          app: app,
          onBack: () => setState(() => _rendering = false),
          onNewAd: _projectId.isEmpty ? null : _newSiblingAd,
        ),
      ],
    );
  }
}
