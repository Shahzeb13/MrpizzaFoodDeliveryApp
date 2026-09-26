import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/shared_components.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/providers/menu_provider.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final favoriteIds = ref.watch(favoritesProvider);
    final menu =
        ref.watch(allMenuItemsProvider);
    final favoriteItems =
        menu.where((item) => favoriteIds.contains(item.id)).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Favourites'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: favoriteItems.isEmpty
          ? const Center(
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
                        color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap the heart icon on any pizza to save it here.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favoriteItems.length,
              itemBuilder: (context, index) {
                final item = favoriteItems[index];
                return MrCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          item.imageUrl,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 76,
                            height: 76,
                            color: AppColors.sand,
                            child: const Center(
                              child: Icon(Icons.local_pizza_rounded,
                                  size: 28, color: AppColors.textLight),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.categoryName,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            MrPriceText(item.basePrice, fontSize: 15),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite_rounded,
                                color: AppColors.primary, size: 22),
                            onPressed: () {
                              ref
                                  .read(favoritesProvider.notifier)
                                  .toggleFavorite(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Removed from favourites'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                            ),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}