import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import '../models/asset_library.dart' show AssetKind;
import 'asset_library_page.dart';
import 'examples_page.dart';
import 'library_page.dart';
import 'models_page.dart';
import 'render_view.dart';
import 'settings_page.dart';
import 'side_nav.dart';
import 'studio/ad_editor_page.dart';
import 'studio/ads_page.dart';
import 'studio/projects_page.dart';
import 'studio/studio_tree.dart';
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
  static const _scenes = 3;
  static const _examples = 4;
  static const _models = 5;
  static const _settings = 6;

  int _currentPage = _studio;

  /// Where in the studio we are. Empty project means the project list; a
  /// project with no ad means that project's ads.
  String _projectId = '';
  String _adId = '';

  /// The last ad that was open, which is what "Studio" goes back to.
  ///
  /// The nav row used to be a way to the top of the tree and nothing else, so
  /// stepping out to Settings and back -- or up to the project list to check
  /// something -- meant walking back down two screens to the ad you had been
  /// working on for the last hour. A section in a nav should return you to your
  /// place in it.
  String _lastProjectId = '';
  String _lastAdId = '';

  /// Whether the studio is showing the run rather than the ad.
  bool _rendering = false;

  AppState get app => widget.app;

  List<NavEntry> get _entries => [
    NavEntry(
      label: tr('Studio'),
      icon: 'clapperboard-line',
      page: _studio,
      expansion: StudioTree(
        app: app,
        openProjectId: _projectId,
        openAdId: _adId,
        onNewProject: _newProject,
        onNewAd: _newAd,
        onOpenProject: _openProject,
        onOpenAd: _openAd,
        onRenameProject: _renameProject,
        onRenameAd: _renameAd,
      ),
    ),
    NavEntry(label: tr('Library'), icon: 'movie-2-line', page: _library),
    NavEntry(label: tr('Actors'), icon: 'user-line', page: _actors),
    NavEntry(label: tr('Scenes'), icon: 'scene-line', page: _scenes),
    NavEntry(label: tr('Examples'), icon: 'lightbulb-line', page: _examples),
    NavEntry(label: tr('Models'), icon: 'layout-line', page: _models),
    NavEntry(label: tr('Settings'), icon: 'settings-3-line', page: _settings),
  ];

  // ---- studio navigation ---------------------------------------------------

  void _openProject(String id) {
    app.workspace.closeAd();
    setState(() {
      _currentPage = _studio;
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
      _lastProjectId = projectId;
      _lastAdId = adId;
      _rendering = false;
    });
  }

  /// A nav row was pressed.
  ///
  /// Every one of them is "go to that section" except this one detail: the
  /// studio remembers where you were in it, so pressing Studio from anywhere
  /// puts you back in the ad you were making rather than at the list of
  /// projects. Walking up to the list is what the crumb trail is for, and it is
  /// a thing you ask for far less often than you ask to get back to work.
  void _pickPage(int index) {
    if (index != _studio) {
      setState(() => _currentPage = index);
      return;
    }

    final remembered = app.workspace.ad(_lastProjectId, _lastAdId);
    if (_adId.isEmpty && remembered != null) {
      _openAd(_lastProjectId, _lastAdId);
      return;
    }
    setState(() => _currentPage = _studio);
  }

  Future<void> _renameProject(String id) async {
    final project = app.workspace.project(id);
    if (project == null) return;

    final name = await askForName(
      context,
      title: tr('Rename the project'),
      label: tr('Project name'),
      placeholder: project.name,
      confirmLabel: tr('Rename'),
      initial: project.name,
    );
    if (name != null) app.workspace.renameProject(id, name);
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

  void _backToProjects() {
    app.workspace.closeAd();
    setState(() {
      _projectId = '';
      _adId = '';
      _rendering = false;
    });
  }

  /// Starts a run and stays where it is.
  ///
  /// It used to navigate to the render view, which meant every generation threw
  /// you off the page you were working on for as long as it took. The progress
  /// is in the canvas now, as a tile filling itself in; this screen is still
  /// reachable, from that tile, for the shot list and the log.
  void _generate() => app.pipeline.start(app.request());

  void _openRender() => setState(() => _rendering = true);

  /// Asks for a name and opens what it made. Reached from the nav tree, and --
  /// for the ad -- from the render view, so a second angle on the same product
  /// never means walking back up to the list.
  Future<void> _newProject() async {
    final name = await askForName(
      context,
      title: tr('New project'),
      subtitle: tr('A folder for the ads of one product or one campaign.'),
      label: tr('Project name'),
      placeholder: tr('e.g. Lumen glow serum'),
      confirmLabel: tr('Create'),
      initial: app.workspace.suggestedProjectName(),
    );
    if (name == null) return;

    _openProject(app.workspace.createProject(name).id);
  }

  Future<void> _newAd(String projectId) async {
    if (app.workspace.project(projectId) == null) return;

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

  /// A second ad in the same project, from the render view. The one that just
  /// rendered stays exactly as it was.
  Future<void> _newSiblingAd() => _newAd(_projectId);

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
      case _scenes:
        return [Crumb(tr('Scenes'))];
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
            onPicked: _pickPage,
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
            onOpenRender: _openRender,
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
