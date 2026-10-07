import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/app_settings.dart';
import 'services/player_controller.dart';
import 'widgets/app_background.dart';
import 'widgets/glass_panel.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Background playback + lock-screen/notification controls.
  // Must run before the first AudioPlayer is created.
  // NOTE: next/previous buttons appear in the notification only because
  // PlayerController mirrors the app queue into the background player's
  // ConcatenatingAudioSource (see _fillSequence). With a single audio
  // source the system would show play/pause only.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.opentune.app.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  final pc = PlayerController();
  await pc.init();
  runApp(VaniApp(pc: pc));
}

/// Exposes the [PlayerController] down the widget tree.
class PlayerScope extends InheritedNotifier<PlayerController> {
  const PlayerScope({
    super.key,
    required super.child,
    required PlayerController pc,
  }) : super(notifier: pc);

  static PlayerController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlayerScope>()!
      .notifier!;
}

/// Obsidian Sonic typography: Space Grotesk for display/titles, Inter
/// for body. google_fonts fetches the files on first use (zero APK size
/// impact); offline it falls back to the platform fonts.
TextTheme _vaniTextTheme() {
  final base = ThemeData.dark().textTheme;
  final display = GoogleFonts.spaceGroteskTextTheme(base);
  final body = GoogleFonts.interTextTheme(base);
  return body.copyWith(
    displayLarge: display.displayLarge,
    displayMedium: display.displayMedium,
    displaySmall: display.displaySmall,
    headlineLarge: display.headlineLarge,
    headlineMedium: display.headlineMedium,
    headlineSmall: display.headlineSmall,
    titleLarge: display.titleLarge,
    titleMedium: display.titleMedium,
    titleSmall: display.titleSmall,
  );
}

class VaniApp extends StatelessWidget {
  final PlayerController pc;
  const VaniApp({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    return PlayerScope(
      pc: pc,
      child: MaterialApp(
        title: 'Vani',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          textTheme: _vaniTextTheme(),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1DB954),
            secondary: Color(0xFF1DB954),
          ),
          bottomNavigationBarTheme:
              const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF1A1A1A),
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.grey,
          ),
          chipTheme: ChipThemeData.fromDefaults(
            primaryColor: const Color(0xFF1DB954),
            secondaryColor: Colors.grey[800]!,
            labelStyle: const TextStyle(),
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: Color(0xFF1DB954),
            inactiveTrackColor: Color(0xFF3A3A3A),
            thumbColor: Colors.white,
          ),
        ),
        home: MainShell(pc: pc),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final PlayerController pc;
  const MainShell({super.key, required this.pc});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String _tabId = 'home';

  Widget _pageFor(String id) {
    final pc = widget.pc;
    switch (id) {
      case 'search':
        return SearchScreen(pc: pc);
      case 'library':
        return LibraryScreen(pc: pc);
      case 'stats':
        return StatsScreen(pc: pc);
      case 'settings':
        return SettingsScreen(pc: pc);
      case 'home':
      default:
        return HomeScreen(pc: pc);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pc.settings,
      builder: (_, __) {
        final settings = widget.pc.settings;
        final order = settings.dockOrder;
        final visible =
            order.map(NavDestination.byId).toList(growable: false);
        if (!order.contains(_tabId)) _tabId = order.first;
        final tabIndex = order.indexOf(_tabId);
        return Scaffold(
          // Animated gradient + veena watermark behind everything
          // (toggle in Settings → Appearance).
          body: Stack(
            children: [
              Positioned.fill(
                child: AppBackground(animated: settings.animatedBackground),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 188),
                child: IndexedStack(
                  index: tabIndex,
                  children: [for (final id in order) _pageFor(id)],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Floating mini-player card (Namida pattern).
                      AnimatedBuilder(
                        animation: widget.pc,
                        builder: (_, __) => Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: MiniPlayer(pc: widget.pc),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Floating editable dock.
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _FloatingDock(
                          destinations: visible,
                          currentId: _tabId,
                          onSelect: (id) =>
                              setState(() => _tabId = id),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Detached tonal pill navigation dock in Material 3 Expressive styling,
/// wrapped in real glass. The visible destinations and their order come
/// from Settings → Navigation (item 6); M3 pill indicator on the active
/// destination, labels on the active item only (Retro Music's pattern).
class _FloatingDock extends StatelessWidget {
  final List<NavDestination> destinations;
  final String currentId;
  final ValueChanged<String> onSelect;
  const _FloatingDock({
    required this.destinations,
    required this.currentId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index =
        destinations.indexWhere((d) => d.id == currentId).clamp(0, 4);
    return GlassPanel(
      radius: 28,
      padding: EdgeInsets.zero,
      tintAlpha: 0.14,
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 70,
        labelBehavior:
            NavigationDestinationLabelBehavior.onlyShowSelected,
        indicatorColor: scheme.secondaryContainer,
        selectedIndex: index,
        onDestinationSelected: (i) => onSelect(destinations[i].id),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
