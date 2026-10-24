import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/location_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/widgets.dart';
import '../features/location/screens/map_location_picker_sheet.dart';
import '../features/menu/data/menu_repository.dart';
import '../features/menu/models/menu_category.dart';
import '../features/menu/models/menu_item.dart';
import '../features/menu/providers/menu_provider.dart';
import '../features/profile/models/profile.dart';
import '../features/profile/providers/address_selection_provider.dart';
import '../features/profile/providers/profile_provider.dart';

/// Top Floating Toast Notification for Cart Actions (Doesn't block bottom checkout bar)
void showTopCartToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shopping_bag_rounded,
                        color: Colors.white, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1800), () {
    entry.remove();
  });
}

/// Official Mr. Pizza Logo Header Widget
class MrPizzaLogoWidget extends StatelessWidget {
  final double size;
  final bool showSlogan;

  const MrPizzaLogoWidget({
    super.key,
    this.size = 38.0,
    this.showSlogan = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            border: Border.all(color: AppColors.accent, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text('👨‍🍳', style: TextStyle(fontSize: 20)),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mr. Pizza',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
                height: 1.1,
              ),
            ),
            if (showSlogan) ...[
              const SizedBox(height: 3),
              Text(
                'LOVE IN EVERY BITE',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Small contextual tag used on dish cards (category / spice / prep meta).
class _ItemTag extends StatelessWidget {
  final String text;
  final Color? color;

  const _ItemTag({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final clr = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: clr,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Red "add to cart" island-button that overlaps the dish image.
class _AddButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _AddButton({this.size = 32, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Heart toggle that overlaps the top-left corner of a dish image.
///
/// Deliberately its own [ConsumerWidget] that watches only [favoritesProvider].
/// Watching it inside [PizzaCard] or [GridItemCard] instead would rebuild every
/// dish on screen each time one heart is tapped, which on the full menu is a
/// visible stall for a single-digit change.
class FavoriteButton extends ConsumerWidget {
  final MenuItem item;
  final double size;

  const FavoriteButton({
    super.key,
    required this.item,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isSaved = isFavorite(favorites, item.id);

    return GestureDetector(
      onTap: () async {
        try {
          await ref.read(favoritesProvider.notifier).toggleFavorite(item.id);
          if (!context.mounted) return;
          showTopCartToast(
            context,
            isSaved
                ? 'Removed ${item.title} from favourites'
                : 'Saved ${item.title} to favourites',
          );
        } catch (_) {
          if (!context.mounted) return;
          showTopCartToast(context, 'Could not update favourites.');
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The dish image runs underneath, so the heart carries its own
          // backdrop rather than relying on the image being light enough.
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowSoft,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isSaved ? AppColors.primary : AppColors.textSecondary,
          size: size * 0.58,
        ),
      ),
    );
  }
}

/// Customer Reviews Carousel (warm editorial cards, no borders)
class CustomerReviewsSection extends StatelessWidget {
  const CustomerReviewsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final reviews = [
      {'comment': 'Super fresh & delicious pizza. Best in town.', 'author': 'Ahmed K.', 'stars': 5, 'tag': 'PIZZA LOVER'},
      {'comment': 'Juicy zinger burgers and crispy fries. Loved it.', 'author': 'Usama M.', 'stars': 5, 'tag': 'BURGER FAN'},
      {'comment': 'Super fast 20-min delivery and still hot.', 'author': 'Aalyan M.', 'stars': 5, 'tag': 'REGULAR'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: MrSectionTitle(
            eyebrow: 'Vouched by locals',
            title: 'Word on the street',
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              return Container(
                width: 250,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowSoft,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Row(
                          children: List.generate(
                            review['stars'] as int,
                            (_) => const Icon(Icons.star_rounded,
                                size: 13, color: AppColors.accent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          review['tag'] as String,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: AppColors.textLight,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          review['author'] as String,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review['comment'] as String,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Premium dish card — title-led editorial row with a squircle dish image.
class PizzaCard extends ConsumerWidget {
  final MenuItem item;
  final VoidCallback onTap;

  const PizzaCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void addToCart() {
      ref.read(cartProvider.notifier).addItem(
            item: item,
            size: PizzaSize.medium,
            crust: PizzaCrust.thin,
            toppings: const [],
            quantity: 1,
          );
      showTopCartToast(context, '${item.title} added to cart.');
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ItemTag(
                        text: item.categoryName.toUpperCase(),
                        color: AppColors.textLight,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (item.isBestseller) ...[
                        const SizedBox(height: 8),
                        const _ItemTag(
                          text: 'Bestseller',
                          color: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: Image.network(
                          MenuRepository.resolveImageUrl(item.imageUrl),
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.sand,
                              child: const Center(
                                child:
                                    Text('🍕', style: TextStyle(fontSize: 32)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: -4,
                      left: -4,
                      child: FavoriteButton(item: item, size: 24),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: _AddButton(onTap: addToCart),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// HD Category Section Header Banner (editorial cover-card)
class CategoryHeroCard extends StatelessWidget {
  final MenuCategory category;
  final String bannerImageUrl;

  const CategoryHeroCard({
    super.key,
    required this.category,
    required this.bannerImageUrl,
  });

  /// A short line under the category name.
  ///
  /// The menu used to be described by a hardcoded eight-value enum, so this was
  /// an exhaustive switch. The restaurant really runs fifteen categories and
  /// adds more over time, so the line is chosen by what the name contains and
  /// falls back to something honest rather than to a wrong guess.
  String get categoryTagline {
    final name = category.name.toLowerCase();
    if (name.contains('deal') ||
        name.contains('offer') ||
        name.contains('free')) {
      return 'Limited-time bundles and combos';
    }
    if (name.contains('pizza')) return 'Hand-tossed, baked fresh to order';
    if (name.contains('burger')) return 'Flame-grilled & crispy delights';
    if (name.contains('wrap') ||
        name.contains('roll') ||
        name.contains('shawarma')) {
      return 'Rolled fresh with signature sauces';
    }
    if (name.contains('chicken') || name.contains('wing')) {
      return 'Crispy, hot and full of flavour';
    }
    if (name.contains('chinese') || name.contains('handi')) {
      return 'Wok-tossed with bold spices';
    }
    if (name.contains('steak')) return 'Seared and served sizzling';
    if (name.contains('pasta')) return 'Creamy, saucy, comfort on a plate';
    if (name.contains('sandwich')) return 'Stacked fresh between soft bread';
    if (name.contains('dessert') ||
        name.contains('cake') ||
        name.contains('brownie')) {
      return 'Sweet treats to finish the meal';
    }
    if (name.contains('drink') ||
        name.contains('beverage') ||
        name.contains('shake')) {
      return 'Ice-cold pours and frozen blends';
    }
    if (name.contains('side') || name.contains('starter')) {
      return 'Share it before the main arrives';
    }
    return 'Fresh from the Mr. Pizza kitchen';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 132,
      margin: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Image.network(
              bannerImageUrl,
              width: double.infinity,
              height: 132,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: AppColors.primaryDark),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.bannerScrim.withValues(alpha: 0.92),
                    AppColors.bannerScrim.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 0,
              bottom: 0,
              right: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      category.name.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Color(0xFF7A5414),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    categoryTagline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 6),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimalist grid tile — solid squircle image in a soft white lift.
class GridItemCard extends ConsumerWidget {
  final MenuItem item;
  final VoidCallback onTap;

  const GridItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void addToCart() {
      ref.read(cartProvider.notifier).addItem(
            item: item,
            size: PizzaSize.medium,
            crust: PizzaCrust.thin,
            toppings: const [],
            quantity: 1,
          );
      showTopCartToast(context, '${item.title} added to cart.');
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowSoft,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 108,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.network(
                      MenuRepository.resolveImageUrl(item.imageUrl),
                      height: 108,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.sand,
                        child: const Center(
                          child: Text('🍕', style: TextStyle(fontSize: 32)),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -2,
                  left: -2,
                  child: FavoriteButton(item: item, size: 26),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: _AddButton(size: 30, onTap: addToCart),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cart Floating Island (Visible ONLY when cart is not empty)
class CartFloatingBar extends ConsumerWidget {
  final VoidCallback onTap;

  const CartFloatingBar({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        height: 62,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: const [
            BoxShadow(
              color: AppColors.overlay,
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${cart.totalItemCount}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Rs. ${cart.subtotal.toInt()}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 6, 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Checkout',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.primary,
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item Customization Bottom Sheet (sizes, crust, toppings, quantity)
class CustomizationBottomSheet extends ConsumerStatefulWidget {
  final MenuItem item;

  const CustomizationBottomSheet({
    super.key,
    required this.item,
  });

  @override
  ConsumerState<CustomizationBottomSheet> createState() =>
      _CustomizationBottomSheetState();
}

class _CustomizationBottomSheetState
    extends ConsumerState<CustomizationBottomSheet> {
  PizzaSize _selectedSize = PizzaSize.medium;
  PizzaCrust _selectedCrust = PizzaCrust.thin;
  final Set<ToppingOption> _selectedToppings = {};
  int _quantity = 1;

  double get _unitPrice {
    double price = widget.item.basePrice * _selectedSize.priceMultiplier +
        _selectedCrust.extraPrice;
    return _selectedToppings.fold(price, (sum, t) => sum + t.price);
  }

  double get _totalPrice => _unitPrice * _quantity;

  void _addToCart() {
    ref.read(cartProvider.notifier).addItem(
          item: widget.item,
          size: _selectedSize,
          crust: _selectedCrust,
          toppings: _selectedToppings.toList(),
          quantity: _quantity,
        );
    showTopCartToast(context, '${widget.item.title} added to cart.');
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: AppColors.textLight,
        ),
      ),
    );
  }

  Widget _pillChoice({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.sand,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'Rs. ${value.toInt()}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.borderDeep,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MrCard(
                            borderRadius: BorderRadius.circular(18),
                            padding: const EdgeInsets.all(6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                MenuRepository.resolveImageUrl(
                                    widget.item.imageUrl),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 72,
                                  height: 72,
                                  color: AppColors.sand,
                                  child: const Center(
                                    child: Text('🍕',
                                        style: TextStyle(fontSize: 28)),
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
                                  widget.item.title,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 14, color: AppColors.accent),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.item.rating.toStringAsFixed(1),
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.schedule_rounded,
                                        size: 13,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.item.prepTime,
                                      style: theme.textTheme.labelMedium,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _sectionLabel('Size'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PizzaSize.values
                            .map((size) => _pillChoice(
                                  selected: _selectedSize == size,
                                  label: size.name,
                                  onTap: () =>
                                      setState(() => _selectedSize = size),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('Crust'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PizzaCrust.values
                            .map((crust) => _pillChoice(
                                  selected: _selectedCrust == crust,
                                  label: crust.name,
                                  onTap: () =>
                                      setState(() => _selectedCrust = crust),
                                ))
                            .toList(),
                      ),
                      if (widget.item.availableToppings.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionLabel('Add-ons'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children:
                              widget.item.availableToppings.map((topping) {
                            final selected =
                                _selectedToppings.contains(topping);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedToppings.remove(topping);
                                  } else {
                                    _selectedToppings.add(topping);
                                  }
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primaryTint
                                      : AppColors.sand,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      topping.icon,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      topping.name,
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontFamily,
                                        fontSize: 12,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '+${topping.price.toInt()}',
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontFamily,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const MrFadeDivider(),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _sectionLabel('Quantity'),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.sand,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                _QtyButton(
                                  icon: Icons.remove_rounded,
                                  onTap: () {
                                    if (_quantity > 1) {
                                      setState(() => _quantity--);
                                    }
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    '$_quantity',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                _QtyButton(
                                  icon: Icons.add_rounded,
                                  onTap: () => setState(() => _quantity++),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const MrFadeDivider(),
                      const SizedBox(height: 16),
                      _summaryRow('Item total', _unitPrice),
                      _summaryRow('Quantity', _quantity.toDouble()),
                      _summaryRow('Total', _totalPrice),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () {
                      _addToCart();
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Add to Cart',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shopping_bag_rounded,
                            color: AppColors.primary,
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Rs. ${_totalPrice.toInt()}',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Location Selection Dialog (GPS, saved addresses, manual entry)
/// The saved addresses offered in the location dialog, duplicates collapsed.
///
/// The address currently applied to the location is deliberately left out:
/// offering it as a choice the customer has not made yet invites them to
/// "confirm" a location they are already standing at and then wonder why
/// nothing visibly happened.
List<UserAddress> savedAddressesForDialog({
  required List<UserAddress> addresses,
  required String? currentAddressText,
}) {
  final seenIds = <String>{};
  final result = <UserAddress>[];
  for (final address in addresses) {
    if (address.addressLine == currentAddressText) continue;
    if (seenIds.add(address.id)) result.add(address);
  }
  return result;
}

/// Which saved address the dialog should open with: the customer's own default,
/// falling back to the first one on file when none is marked.
///
/// Takes only the addresses that are actually visible in the dialog, so the
/// value chosen here can never be one the dropdown cannot display — which is
/// what would leave the field showing its hint while state believed something
/// was selected.
UserAddress? defaultSavedAddress(List<UserAddress> visible) {
  if (visible.isEmpty) return null;
  return visible.firstWhere((address) => address.isDefault,
      orElse: () => visible.first);
}

/// The saved-address choice: a field that shows the current pick and opens a
/// list of every saved address.
///
/// This is deliberately *not* a `DropdownButtonFormField`. That widget pins its
/// collapsed button to exactly one line of text: the address was handed a tight
/// 24px height no matter how many lines `maxLines` allowed, so anything needing
/// two lines had the second one chopped off and read as half a line of sliced
/// glyphs. The height was never negotiated with the text, so no amount of
/// padding or `maxLines` on the item fixed it.
///
/// A tappable field plus a sheet has no such ceiling — the field grows to the
/// address it is showing and every row in the list wraps freely, so a long
/// address is readable both when chosen and when choosing.
class SavedAddressPickerField extends StatelessWidget {
  const SavedAddressPickerField({
    super.key,
    required this.addresses,
    required this.selected,
    required this.onSelected,
  });

  final List<UserAddress> addresses;
  final UserAddress? selected;
  final ValueChanged<UserAddress> onSelected;

  static const String fieldKey = 'saved-address-picker';

  Future<void> _openAddressList(BuildContext context) async {
    final chosen = await showModalBottomSheet<UserAddress>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => _SavedAddressListSheet(
        addresses: addresses,
        selected: selected,
      ),
    );
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addressLine = selected?.addressLine;
    final hasSelection = addressLine != null;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAddressList(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                // Three lines before it gives up. Combined with the wrapping
                // this box is free to grow, this is the full address or as much
                // of it as the field can usefully show.
                child: Text(
                  hasSelection ? addressLine : 'Saved address',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: hasSelection
                      ? theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w500,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: AppColors.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of saved addresses, shown in a sheet.
///
/// Each row is given the room its address actually needs, so a long address is
/// fully readable here instead of being trimmed to fit a one-line dropdown.
class _SavedAddressListSheet extends StatelessWidget {
  const _SavedAddressListSheet(
      {required this.addresses, required this.selected});

  final List<UserAddress> addresses;
  final UserAddress? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // The sheet never grows past the screen, however many addresses there
        // are — it scrolls instead.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderDeep,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Choose a saved address',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                itemCount: addresses.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final address = addresses[index];
                  final isSelected = address == selected;
                  return InkWell(
                    onTap: () => Navigator.pop(context, address),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: Row(
                        // Top, not centre: a multi-line address should keep its
                        // check mark beside its first line.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              address.addressLine,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocationSelectionDialog extends ConsumerStatefulWidget {
  const LocationSelectionDialog({super.key});

  @override
  ConsumerState<LocationSelectionDialog> createState() =>
      _LocationSelectionDialogState();
}

class _LocationSelectionDialogState
    extends ConsumerState<LocationSelectionDialog> {
  final _addressController = TextEditingController();
  UserAddress? _selectedSaved;
  bool _isLocating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preselectDefaultSavedAddress();
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// Preselects the default address as soon as one is known.
  ///
  /// This is the whole difference between "open the dialog, choose something,
  /// confirm" and "open the dialog, confirm". Without it the customer has to
  /// touch the dropdown on every single visit, to choose something the app
  /// already knows they chose when they marked it as their default.
  ///
  /// Runs from a listener and again after the first frame, because addresses
  /// may already be cached by the time this dialog opens — in which case the
  /// listener never fires and the post-frame pass is the only chance.
  void _preselectDefaultSavedAddress() {
    if (_selectedSaved != null) return;

    final address = _defaultFromLoadedAddresses();
    if (address == null) return;

    setState(() => _selectedSaved = address);
  }

  UserAddress? _defaultFromLoadedAddresses() {
    final addresses =
        ref.read(addressesFutureProvider).value ?? const <UserAddress>[];
    if (addresses.isEmpty) return null;
    return defaultSavedAddress(
      savedAddressesForDialog(
        addresses: addresses,
        currentAddressText: ref.read(locationProvider).address,
      ),
    );
  }

  /// Applies the choice to the app and stores it, so My Addresses and checkout
  /// both know about it immediately.
  ///
  /// A saved address is already stored, so it only needs applying. A typed or
  /// GPS-captured one is written to the `addresses` table here — previously it
  /// lived in memory only, which is why the address list stayed empty.
  Future<void> _select() async {
    final entered = _addressController.text.trim();

    // A saved address is already stored, so it only needs applying. A typed or
    // GPS-captured one is written to the `addresses` table here — previously it
    // lived in memory only, which is why the address list stayed empty.
    //
    // Falling back to the default address means Confirm is never a dead button.
    // It used to return early when the field was empty and nothing had been
    // picked, so the customer had to open the dropdown and choose before
    // confirming did anything at all — on every single visit.
    final chosen = _selectedSaved ?? _defaultFromLoadedAddresses();

    if (entered.isEmpty && chosen == null) return;
    setState(() => _isSaving = true);

    final locationNotifier = ref.read(locationProvider.notifier);

    if (chosen != null) {
      // Keep the stored pin so checkout can name the closest branch.
      locationNotifier.applySavedAddress(chosen);
    } else if (entered.isNotEmpty) {
      // setLocation geocodes first so the branch can be worked out; it stores
      // the text immediately, so the save below can rely on the text being set.
      await locationNotifier.setLocation(entered);
    }

    if (!mounted) return;
    try {
      await ref.read(saveCurrentLocationProvider)();
    } catch (_) {
      // A failed save must not block the customer from choosing where to eat.
      // The location is still applied, and the address screen can retry.
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);

    await ref.read(locationProvider.notifier).useCurrentLocation();
    if (!mounted) return;

    final location = ref.read(locationProvider);
    setState(() => _isLocating = false);

    if (location.errorMessage != null) {
      // Stay open so the customer can read the problem and type an address.
      return;
    }

    // Store the captured position straight away, the same as a typed choice, so
    // it is waiting in My Addresses and at checkout.
    if (!mounted) return;
    try {
      await ref.read(saveCurrentLocationProvider)();
    } catch (_) {
      // Not being able to store it must not stop the customer ordering.
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Opens the delivery map as a sheet over this dialog.
  ///
  /// The map does the saving itself, exactly as the GPS button does here, so
  /// whichever way the customer chooses a location the app ends up in the same
  /// state. Returning true means a location was confirmed, so this dialog has
  /// nothing left to ask and closes.
  Future<void> _openMapPicker() async {
    final picked = await showMapLocationPicker(context);
    if (!mounted) return;
    if (picked == true) Navigator.pop(context);
  }

  Future<void> _openLocationSettings() async {
    await ref.read(locationProvider.notifier).openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = ref.watch(locationProvider);
    final addresses =
        ref.watch(addressesFutureProvider).value ?? const <UserAddress>[];
    final uniqueSavedAddresses = savedAddressesForDialog(
      addresses: addresses,
      currentAddressText: location.address,
    );

    // Addresses can finish loading after this dialog opens. When they do, the
    // default gets preselected without the customer touching anything.
    ref.listen(addressesFutureProvider, (previous, next) {
      if (next.valueOrNull == null) return;
      _preselectDefaultSavedAddress();
    });

    final activeSelection = uniqueSavedAddresses.any((a) => a == _selectedSaved)
        ? uniqueSavedAddresses.firstWhere((a) => a == _selectedSaved)
        : null;

    // The dialog used to pass horizontal-only inset padding, which quietly
    // replaced the default vertical inset with zero and left no room to scroll
    // in. On a short screen the address text was squeezed into whatever was
    // left after the fixed-height buttons, so it rendered as a cut-off line.
    // The height is now measured from the actual viewport and the content
    // scrolls inside it, so a long address wraps instead of being clipped.
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.padding.vertical;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: BoxConstraints(
        maxHeight: (availableHeight - 48).clamp(280.0, double.infinity),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Set Delivery Location',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'We deliver hot & fresh across Abbottabad and Mansehra.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isLocating || _isSaving ? null : _openMapPicker,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text(
                      'Pick on map',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primaryLight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _isLocating ? null : _useCurrentLocation,
                    icon: const Icon(Icons.my_location_rounded, size: 17),
                    label: Text(
                      _isLocating ? 'Locating…' : 'Use Current Location',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (location.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    location.errorMessage!,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  if (location.settingsMustBeOpened)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openLocationSettings,
                        icon: const Icon(Icons.settings_rounded, size: 17),
                        label: const Text('Open Settings'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                ],
                if (uniqueSavedAddresses.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Expanded(child: MrFadeDivider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.textLight,
                          ),
                        ),
                      ),
                      Expanded(child: MrFadeDivider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SavedAddressPickerField(
                    key: const Key(SavedAddressPickerField.fieldKey),
                    addresses: uniqueSavedAddresses,
                    selected: activeSelection,
                    onSelected: (value) =>
                        setState(() => _selectedSaved = value),
                  ),
                ],
                // Wraps too, so a long hand-typed address is readable while it is
                // being typed rather than scrolled horizontally out of sight.
                TextField(
                  controller: _addressController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Enter address manually',
                    prefixIcon: Icon(Icons.edit_location_alt_rounded, size: 19),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: (_isSaving || _isLocating) ? null : _select,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Flexible so the label gives way on a narrow screen or
                        // at a large text scale instead of overflowing the
                        // button it sits in.
                        Flexible(
                          child: Text(
                            'Confirm Location',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward_rounded,
                            size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Say plainly that confirming stores the location, so the save is
                // not a surprise and My Addresses making sense afterwards is
                // expected rather than mysterious.
                const Text(
                  'Saved to your addresses so you can pick it again at checkout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
