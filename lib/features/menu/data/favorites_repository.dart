import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';

/// The dishes a customer has hearted, read from and written to the `favorites`
/// table.
///
/// These used to be a `Set<String>` held in memory, which lost every customer's
/// saved dishes on restart and handed the previous account's favourites to
/// whoever signed in next on a shared phone. They belong to the account, so
/// they belong in the database next to `addresses`.
///
/// Row level security already refuses to return or accept a row belonging to
/// somebody else. [userId] is still stated in every query so the intent is
/// readable and so the repository can be exercised against a fake client.
class FavoritesRepository {
  /// Resolved lazily, mirroring [LoyaltyRepository]: a test can construct this
  /// without the global Supabase client having been initialised.
  final SupabaseClient? _injectedClient;

  FavoritesRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get client => _injectedClient ?? supabase;

  /// The `menu_items.id` values [userId] has saved, most recently saved first.
  ///
  /// Only the ids are read. The dish itself always comes from the live menu
  /// catalog, so an item taken off the menu or repriced does not leave a stale
  /// card behind — it simply drops out, because no current item carries its id.
  ///
  /// A failure propagates. The screen says the list could not be loaded; it must
  /// never present an empty list as "you have not saved anything", which is a
  /// different statement.
  Future<List<String>> fetchFavoriteItemIds(String userId) async {
    final rows = await client
        .from('favorites')
        .select('menu_item_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map((row) => (row['menu_item_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// Saves [itemId] for [userId].
  ///
  /// Upserts rather than inserts. A double tap on the heart fires two writes and
  /// the unique constraint on `(user_id, menu_item_id)` would turn the second
  /// into an error the customer sees for a tap they were entitled to make;
  /// ignoring the conflict makes saving idempotent instead.
  Future<void> addFavorite({
    required String userId,
    required String itemId,
  }) async {
    await client.from('favorites').upsert(
          {
            'user_id': userId,
            'menu_item_id': itemId,
          },
          onConflict: 'user_id,menu_item_id',
          ignoreDuplicates: true,
        );
  }

  /// Removes [itemId] from [userId]'s saved dishes.
  ///
  /// Deleting a row that is not there is already a no-op, so removing something
  /// twice cannot fail.
  Future<void> removeFavorite({
    required String userId,
    required String itemId,
  }) async {
    await client
        .from('favorites')
        .delete()
        .eq('user_id', userId)
        .eq('menu_item_id', itemId);
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(),
);
