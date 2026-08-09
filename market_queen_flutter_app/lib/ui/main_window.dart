import 'package:flutter/material.dart';

import '../app_state.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'side_nav.dart';
import 'studio_page.dart';
import 'theme.dart';

/// The window: navigation on the left, the current page filling the rest.
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.app});

  final AppState app;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;

    return ColoredBox(
      color: mq.background,
      child: Row(
        children: [
          SideNav(
            app: widget.app,
            currentIndex: _currentIndex,
            onPicked: (index) => setState(() => _currentIndex = index),
          ),
          Expanded(
            // IndexedStack, not a switch: each page keeps its scroll position
            // and its half-typed fields when you step away and come back.
            child: IndexedStack(
              index: _currentIndex,
              children: [
                StudioPage(app: widget.app),
                LibraryPage(app: widget.app),
                SettingsPage(app: widget.app),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
