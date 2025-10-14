import 'package:shared_preferences/shared_preferences.dart';

/// Abstracts the underlying key value persistence implementation so that the
/// application logic can depend on an interface instead of the concrete
/// [SharedPreferences] implementation.
abstract class PreferencesService {
  Future<void> init();

  String? getString(String key);

  List<String>? getStringList(String key);

  Future<bool> setString(String key, String value);

  Future<bool> setStringList(String key, List<String> values);

  // Add a method to get JWT token
  Future<String?> getToken();
}

class SharedPreferencesService implements PreferencesService {
  SharedPreferences? _instance;

  @override
  Future<void> init() async {
    _instance ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _prefs {
    final prefs = _instance;
    if (prefs == null) {
      throw StateError('PreferencesService.init must be called before use.');
    }
    return prefs;
  }

  @override
  String? getString(String key) {
    return _prefs.getString(key);
  }

  @override
  List<String>? getStringList(String key) {
    return _prefs.getStringList(key);
  }

  @override
  Future<bool> setString(String key, String value) {
    return _prefs.setString(key, value);
  }

  @override
  Future<bool> setStringList(String key, List<String> values) {
    return _prefs.setStringList(key, values);
  }

  // Method to get JWT token from SharedPreferences
  @override
  Future<String?> getToken() async {
    return _prefs.getString('jwt_token');
  }
}
