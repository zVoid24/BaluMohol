import 'package:flutter/foundation.dart';

enum AppLanguage { bangla, english }

extension AppLanguageX on AppLanguage {
  bool get isBangla => this == AppLanguage.bangla;

  String get displayName => switch (this) {
        AppLanguage.bangla => 'বাংলা',
        AppLanguage.english => 'English',
      };
}

class LanguageController extends ChangeNotifier {
  AppLanguage _language = AppLanguage.bangla;

  AppLanguage get language => _language;

  void setLanguage(AppLanguage language) {
    if (_language == language) return;
    _language = language;
    notifyListeners();
  }
}
