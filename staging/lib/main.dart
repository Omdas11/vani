import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/app_settings.dart';
import 'services/player_controller.dart';
import 'services/vani_theme.dart';
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
  //
  // v1.5.0 notification hardening (notification showed no transport
  // buttons on device): androidStopForegroundOnPause=false keeps the
  // foreground service alive across pause/resume (on Android 12+ the
  // service would otherwise detach and the media session could end up
  // in a degraded state); explicit icon + brand color so the
  // MediaStyle notification always has valid assets.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.opentune.app.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: false,
    androidNotificationIcon: 'mipmap/ic_launcher',
    notificationColor: const Color(0xFF00E59B),
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

class VaniApp extends StatefulWidget {
  final PlayerController pc;
  const VaniApp({super.key, required this.pc});

  @override
  State<VaniApp> createState() => _VaniAppState();
}

class _VaniAppState extends State<VaniApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Resolve the wallpaper-derived palette once at startup
    // (fire-and-forget: never blocks the first frame)…
    widget.pc.settings.refreshDynamicColor();
    // …and re-resolve on every resume, so a wallpaper change made while
    // the app was away re-themes the app.
    _lifecycle = AppLifecycleListener(
      onResume: () => widget.pc.settings.refreshDynamicColor(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole MaterialApp whenever theme settings change:
    // preset, match-system toggle, corner radius, or a fresh dynamic
    // palette from the platform.
    return AnimatedBuilder(
      animation: widget.pc.settings,
      builder: (_, __) {
        final settings = widget.pc.settings;
        return PlayerScope(
          pc: widget.pc,
          child: MaterialApp(
            title: 'Vani',
            debugShowCheckedModeBanner: false,
            theme: VaniTheme.buildTheme(
              scheme: settings.resolveColorScheme(),
              cornerRadius: settings.cornerRadius,
            ),
            home: MainShell(pc: widget.pc),
          ),
        );
      },
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
          // (toggle in Settings → Look & Feel).
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
                      // Floating mini-player card (PixelPlayer pattern).
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
/// destination, labels on the active item only.
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
