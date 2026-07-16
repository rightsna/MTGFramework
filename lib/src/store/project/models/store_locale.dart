/// The App Store screenshot localizations a project can author. Each [code] is
/// both the App Store Connect localization code AND the on-disk folder name
/// under a project's `screenshots/` (e.g. `screenshots/en-US/`). Labels are
/// shown KO/EN in the language picker.
class StoreLocale {
  final String code;
  final String ko; // Korean label
  final String en; // English label
  const StoreLocale(this.code, this.ko, this.en);
}

/// Curated list of common App Store localizations. Add more here as needed —
/// the picker and folder layout pick them up automatically.
const List<StoreLocale> kStoreLocales = [
  StoreLocale('ko', '한국어', 'Korean'),
  StoreLocale('en-US', '영어(미국)', 'English (U.S.)'),
  StoreLocale('ja', '일본어', 'Japanese'),
  StoreLocale('zh-Hans', '중국어(간체)', 'Chinese (Simplified)'),
  StoreLocale('zh-Hant', '중국어(번체)', 'Chinese (Traditional)'),
  StoreLocale('es-ES', '스페인어', 'Spanish'),
  StoreLocale('fr-FR', '프랑스어', 'French'),
  StoreLocale('de-DE', '독일어', 'German'),
  StoreLocale('pt-BR', '포르투갈어(브라질)', 'Portuguese (Brazil)'),
  StoreLocale('ru', '러시아어', 'Russian'),
  StoreLocale('it', '이탈리아어', 'Italian'),
  StoreLocale('id', '인도네시아어', 'Indonesian'),
  StoreLocale('vi', '베트남어', 'Vietnamese'),
  StoreLocale('th', '태국어', 'Thai'),
];

/// Locales a new project starts with: Korean (primary) + US English.
const List<String> kDefaultScreenshotLocales = ['ko', 'en-US'];

/// The set of known locale folder names (used to tell locale folders apart from
/// legacy screenshot-document folders during migration).
final Set<String> kKnownLocaleCodes = {for (final l in kStoreLocales) l.code};

/// Catalog entry for [code], or null if it isn't in [kStoreLocales].
StoreLocale? storeLocaleByCode(String code) {
  for (final l in kStoreLocales) {
    if (l.code == code) return l;
  }
  return null;
}

/// Display label for [code] in the current editor language, falling back to the
/// raw code for locales not in the catalog (e.g. a folder authored elsewhere).
String storeLocaleLabel(String code, {required bool english}) {
  final l = storeLocaleByCode(code);
  if (l == null) return code;
  return english ? l.en : l.ko;
}
