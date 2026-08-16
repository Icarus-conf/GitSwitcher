import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_services.dart';
import 'src/ui/settings_screen.dart';
import 'src/ui/theme/glass.dart';
import 'src/ui/tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Put a real NSVisualEffectView behind the Flutter view, so the window is
  // frosted rather than see-through.
  //
  // Do NOT call makeWindowFullyTransparent() here: it removes the window
  // background outright, which overrides the material and leaves the desktop
  // showing through unblurred.
  await WindowManipulator.initialize();
  WindowManipulator.setMaterial(NSVisualEffectViewMaterial.sidebar);
  WindowManipulator.makeTitlebarTransparent();
  WindowManipulator.enableFullSizeContentView();
  WindowManipulator.hideTitle();

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(660, 620),
    center: true,
    title: 'GitSwitcher Settings',
    // The content runs under the title bar, so the frosted layer reaches the
    // top edge. The window background is left alone — the material owns it.
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: true,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // The window is only ever shown on demand from the menu.
    await windowManager.setPreventClose(true);
    await windowManager.hide();
  });

  final services = await AppServices.create();
  final tray = TrayController(services);
  await tray.start();

  runApp(GitSwitcherApp(services: services, tray: tray));
}

class GitSwitcherApp extends StatelessWidget {
  const GitSwitcherApp({super.key, required this.services, required this.tray});

  final AppServices services;
  final TrayController tray;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitSwitcher',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: SettingsScreen(services: services, tray: tray),
    );
  }

  /// Every surface stays transparent so the window's vibrancy layer is what the
  /// user actually sees.
  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Glass.accents.first,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dialogTheme: const DialogThemeData(backgroundColor: Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xF21C1E22)
            : const Color(0xF2FFFFFF),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark ? Colors.white : Glass.ink,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
