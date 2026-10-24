import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/shared_components.dart';
import '../../menu/data/menu_repository.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/providers/menu_provider.dart';

/// The customer's saved dishes.
///
/// Reads two things and needs both before it can draw anything: the saved ids
/// from the `favorites` table, and the live menu catalog to turn those ids into
/// dishes. A saved id with no matching catalog item is dropped rather than shown
/// as a blank row, because that item is off the menu and the customer cannot
/// order it.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final catalogAsync = ref.watch(menuCatalogProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Favourites'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          // The app is go_router, so popping the route is the way back rather
          // than Navigator.pop, which would have no route to pop against.
          onPressed: () => context.pop(),
        ),
      ),
      body: _buildBody(context, ref, favoritesAsync, catalogAsync),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<String>> favoritesAsync,
    AsyncValue<dynamic> catalogAsync,
  ) {
    // While either read is in flight the list is genuinely unknown. Rendering
    // the empty state now flashed "no favourites" at every customer on every
    // visit, which reads as "your saved dishes are gone".
    if (favoritesAsync.isLoading || catalogAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (favoritesAsync.hasError) {
      return _buildProblem(
        title: 'Could not load your favourites',
        detail: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(favoritesProvider),
      );
    }

    if (catalogAsync.hasError) {
      return _buildProblem(
        title: 'Could not load the menu',
        detail: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(menuCatalogProvider),
      );
    }

    final savedIds = favoritesAsync.valueOrNull ?? const <String>[];
    final itemsById = <String, MenuItem>{
      for (final item in ref.watch(allMenuItemsProvider)) item.id: item,
    };
    final savedItems = <MenuItem>[
      for (final id in savedIds)
        if (itemsById[id] != null) itemsById[id]!,
    ];

    if (savedItems.isEmpty) {
      return const _EmptyFavourites();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: savedItems.length,
      itemBuilder: (context, index) => _FavoriteRow(item: savedItems[index]),
    );
  }

  Widget _buildProblem({
    required String title,
    required String detail,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const MrIconWell(
              icon: Icons.wifi_off_rounded,
              color: AppColors.textSecondary,
              background: AppColors.sand,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// One saved dish: picture, name, price, and the two actions a returning
/// customer actually wants — put it back in the cart, or stop saving it.
class _FavoriteRow extends ConsumerWidget {
  final MenuItem item;

  const _FavoriteRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = isFavorite(ref.watch(favoritesProvider), item.id);

    return MrCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => CustomizationBottomSheet(item: item),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                // Through the resolver, like every other dish image, so a
                // relative path from before the Cloudinary migration still
                // loads instead of showing a broken frame.
                MenuRepository.resolveItemImage(item),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 76,
                  height: 76,
                  color: AppColors.sand,
                  child: const Center(
                    child:
                        Icon(Icons.local_pizza_rounded, size: 28, color: AppColors.textLight),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.categoryName,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  MrPriceText(item.basePrice, fontSize: 15),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    isSaved
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color:
                        isSaved ? AppColors.primary : AppColors.textSecondary,
                    size: 22,
                  ),
                  onPressed: () async {
                    try {
                      await ref
                          .read(favoritesProvider.notifier)
                          .toggleFavorite(item.id);
                    } catch (_) {
                      if (!context.mounted) return;
                      showTopCartToast(
                          context, 'Could not update favourites.');
                    }
                  },
                ),
                ElevatedButton(
                  onPressed: () {
                    ref.read(cartProvider.notifier).addItem(
                          item: item,
                          size: PizzaSize.medium,
                          crust: PizzaCrust.thin,
                          toppings: [],
                          quantity: 1,
                        );
                    showTopCartToast(
                        context, 'Added ${item.title} to cart!');
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFavourites extends StatelessWidget {
  const _EmptyFavourites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MrIconWell(
            icon: Icons.favorite_border_rounded,
            color: AppColors.textSecondary,
            background: AppColors.sand,
            size: 28,
          ),
          SizedBox(height: 12),
          Text(
            'No Favourites Saved',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tap the heart on any dish to save it here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
