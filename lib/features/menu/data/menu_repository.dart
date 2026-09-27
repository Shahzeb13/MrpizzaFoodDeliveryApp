import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../core/network/supabase_client.dart';
import '../models/menu_item.dart';
import 'menu_catalog.dart';

class MenuRepository {
  /// Loads the menu from Supabase: the real `categories` rows plus every
  /// `menu_items` row, joined through `menu_items.category_id`.
  ///
  /// No bundled fallback. An empty table returns [MenuCatalog.empty] and a
  /// failed fetch throws, so the screen can say the kitchen has nothing on or
  /// offer a retry. Answering with the bundled mock catalog here once showed
  /// customers sample pizzas that were not for sale.
  Future<MenuCatalog> fetchMenuCatalog() async {
    // PostgREST embeds `categories` through the real foreign key
    // (menu_items_category_id_fkey), so one round trip is enough.
    final itemRows = await supabase
        .from('menu_items')
        .select('*, categories(id, name, sort_order)');
    final items = (itemRows as List).whereType<Map<String, dynamic>>();

    final categoryRows = await supabase
        .from('categories')
        .select('id, name, sort_order')
        .order('sort_order', ascending: true);

    return MenuCatalog.fromRows(
      itemRows: items.toList(),
      categoryRows:
          (categoryRows as List).whereType<Map<String, dynamic>>().toList(),
    );
  }

  /// Base URL that relative `image_url` values are resolved against.
  ///
  /// Rows written before the Cloudinary migration store a bare path such as
  /// `/menu-images/zinger.png`, which `Image.network` cannot load. Those are
  /// resolved against this base; absolute URLs are passed through untouched, so
  /// the app works with either storage backend at once.
  static String get imageBaseUrl {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;
    try {
      _cachedBaseUrl = dotenv.maybeGet('MENU_IMAGE_BASE_URL')?.trim() ?? '';
    } catch (_) {
      // The .env asset is unavailable in unit tests.
      _cachedBaseUrl = '';
    }
    return _cachedBaseUrl!;
  }

  static String? _cachedBaseUrl;

  @visibleForTesting
  static void overrideImageBaseUrl(String value) => _cachedBaseUrl = value.trim();

  /// Turns a stored `image_url` into something `Image.network` can load.
  ///
  /// Absolute `http(s)` URLs are returned unchanged, so Cloudinary URLs keep
  /// working. A relative path is joined onto [baseUrl]. An empty value stays
  /// empty rather than becoming a broken request, which lets the caller show
  /// its own placeholder.
  static String resolveImageUrl(String raw, {String? baseUrl}) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final base = (baseUrl ?? imageBaseUrl).trim();
    if (base.isEmpty) return value;
    final separator = value.startsWith('/') ? '' : '/';
    return '$base$separator$value';
  }

  /// Resolved image URL for a loaded item.
  static String resolveItemImage(MenuItem item) =>
      resolveImageUrl(item.imageUrl);

  // The bundled sample menu below is intentionally not used: answering an empty\n  // or failed fetch with sample food let customers order items that were not on\n  // the menu. Kept only as test fixture data. Do not wire it back in as a\n  // silent fallback.\n
}
