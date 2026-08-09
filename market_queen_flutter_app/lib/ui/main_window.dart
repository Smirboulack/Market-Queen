import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/translator.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'side_nav.dart';
import 'studio_page.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'widgets/buttons.dart';

/// The window: navigation on the left, a crumb trail across the top, the current
/// page filling the rest.
///
/// The studio has two faces and the window owns which one is showing, because
/// the button that switches between them lives up here: Generate is a
/// window-level action, not something buried at the bottom of a form.
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.app});

  final AppState app;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  static const _studio = 0;
  static const _library = 1;
  static const _settings = 2;

  int _currentPage = _studio;

  /// Whether the studio is showing the run rather than the script.
  bool _rendering = false;

  List<NavEntry> get _entries => [
    NavEntry(label: tr('Studio'), icon: 'clapperboard-line', page: _studio),
    // No page behind these two yet. They stay on the list because the shape of
    // the app should be readable before all of it exists -- and because a nav
    // that grows entries later moves everything under them.
    NavEntry(label: tr('Projects'), icon: 'folder-line', soon: true),
    NavEntry(label: tr('Library'), icon: 'movie-2-line', page: _library),
    NavEntry(label: tr('Templates'), icon: 'layout-line', soon: true),
    NavEntry(label: tr('Settings'), icon: 'settings-3-line', page: _settings),
  ];

  void _generate() {
    setState(() => _rendering = true);
    widget.app.pipeline.start(widget.app.project.toRequest());
  }

  List<Crumb> _crumbs() {
    switch (_currentPage) {
      case _library:
        return [Crumb(tr('Library'))];
      case _settings:
        return [Crumb(tr('Settings'))];
      default:
        final name = '${widget.app.project.product['name'] ?? ''}'.trim();
        return [
          Crumb(tr('Studio')),
          Crumb(name.isEmpty ? tr('New project') : name),
          // One draft at a time, so the ad is always the first one. It becomes a
          // way back as soon as there is somewhere to come back from.
          Crumb(
            tr('Ad #1'),
            onTap: _rendering ? () => setState(() => _rendering = false) : null,
          ),
          if (_rendering) Crumb(tr('Render')),
        ];
    }
  }

  Widget? _action() {
    if (_currentPage != _studio) return null;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.app.project, widget.app.pipeline]),
      builder: (context, _) {
        final project = widget.app.project;
        final pipeline = widget.app.pipeline;
        final missing = project.missing;

        return PrimaryButton(
          text: pipeline.running ? tr('Generating…') : tr('Generate'),
          icon: 'magic-line',
          loading: pipeline.running,
          enabled: project.complete && !pipeline.running,
          //: %1 is a list like "a product, an actor"
          tooltip: missing.isEmpty
              ? ''
              : tr('Still needs %1.').arg(missing.join(', ')),
          onPressed: _generate,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ColoredBox(
      color: mq.background,
      child: Row(
        children: [
          SideNav(
            app: widget.app,
            entries: _entries,
            currentPage: _currentPage,
            onPicked: (index) => setState(() => _currentPage = index),
          ),
          Expanded(
            child: Column(
              children: [
                ListenableBuilder(
                  // The middle crumb is the product's name, which is typed on
                  // the page underneath it.
                  listenable: widget.app.project,
                  builder: (context, _) =>
                      TopBar(crumbs: _crumbs(), trailing: _action()),
                ),
                Expanded(
                  // IndexedStack, not a switch: each page keeps its scroll
                  // position and its half-typed fields when you step away and
                  // come back.
                  child: IndexedStack(
                    index: _currentPage,
                    children: [
                      StudioPage(
                        app: widget.app,
                        rendering: _rendering,
                        onBackToScript: () =>
                            setState(() => _rendering = false),
                      ),
                      LibraryPage(app: widget.app),
                      SettingsPage(app: widget.app),
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
}
