import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentune/main.dart';
import 'package:opentune/services/player_controller.dart';

/// v1.6.5 navigation-regression tests.
///
/// v1.6.4's per-tab nested Navigators introduced four user-confirmed
/// regressions (screenshots 2026-10-08):
///
/// 1. "Settings inside home": Home's header gear pushed a Settings page
///    onto the HOME tab's navigator, so Settings content showed while
///    the dock still had Home selected. Fixed: the gear now requests a
///    tab switch (TabSwitchRequest) instead of pushing.
/// 2. System back exited the app instead of popping tab sub-pages.
///    Fixed: MainShell PopScope — pop tab sub-page → go Home tab →
///    double-press-to-exit.
/// 3. After folder import, the import option "disappeared": the
///    "Importing folder" dialog was shown with useRootNavigator:true
///    but dismissed with Navigator.pop(tabContext), which popped the
///    tab's own route (black tab) and left the dialog stuck open.
///    Fixed: dismissRootDialog pops the root navigator. Same fix
///    applied to every root-shown dialog dismissed with an outer
///    context (Drive add/index/edit, rename playlist, new playlist).
/// 4. "Home screen stuck": the never-dismissed import dialog
///    (barrierDismissible:false) blocked the whole app at "98 of 98".
class _FakePC extends PlayerController {
  _FakePC() : super.test();

  @override
  Future<int> importLocalFolder(
      {void Function(int done, int total)? onProgress}) async {
    onProgress?.call(2, 2);
    return 0;
  }
}

Future<void> _pumpShell(WidgetTester tester,
    {List<String>? dockOrder, Future<void> Function()? onExit}) async {
  final pc = _FakePC();
  pc.settings.animatedBackground = false;
  if (dockOrder != null) pc.settings.dockOrder = dockOrder;
  await tester.pumpWidget(
      MaterialApp(home: MainShell(pc: pc, onExit: onExit)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

bool _shows(WidgetTester tester, String text) =>
    find.text(text, findRichText: true).evaluate().isNotEmpty;

Future<void> _tapDock(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('tab identity', () {
    testWidgets('each tab shows its own root content after switching',
        (tester) async {
      await _pumpShell(tester);
      expect(_shows(tester, 'Your Mix'), isTrue); // home
      await _tapDock(tester, 'Library');
      expect(_shows(tester, 'Your music, your way'), isTrue);
      expect(_shows(tester, 'Your Mix'), isFalse);
      await _tapDock(tester, 'Search');
      expect(_shows(tester, 'Your music, your way'), isFalse);
      await _tapDock(tester, 'Home');
      expect(_shows(tester, 'Your Mix'), isTrue);
      expect(_shows(tester, 'Your music, your way'), isFalse);
    });

    testWidgets(
        'home gear switches to the settings tab instead of pushing '
        'settings onto the home stack', (tester) async {
      await _pumpShell(tester, dockOrder: const [
        'home',
        'search',
        'library',
        'stats',
        'settings'
      ]);
      // Tap the gear in the Home header.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_shows(tester, 'Tune the app to your taste'), isTrue);
      // The bug: tapping Home in the dock afterwards still showed the
      // pushed Settings page. Fixed: we are ON the settings tab, so
      // Home shows home content.
      await _tapDock(tester, 'Home');
      expect(_shows(tester, 'Your Mix'), isTrue);
      expect(_shows(tester, 'Tune the app to your taste'), isFalse);
    });
  });

  group('system back', () {
    testWidgets('back pops the active tab sub-page first', (tester) async {
      await _pumpShell(tester);
      await _tapDock(tester, 'Library');
      // Push "My Drive" inside the library tab's navigator.
      await tester.tap(find.text('My Drive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_shows(tester, 'Add song from link'), isTrue);
      await _systemBack(tester);
      expect(_shows(tester, 'Add song from link'), isFalse);
      expect(_shows(tester, 'Your music, your way'), isTrue);
    });

    testWidgets('back on a tab root switches to the home tab',
        (tester) async {
      await _pumpShell(tester);
      await _tapDock(tester, 'Library');
      expect(_shows(tester, 'Your music, your way'), isTrue);
      await _systemBack(tester);
      expect(_shows(tester, 'Your Mix'), isTrue);
    });

    testWidgets('double back on home asks, then exits', (tester) async {
      var exits = 0;
      await _pumpShell(tester, onExit: () async => exits++);
      expect(_shows(tester, 'Your Mix'), isTrue);
      await _systemBack(tester);
      expect(_shows(tester, 'Press back again to exit'), isTrue);
      expect(exits, 0);
      await _systemBack(tester);
      expect(exits, 1);
    });

    testWidgets('back with a root dialog open dismisses the dialog',
        (tester) async {
      await _pumpShell(tester);
      await _tapDock(tester, 'Library');
      // "On this phone" opens the import choice dialog on the ROOT
      // navigator (useRootNavigator: true).
      await tester.tap(find.text('On this phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shows(tester, 'Import from phone'), isTrue);
      await _systemBack(tester);
      expect(_shows(tester, 'Import from phone'), isFalse);
      // Still in the app on the library tab (no exit, no tab switch).
      expect(_shows(tester, 'Your music, your way'), isTrue);
    });
  });

  group('folder import dialog', () {
    testWidgets(
        'import completion dismisses the progress dialog and keeps '
        'the library tab alive', (tester) async {
      await _pumpShell(tester);
      await _tapDock(tester, 'Library');
      await tester.tap(find.text('On this phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Choice dialog (root navigator).
      expect(_shows(tester, 'Import from phone'), isTrue);
      await tester.tap(find.text('Pick a folder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Progress dialog shown; fake import completes instantly.
      await tester.pump(const Duration(seconds: 1));
      expect(_shows(tester, 'Importing folder'), isFalse,
          reason: 'progress dialog must be dismissed after import');
      // The library tab must NOT be black/emptied by a wrong-navigator pop.
      expect(_shows(tester, 'Your music, your way'), isTrue);
      expect(_shows(tester, 'No new tracks imported.'), isTrue);
    });
  });
}
