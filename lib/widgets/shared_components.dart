import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/location_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/widgets.dart';
import '../features/menu/models/menu_item.dart';
import '../features/menu/providers/menu_provider.dart';
import '../features/profile/models/profile.dart';
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
  final IconData? icon;
  final String text;
  final Color? color;

  const _ItemTag({this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final clr = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: clr),
          const SizedBox(width: 3),
        ],
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
                        text: item.category.label.toUpperCase(),
                        color: AppColors.textLight,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.accent),
                          const SizedBox(width: 3),
                          Text(
                            item.rating.toStringAsFixed(1),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ItemTag(
                            icon: Icons.schedule_rounded,
                            text: item.prepTime,
                          ),
                          if (item.isBestseller) ...[
                            const SizedBox(width: 10),
                            const _ItemTag(
                              text: 'Bestseller',
                              color: AppColors.primary,
                            ),
                          ],
                        ],
                      ),
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
                          item.imageUrl,
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.sand,
                              child: const Center(
                                child: Text('🍕', style: TextStyle(fontSize: 32)),
                              ),
                            );
                          },
                        ),
                      ),
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
  final ItemCategory category;
  final String bannerImageUrl;

  const CategoryHeroCard({
    super.key,
    required this.category,
    required this.bannerImageUrl,
  });

  String get categoryTagline {
    switch (category) {
      case ItemCategory.classics:
        return 'Authentic hand-crafted pizzas';
      case ItemCategory.specials:
        return 'Chef signature stuffed crusts';
      case ItemCategory.burgers:
        return 'Flame-grilled & crispy delights';
      case ItemCategory.shawarmas:
        return 'Authentic Arabian & zesty wraps';
      case ItemCategory.desserts:
        return 'Sweet molten cakes & brownies';
      case ItemCategory.deals:
        return 'Exclusive multi-item combo bundles';
      case ItemCategory.sides:
        return 'Crispy garlic knots & wings';
      case ItemCategory.drinks:
        return 'Ice-cold sodas, shakes & frozen';
    }
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldTint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      category.label.toUpperCase(),
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
                      item.imageUrl,
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
                  const SizedBox(height: 1),
                  _ItemTag(
                    text: '${item.rating.toStringAsFixed(1)} ★',
                    color: AppColors.accent,
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
                                widget.item.imageUrl,
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
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
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
                          children: widget.item.availableToppings
                              .map((topping) {
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
                                    duration:
                                        const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primaryTint
                                          : AppColors.sand,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          topping.icon,
                                          style:
                                              const TextStyle(fontSize: 13),
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
                              })
                              .toList(),
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

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _select() {
    final entered = _addressController.text.trim();
    final notifier = ref.read(locationProvider.notifier);

    if (entered.isNotEmpty) {
      notifier.setLocation(entered);
      Navigator.pop(context);
    } else if (_selectedSaved != null) {
      // Keep the stored pin so checkout can name the closest branch.
      notifier.applySavedAddress(_selectedSaved!);
      Navigator.pop(context);
    }
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
    Navigator.pop(context);
  }

  Future<void> _openLocationSettings() async {
    await ref.read(locationProvider.notifier).openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = ref.watch(locationProvider);
    final addresses = ref.watch(addressesFutureProvider).value ?? const [];
    final savedAddresses = addresses
        .where((address) => address.addressLine != location.address)
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
              if (savedAddresses.isNotEmpty) ...[
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
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: DropdownButtonFormField<UserAddress>(
                    initialValue: _selectedSaved,
                    hint: const Text('Saved address'),
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(18),
                    items: savedAddresses
                        .map(
                          (address) => DropdownMenuItem(
                            value: address,
                            child: Text(
                              address.addressLine,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _selectedSaved = value),
                  ),
                ),
              ],
              TextField(
                controller: _addressController,
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
                  onPressed: _select,
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
                      Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}