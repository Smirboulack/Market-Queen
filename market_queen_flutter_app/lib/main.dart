import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'core/title_bar.dart';
import 'ui/main_window.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1900, 1200),
      minimumSize: Size(1020, 700),
      center: true,
      title: 'Market Queen - SegfaultLabs',
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.maximize(); // <-- ajout ici
    },
  );

  final app = await AppState.create();
  await TitleBar.setDark(app.settings.darkMode);
  runApp(MarketQueenApp(app: app));
}

class MarketQueenApp extends StatefulWidget {
  const MarketQueenApp({super.key, required this.app});

  final AppState app;

  @override
  State<MarketQueenApp> createState() => _MarketQueenAppState();
}

class _MarketQueenAppState extends State<MarketQueenApp> {
  late bool _dark = widget.app.settings.darkMode;

  @override
  void initState() {
    super.initState();
    // The theme and the language are both whole-window changes: rebuild from
    // the root rather than threading them through every widget.
    widget.app.settings.addListener(_onChanged);
    widget.app.translator.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.app.settings.removeListener(_onChanged);
    widget.app.translator.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // No fade here: a theme switch snaps everywhere at once, and a caption that
    // lagged behind the content would read as two competing animations.
    if (widget.app.settings.darkMode != _dark) {
      _dark = widget.app.settings.darkMode;
      TitleBar.setDark(_dark);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = MqTheme(dark: widget.app.settings.darkMode);

    return AppTheme(
      theme: theme,
      child: MaterialApp(
        title: 'Market Queen',
        debugShowCheckedModeBanner: false,
        theme: theme.material,
        // Arabic mirrors the whole interface.
        builder: (context, child) => Directionality(
          textDirection: widget.app.translator.rightToLeft
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          backgroundColor: theme.background,
          body: MainWindow(app: widget.app),
        ),
      ),
    );
  }
}
