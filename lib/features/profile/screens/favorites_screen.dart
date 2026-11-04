import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/neumorphic.dart';
import '../../../widgets/shared_components.dart';
import '../../menu/data/menu_repository.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/providers/menu_provider.dart';

/// The customer's saved dishes matching Batch 3 Image 2.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final catalogAsync = ref.watch(menuCatalogProvider);

    return Scaffold(
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'My Favourites',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: NeuColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        leading: Center(
          child: NeuCircleButton(
            size: 40,
            onPressed: () => context.pop(),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: NeuColors.textPrimary,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBody(context, ref, favoritesAsync, catalogAsync),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<String>> favoritesAsync,
    AsyncValue<dynamic> catalogAsync,
  ) {
    if (favoritesAsync.isLoading || catalogAsync.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: NeuColors.primary),
      );
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
            NeuInset(
              borderRadius: 30,
              padding: const EdgeInsets.all(16),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: NeuColors.textSecondary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: NeuColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: NeuColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// One saved dish with Neumorphic card styling.
class _FavoriteRow extends ConsumerWidget {
  final MenuItem item;

  const _FavoriteRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = isFavorite(ref.watch(favoritesProvider), item.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: NeuCard(
        padding: const EdgeInsets.all(12),
        borderRadius: 22,
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => CustomizationBottomSheet(item: item),
        ),
        child: Row(
          children: [
            NeuInset(
              borderRadius: 16,
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  MenuRepository.resolveItemImage(item),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 72,
                    height: 72,
                    color: NeuColors.sand,
                    child: const Center(
                      child: Text('🍕', style: TextStyle(fontSize: 26)),
                    ),
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
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: NeuColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.categoryName,
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NeuColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rs. ${item.basePrice.toInt()}',
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: NeuColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                NeuCircleButton(
                  size: 36,
                  onPressed: () async {
                    try {
                      await ref
                          .read(favoritesProvider.notifier)
                          .toggleFavorite(item.id);
                    } catch (_) {
                      if (!context.mounted) return;
                      showTopCartToast(context, 'Could not update favourites.');
                    }
                  },
                  child: Icon(
                    isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isSaved ? NeuColors.primary : NeuColors.textSecondary,
                    size: 19,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    ref.read(cartProvider.notifier).addItem(
                          item: item,
                          size: PizzaSize.medium,
                          crust: PizzaCrust.thin,
                          toppings: [],
                          quantity: 1,
                        );
                    showTopCartToast(context, 'Added ${item.title} to cart!');
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: NeuColors.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4DE51926),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state matching Batch 3 Image 2 with concentric circular debossed well and red heart.
class _EmptyFavourites extends StatelessWidget {
  const _EmptyFavourites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Outer raised / inner debossed well for heart
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeuColors.background,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-6, -6),
                    blurRadius: 16,
                  ),
                  BoxShadow(
                    color: Color(0x28A6B4C9),
                    offset: Offset(6, 6),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE9EFF7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        offset: const Offset(3, 3),
                        blurRadius: 6,
                      ),
                      const BoxShadow(
                        color: Colors.white,
                        offset: Offset(-3, -3),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.favorite_outline_rounded,
                      color: NeuColors.primary,
                      size: 46,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Favourites Saved',
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the heart icon on any pizza to save it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: NeuColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            // Primary Pill Button: Browse the menu
            GestureDetector(
              onTap: () => context.go('/home'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: NeuColors.primary,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66E51926),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Text(
                  'Browse the menu',
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
