import 'package:balumohol/core/language/language_controller.dart';

class LocalizedText {
  const LocalizedText({
    required this.bangla,
    required this.english,
  });

  final String bangla;
  final String english;

  String resolve(AppLanguage language) {
    return language.isBangla ? bangla : english;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalizedText &&
        other.bangla == bangla &&
        other.english == english;
  }

  @override
  int get hashCode => Object.hash(bangla, english);
}
