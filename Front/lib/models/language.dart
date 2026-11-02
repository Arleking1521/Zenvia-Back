enum AppLanguage { english, chinese, kazakh, russian }

extension AppLanguageX on AppLanguage {
  String get apiCode {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.chinese:
        return 'zh';
      case AppLanguage.kazakh:
        return 'kk';
      case AppLanguage.russian:
        return 'ru';
    }
  }

  String get label {
    switch (this) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.chinese:
        return '中文';
      case AppLanguage.kazakh:
        return 'Қазақ тілі';
      case AppLanguage.russian:
        return 'Русский';
    }
  }

  String get subLabel {
    switch (this) {
      case AppLanguage.english:
        return 'Английский';
      case AppLanguage.chinese:
        return 'Китайский';
      case AppLanguage.kazakh:
        return 'Казахский';
      case AppLanguage.russian:
        return '';
    }
  }

  String get flagEmoji {
    switch (this) {
      case AppLanguage.english:
        return 'EN';
      case AppLanguage.chinese:
        return '中';
      case AppLanguage.kazakh:
        return 'KZ';
      case AppLanguage.russian:
        return 'RU';
    }
  }

  static AppLanguage? tryFromApiCode(String? code) {
    switch (code) {
      case 'en':
        return AppLanguage.english;
      case 'zh':
        return AppLanguage.chinese;
      case 'kk':
        return AppLanguage.kazakh;
      case 'ru':
        return AppLanguage.russian;
      default:
        return null;
    }
  }

  static AppLanguage fromApiCode(String? code) {
    return tryFromApiCode(code) ?? AppLanguage.english;
  }
}

class LanguageOption {
  final int id;
  final String code;
  final String title;
  final int position;
  final String? iconUrl;

  const LanguageOption({
    required this.id,
    required this.code,
    required this.title,
    this.position = 0,
    this.iconUrl,
  });

  AppLanguage? get appLanguage => AppLanguageX.tryFromApiCode(code);
}

