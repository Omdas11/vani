import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/app_settings.dart';
import 'services/crash_log.dart';
import 'services/debug_log.dart';
import 'services/player_controller.dart';
import 'services/vani_theme.dart';
import 'widgets/app_background.dart';
import 'widgets/floating_dock.dart';
import 'widgets/mini_player.dart';
import 'widgets/nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DebugLog.logNow('app', 'Vani $kAppVersion starting');
  // Uncaught errors (framework + async gaps) go to the in-app log with
  // stack traces, so device issues can be diagnosed without adb.
  FlutterError.onError = (details) {
    DebugLog.logNow('error',
        'FlutterError: ${details.exception}\n${details.stack}');
    // Persist every crash: the report survives restarts and can be
    // shared from Developer options (incl. the Simulate-crash button).
    unawaited(CrashLog.saveCrash(details.exception, details.stack));
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    DebugLog.logNow('error', 'uncaught async: $error\n$stack');
    unawaited(CrashLog.saveCrash(error, stack));
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

class _VaniAppState extends State<VaniApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sync the phone's light/dark state before the first frame so
    // System theme mode resolves correctly from launch.
    widget.pc.settings.setPlatformBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness);
    // Resolve the wallpaper-derived palette once at startup
    // (fire-and-forget: never blocks the first frame)…
    widget.pc.settings.refreshDynamicColor();
    // …and re-resolve on every resume, so a wallpaper change made while
    // the app was away re-themes the app.
    _lifecycle = AppLifecycleListener(
      onResume: () => widget.pc.settings.refreshDynamicColor(),
    );
  }

  /// When the phone flips between light and dark, System theme mode
  /// re-resolves and the whole MaterialApp rebuilds via the settings
  /// AnimatedBuilder.
  @override
  void didChangePlatformBrightness() {
    widget.pc.settings.setPlatformBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  /// Override for tests: called instead of [SystemNavigator.pop] when
  /// the user confirms app exit via double-back.
  final Future<void> Function()? onExit;

  const MainShell({super.key, required this.pc, this.onExit});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String _tabId = 'home';
  DateTime? _lastBackPress;

  /// One navigator per tab (PixelPlayer/Spotify pattern): sub-pages
  /// pushed inside a tab (playlist pages, settings sub-pages, …) stay
  /// confined to the tab's content area, so the floating mini player +
  /// dock in this shell keep floating above every screen. Keys persist
  /// across rebuilds and dock reorderings, preserving each tab's
  /// navigation stack.
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {};

  GlobalKey<NavigatorState> _navKeyFor(String id) =>
      _navKeys.putIfAbsent(id, () => GlobalKey<NavigatorState>());

  /// The root content widget for a tab id (no Navigator wrapper).
  Widget _screenFor(String id) {
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

  Widget _pageFor(String id) {
    return Navigator(
      key: _navKeyFor(id),
      onGenerateRoute: (_) =>
          MaterialPageRoute(builder: (_) => _screenFor(id)),
    );
  }

  /// Switches the dock to [id]. Screens call this (via
  /// [TabSwitchRequest]) instead of pushing another tab's page onto
  /// their own tab's navigator — e.g. Home's settings gear jumps to the
  /// Settings tab rather than showing "settings inside home".
  void _switchTab(String id) {
    final order = widget.pc.settings.dockOrder;
    if (order.contains(id)) {
      if (_tabId != id) setState(() => _tabId = id);
    } else {
      // Not in the dock (shouldn't happen for the built-ins —
      // sanitizeDockOrder always re-adds missing ids): open as a
      // full-screen root overlay instead of corrupting a tab stack.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _screenFor(id)),
      );
    }
  }

  /// System-back handling (v1.6.5): nested tab Navigators never saw the
  /// system back button, so back always exited the app. Order:
  ///   1. root route on top (dialog / sheet / Now Playing) → pop it;
  ///   2. active tab's navigator can pop → pop the sub-page;
  ///   3. not on Home → go to the Home tab;
  ///   4. on Home → double-press-to-exit.
  void _handleBack() {
    // 1. Root-level routes (dialogs/sheets/player) belong to the root
    // navigator — MainShell itself sits on the root, so this is it.
    final rootNav = Navigator.of(context);
    if (rootNav.canPop()) {
      rootNav.pop();
      return;
    }
    // 2. Pop the active tab's own page stack.
    final tabNav = _navKeys[_tabId]?.currentState;
    if (tabNav != null && tabNav.canPop()) {
      tabNav.pop();
      return;
    }
    // 3. Back on a tab root goes to the Home tab.
    final order = widget.pc.settings.dockOrder;
    if (_tabId != 'home' && order.contains('home')) {
      setState(() => _tabId = 'home');
      return;
    }
    // 4. Double-press to exit from the Home tab root.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      _lastBackPress = null;
      if (widget.onExit != null) {
        widget.onExit!();
      } else {
        SystemNavigator.pop();
      }
    } else {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
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
        return TabSwitchRequest(
          switchTab: _switchTab,
          child: PopScope(
            // We handle every system back ourselves (see _handleBack):
            // nested tab Navigators never receive it otherwise.
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _handleBack();
            },
            child: Scaffold(
              // Animated gradient + veena watermark behind everything
              // (toggle in Settings → Look & Feel).
              body: Stack(
                children: [
                  Positioned.fill(
                    child:
                        AppBackground(animated: settings.animatedBackground),
                  ),
                  // Content reserves room for the bottom stack. The mini
                  // player takes ZERO space when hidden (no weird blank
                  // gap): the padding animates between dock-only and
                  // dock+mini-player heights as playback starts/stops.
                  AnimatedBuilder(
                    animation: widget.pc,
                    builder: (_, __) {
                      final miniVisible =
                          widget.pc.currentTrack != null;
                      return AnimatedPadding(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(
                            bottom: miniVisible ? 188 : 100),
                        child: IndexedStack(
                          index: tabIndex,
                          children: [for (final id in order) _pageFor(id)],
                        ),
                      );
                    },
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
                          // Dynamically appears: zero space when hidden,
                          // slides+fades in on playback, collapses away on
                          // stop. The exiting card keeps its stale track
                          // (inert) so the collapse animates smoothly
                          // instead of popping.
                          AnimatedBuilder(
                            animation: widget.pc,
                            builder: (_, __) {
                              final track = widget.pc.currentTrack;
                              return AnimatedSwitcher(
                                duration:
                                    const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    SizeTransition(
                                  sizeFactor: animation,
                                  // Collapse toward the dock.
                                  alignment: Alignment.bottomCenter,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.45),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                ),
                                child: track != null
                                    ? Padding(
                                        key: const ValueKey('mini-on'),
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 0, 12, 8),
                                        child: MiniPlayer(
                                          pc: widget.pc,
                                          displayTrack: track,
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('mini-off')),
                              );
                            },
                          ),
                          // Floating editable dock (M3 Expressive tonal pill
                          // dock with sliding active indicator).
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
            ),
          ),
        );
      },
    );
  }
}

