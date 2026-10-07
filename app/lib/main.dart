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
  runApp(OpenTuneApp(pc: pc));
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

class OpenTuneApp extends StatelessWidget {
  final PlayerController pc;
  const OpenTuneApp({super.key, required this.pc});

  @override
  Widget build(BuildContext context) {
    return PlayerScope(
      pc: pc,
      child: MaterialApp(
        title: 'OpenTune',
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
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _tab, children: pages)),
          // Rebuild the mini player whenever the controller notifies.
          AnimatedBuilder(
            animation: widget.pc,
            builder: (_, __) => MiniPlayer(pc: widget.pc),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(
              icon: Icon(Icons.library_music), label: 'Library'),
        ],
      ),
    );
  }
}
