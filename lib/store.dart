/// The store-publishing kit — a self-wired [StoreItemCard] you configure with a
/// single [StoreItem] (title + storageDir + fastlaneRoot): it loads the item's
/// authored app icon + screenshots, opens the app-icon / screenshot / feature-
/// graphic editors, manages languages, and deploys the rendered assets into the
/// app's fastlane + native icon folders.
///
/// This is a SEPARATE entry point from `package:framework/framework.dart` so its
/// generic [AppLocale] / `tr` helpers (which the host must provide above the
/// card) don't collide with tools that already define their own.
library;

export 'src/store/store_item.dart';
export 'src/store/store_item_card.dart';
export 'src/store/l10n/app_locale.dart';
