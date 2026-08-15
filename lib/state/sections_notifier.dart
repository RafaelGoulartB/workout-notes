import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kPrefsPlanSectionEnabled = 'section_plan_enabled';

/// App-wide visibility of optional sections (tabs). Persisted in
/// [SharedPreferences] so the navigation shell and the settings screens
/// stay in sync at runtime.
class SectionsNotifier extends ChangeNotifier {
  SectionsNotifier([this._planEnabled = true]);

  bool _planEnabled;

  bool get planEnabled => _planEnabled;

  Future<void> setPlanEnabled(bool enabled) async {
    if (_planEnabled == enabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsPlanSectionEnabled, enabled);
    _planEnabled = enabled;
    notifyListeners();
  }
}
