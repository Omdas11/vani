import 'package:flutter/material.dart';

/// Dismisses a dialog or bottom sheet that was shown with
/// `useRootNavigator: true`.
///
/// Plain `Navigator.pop(context)` from a screen inside one of the tab
/// Navigators pops the *tab's* navigator instead — the v1.6.4 regression:
/// it popped tab pages (even a tab's initial route, leaving the tab
/// black/empty) while the root dialog stayed stuck open. Always use this
/// helper for root-shown dialogs/sheets.
void dismissRootDialog(BuildContext context, [Object? result]) {
  Navigator.of(context, rootNavigator: true).pop(result);
}

/// Lets any screen request a dock-tab switch (e.g. Home's settings gear
/// jumping to the Settings tab). Pushing a Settings page onto the Home
/// tab's own navigator made it look like "settings inside home" while
/// the dock still showed Home selected (v1.6.4 regression report).
class TabSwitchRequest extends InheritedWidget {
  final void Function(String id) switchTab;

  const TabSwitchRequest({
    super.key,
    required this.switchTab,
    required super.child,
  });

  static void Function(String id) of(BuildContext context) {
    final w =
        context.dependOnInheritedWidgetOfExactType<TabSwitchRequest>();
    assert(w != null, 'TabSwitchRequest not found above this widget');
    return w!.switchTab;
  }

  @override
  bool updateShouldNotify(TabSwitchRequest oldWidget) => true;
}
