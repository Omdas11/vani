import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/app_settings.dart';
import 'services/debug_log.dart';
import 'services/player_controller.dart';
import 'services/vani_theme.dart';
import 'widgets/app_background.dart';
import 'widgets/floating_dock.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DebugLog.logNow('app', 'Vani $kAppVersion starting');
  // Uncaught errors (framework + async gaps) go to the in-app log with
  // stack traces, so device issues can be diagnosed without adb.
  FlutterError.onError = (details) {
    DebugLog.logNow('error',
        'FlutterError: ${details.exception}\n${details.stack}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    DebugLog.logNow('error', 'uncaught async: $error\n$stack');
    return true;
  };
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
  DebugLog.logNow('audio', 'JustAudioBackground.init done');
  final pc = PlayerController();
  await pc.init();
  DebugLog.logNow('app', 'PlayerController.init done (settings loaded, EQ verdict resolved)');
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

  /// One navigator per tab (PixelPlayer/Spotify pattern): sub-pages
  /// pushed inside a tab (playlist pages, settings sub-pages, …) stay
  /// confined to the tab's content area, so the floating mini player +
  /// dock in this shell keep floating above every screen. Keys persist
  /// across rebuilds and dock reorderings, preserving each tab's
  /// navigation stack.
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {};

  GlobalKey<NavigatorState> _navKeyFor(String id) =>
      _navKeys.putIfAbsent(id, () => GlobalKey<NavigatorState>());

  Widget _pageFor(String id) {
    final pc = widget.pc;
    final Widget screen;
    switch (id) {
      case 'search':
        screen = SearchScreen(pc: pc);
        break;
      case 'library':
        screen = LibraryScreen(pc: pc);
        break;
      case 'stats':
        screen = StatsScreen(pc: pc);
        break;
      case 'settings':
        screen = SettingsScreen(pc: pc);
        break;
      case 'home':
      default:
        screen = HomeScreen(pc: pc);
        break;
    }
    return Navigator(
      key: _navKeyFor(id),
      onGenerateRoute: (_) =>
          MaterialPageRoute(builder: (_) => screen),
    );
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
                      // Floating editable dock (M3 Expressive tonal pill
                      // dock with sliding active indicator).
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: FloatingDock(
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

