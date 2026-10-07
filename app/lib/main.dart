import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'services/player_controller.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Background playback + lock-screen/notification controls.
  // Must run before the first AudioPlayer is created.
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
    required PlayerController pc,
    required super.child,
  }) : super(notifier: pc);

  static PlayerController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlayerScope>()!
      .notifier!;
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
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF121212),
            elevation: 0,
          ),
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(pc: widget.pc),
      SearchScreen(pc: widget.pc),
      LibraryScreen(pc: widget.pc),
    ];
    return Scaffold(
      // The dock + mini card float above the content; the body gets
      // bottom padding so list content isn't hidden behind them.
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 188),
            child: IndexedStack(index: _tab, children: pages),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MiniPlayer(pc: widget.pc),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Floating M3 Expressive dock (detached tonal pill).
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _FloatingDock(
                      tab: _tab,
                      onTab: (i) => setState(() => _tab = i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detached tonal pill navigation dock in Material 3 Expressive styling:
/// surfaceContainer fill, 28dp radius, tonal shadow, M3 pill indicator
/// on the active destination with labels shown for the active item only
/// (Retro Music's proven M3 pattern).
class _FloatingDock extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _FloatingDock({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(28),
      color: scheme.surfaceContainer,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 70,
        labelBehavior:
            NavigationDestinationLabelBehavior.onlyShowSelected,
        indicatorColor: scheme.secondaryContainer,
        selectedIndex: tab,
        onDestinationSelected: onTab,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'Library'),
        ],
      ),
    );
  }
}
