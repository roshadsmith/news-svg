import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controllers/app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/news_api.dart';
import 'services/settings_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NewsApp());
}

class NewsApp extends StatefulWidget {
  const NewsApp({super.key});

  @override
  State<NewsApp> createState() => _NewsAppState();
}

class _NewsAppState extends State<NewsApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController(api: NewsApi(), settingsStore: SettingsStore());
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const sand = Color(0xFFF7F7F7);
    const mist = Color(0xFFF1F2F4);
    const ink = Color(0xFF111111);
    const red = Color(0xFFB80000);
    const night = Color(0xFF0F1214);
    const slate = Color(0xFF171B1F);
    const ash = Color(0xFFD2D7DF);
    const accent = Color(0xFFE35A5A);

    const headingFontFamily = 'Georgia';
    const headingFallback = ['Times New Roman', 'serif'];
    const bodyFontFamily = 'Arial';
    const bodyFallback = ['Helvetica', 'sans-serif'];

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: red,
            brightness: Brightness.light,
          ).copyWith(
            primary: red,
            secondary: const Color(0xFF1F2933),
            surface: Colors.white,
          ),
      scaffoldBackgroundColor: sand,
      fontFamily: bodyFontFamily,
      fontFamilyFallback: bodyFallback,
      textTheme:
          const TextTheme(
                titleLarge: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                titleMedium: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                bodyMedium: TextStyle(fontSize: 15, height: 1.6),
                bodySmall: TextStyle(fontSize: 13, height: 1.45),
                labelSmall: TextStyle(fontSize: 12, letterSpacing: 0.2),
              )
              .apply(bodyColor: ink, displayColor: ink)
              .copyWith(
                titleLarge: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: headingFontFamily,
                  fontFamilyFallback: headingFallback,
                ),
                titleMedium: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: headingFontFamily,
                  fontFamilyFallback: headingFallback,
                ),
              ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.94),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: red.withValues(alpha: 0.08),
        labelStyle: const TextStyle(color: red),
        side: BorderSide(color: red.withValues(alpha: 0.15)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        indicatorColor: red.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: red,
          foregroundColor: Colors.white,
        ),
      ),
    );

    final darkScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: const Color(0xFFFDF2F2),
          secondary: const Color(0xFF8FB7B0),
          onSecondary: const Color(0xFF0C1514),
          surface: slate,
          onSurface: ash,
          background: night,
          onBackground: ash,
          error: const Color(0xFFFF6B6B),
          onError: const Color(0xFF2A0C0C),
        );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: darkScheme,
      scaffoldBackgroundColor: night,
      fontFamily: bodyFontFamily,
      fontFamilyFallback: bodyFallback,
      textTheme:
          const TextTheme(
                titleLarge: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                titleMedium: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                bodyMedium: TextStyle(fontSize: 15, height: 1.6),
                bodySmall: TextStyle(fontSize: 13, height: 1.45),
                labelSmall: TextStyle(fontSize: 12, letterSpacing: 0.2),
              )
              .apply(bodyColor: ash, displayColor: ash)
              .copyWith(
                titleLarge: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: headingFontFamily,
                  fontFamilyFallback: headingFallback,
                ),
                titleMedium: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: headingFontFamily,
                  fontFamilyFallback: headingFallback,
                ),
              ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ash,
      ),
      cardTheme: CardThemeData(
        color: slate.withValues(alpha: 0.95),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slate.withValues(alpha: 0.8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkScheme.primary.withValues(alpha: 0.25),
        labelStyle: TextStyle(color: darkScheme.onPrimary),
        side: BorderSide(color: darkScheme.primary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: slate.withValues(alpha: 0.95),
        indicatorColor: darkScheme.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: darkScheme.primary,
          foregroundColor: darkScheme.onPrimary,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final settings = _controller.settings;
        final mode = settings.themeMode == 'dark'
            ? ThemeMode.dark
            : settings.themeMode == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
        return MaterialApp(
          title: 'news.svg',
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            scaffoldBackgroundColor: sand,
            colorScheme: baseTheme.colorScheme.copyWith(surface: mist),
          ),
          darkTheme: darkTheme,
          themeMode: mode,
          builder: (context, child) {
            final data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(textScaleFactor: settings.textScale),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final showSplash =
        !widget.controller.initialized ||
        (_index == 0 &&
            widget.controller.loading &&
            widget.controller.articles.isEmpty);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.controller.shouldShowUpdatePrompt()) return;
      _showUpdateDialog(context);
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: showSplash
          ? const Scaffold(body: _SplashScreen())
          : Scaffold(
              body: IndexedStack(
                index: _index,
                children: [
                  HomeScreen(
                    controller: widget.controller,
                    onManageSources: () => setState(() => _index = 1),
                  ),
                  ProfileScreen(controller: widget.controller),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) {
                  setState(() => _index = value);
                  if (value == 0) {
                    widget.controller.refreshIfNeeded();
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard_rounded),
                    label: 'Feed',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _showUpdateDialog(BuildContext context) async {
    final info = widget.controller.updateInfo;
    if (info == null) return;
    widget.controller.markUpdatePromptShown();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} is ready to download.'),
              if (info.notes != null && info.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(info.notes!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri.tryParse(info.downloadUrl);
                if (uri == null) return;
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
              },
              child: const Text('Download'),
            ),
          ],
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark
        ? const [Color(0xFF0B0F12), Color(0xFF141A20)]
        : const [Color(0xFFF9F9F9), Color(0xFFF1F2F4)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: background,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', width: 140, height: 140),
            const SizedBox(height: 16),
            Text(
              'Loading headlines...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
