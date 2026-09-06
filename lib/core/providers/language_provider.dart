import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currently supported app languages.
enum AppLanguage { english, urdu }

/// Tracks the active language.
///
/// For this stage it is a simple in-memory provider defaulting to English.
/// Localization wiring is added in a later stage.
class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() => AppLanguage.english;

  void setLanguage(AppLanguage language) => state = language;
}

final languageProvider =
    NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);