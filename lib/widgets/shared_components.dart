import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/location_provider.dart';
import '../core/theme/app_colors.dart';
import '../features/menu/models/menu_item.dart';
import '../features/menu/providers/menu_provider.dart';

/// Top Floating Toast Notification for Cart Actions (Doesn't block bottom checkout bar)
void showTopCartToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
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
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.accent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
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
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const [
                Text(
                  'Mr. Pizza',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(width: 3),
                Text('🍕', style: TextStyle(fontSize: 14)),
              ],
            ),
            if (showSlogan) ...[
              const SizedBox(height: 1),
              Text(
                'Love in Every Bite',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Customer Reviews Carousel (Clean, modern glassmorphic card design)
class CustomerReviewsSection extends StatelessWidget {
  const CustomerReviewsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final reviews = [
      {'comment': 'Super fresh & delicious pizza! Best in town.', 'author': 'Ahmed K.', 'stars': 5},
      {'comment': 'Juicy zinger burgers & crispy fries! Loved it.', 'author': 'Usama M.', 'stars': 5},
      {'comment': 'Super fast 20-min delivery & hot food.', 'author': 'Aalyan M.', 'stars': 5},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded, color: Colors.orange, size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'Customer Reviews & Ratings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 84,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final review = reviews[index];
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
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
                            (_) => const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          review['author'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      review['comment'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.2,
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

/// Ultra-Minimalist Pizza/Item Card (NO PRICES DISPLAYED)
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left Text Details (ONLY Title, No Prices)
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),

            // Right Round Pizza Image with Stacked Yellow '+' Button
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.network(
                      item.imageUrl,
                      width: 86,
                      height: 86,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 86,
                          height: 86,
                          color: AppColors.background,
                          child: const Center(
                            child: Text('🍕', style: TextStyle(fontSize: 34)),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Yellow '+' Action Button
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: GestureDetector(
                    onTap: () {
                      ref.read(cartProvider.notifier).addItem(
                            item: item,
                            size: PizzaSize.medium,
                            crust: PizzaCrust.thin,
                            toppings: [],
                            quantity: 1,
                          );
                      showTopCartToast(context, 'Added ${item.title} to cart! 🍕');
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.black,
                        size: 20,
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

/// HD Category Section Header Banner (Clean, no duplicate item inner circle)
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
        return 'Authentic Hand-Crafted Pizzas 🍕';
      case ItemCategory.specials:
        return 'Chef Signature Stuffed Crusts 🔥';
      case ItemCategory.burgers:
        return 'Flame-Grilled & Crispy Delights 🍔';
      case ItemCategory.shawarmas:
        return 'Authentic Arabian & Zesty Wraps 🌯';
      case ItemCategory.desserts:
        return 'Sweet Molten Cakes & Brownies 🍰';
      case ItemCategory.deals:
        return 'Exclusive Multi-Item Combo Bundles 🎁';
      case ItemCategory.sides:
        return 'Crispy Garlic Knots & Buffalo Wings 🍗';
      case ItemCategory.drinks:
        return 'Ice-Cold Sodas, Shakes & Margaritas 🥤';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background Cover Image
            Image.network(
              bannerImageUrl,
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: AppColors.primaryDark),
            ),

            // Gradient Overlay
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.black.withOpacity(0.50),
                    Colors.black.withOpacity(0.20),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),

            // Banner Title & Subtitle Tagline
            Positioned(
              left: 18,
              top: 0,
              bottom: 0,
              right: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        category.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.8,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    categoryTagline,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
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

/// Minimalist Grid Item Card (NO PRICES DISPLAYED)
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
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 125,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.imageUrl,
                    height: 125,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.background,
                      child: const Center(child: Text('🍰', style: TextStyle(fontSize: 36))),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () {
                    ref.read(cartProvider.notifier).addItem(
                          item: item,
                          size: PizzaSize.medium,
                          crust: PizzaCrust.thin,
                          toppings: [],
                          quantity: 1,
                        );
                    showTopCartToast(context, 'Added ${item.title} to cart! 🍰');
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Cart Floating Bottom Bar (Visible ONLY when cart is not empty)
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withOpacity(0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${cart.totalItemCount} ITEMS',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Rs. ${cart.subtotal.toInt()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              children: const [
                Text('Checkout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simplified Uncluttered Food Dressing Modal ("Next Screen")
class CustomizationBottomSheet extends StatefulWidget {
  final MenuItem item;

  const CustomizationBottomSheet({super.key, required this.item});

  @override
  State<CustomizationBottomSheet> createState() => _CustomizationBottomSheetState();
}

class _CustomizationBottomSheetState extends State<CustomizationBottomSheet> {
  late PizzaSize selectedSize;
  late PizzaCrust selectedCrust;
  late BurgerPatty selectedPatty;
  final Set<ToppingOption> selectedToppings = {};
  final TextEditingController instructionsController = TextEditingController();
  int quantity = 1;

  @override
  void initState() {
    super.initState();
    selectedSize = PizzaSize.medium;
    selectedCrust = PizzaCrust.thin;
    selectedPatty = BurgerPatty.crispyChicken;
  }

  @override
  void dispose() {
    instructionsController.dispose();
    super.dispose();
  }

  double get totalPrice {
    double price = widget.item.basePrice;
    if (widget.item.category == ItemCategory.burgers) {
      price += selectedPatty.extraPrice;
    } else {
      price = price * selectedSize.priceMultiplier + selectedCrust.extraPrice;
    }
    for (final topping in selectedToppings) {
      price += topping.price;
    }
    return price * quantity;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isBurger = item.category == ItemCategory.burgers;
    final isPizza = item.category == ItemCategory.specials ||
        item.category == ItemCategory.classics ||
        item.category == ItemCategory.deals;

    return Consumer(
      builder: (context, ref, child) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Food Cover Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          item.imageUrl,
                          width: double.infinity,
                          height: 160,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Food Title (Uncluttered: No Descriptions)
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 10),

                      // Burger Choices
                      if (isBurger) ...[
                        const Text(
                          'Patty Option',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: BurgerPatty.values.map((patty) {
                            final isSelected = selectedPatty == patty;
                            return ChoiceChip(
                              label: Text(
                                patty.extraPrice > 0
                                    ? '${patty.name} (+Rs. ${patty.extraPrice.toInt()})'
                                    : patty.name,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.background,
                              onSelected: (val) {
                                if (val) setState(() => selectedPatty = patty);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ]
                      // Pizza Choices
                      else if (isPizza) ...[
                        const Text(
                          'Select Size',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: PizzaSize.values.map((size) {
                            final isSelected = selectedSize == size;
                            return ChoiceChip(
                              label: Text(
                                size.name,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.background,
                              onSelected: (val) {
                                if (val) setState(() => selectedSize = size);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        const Text(
                          'Select Crust',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: PizzaCrust.values.map((crust) {
                            final isSelected = selectedCrust == crust;
                            return ChoiceChip(
                              label: Text(
                                crust.extraPrice > 0
                                    ? '${crust.name} (+Rs. ${crust.extraPrice.toInt()})'
                                    : crust.name,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.background,
                              onSelected: (val) {
                                if (val) setState(() => selectedCrust = crust);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Special Instructions Line
                      const Text(
                        'Special Instructions',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: instructionsController,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: 'e.g. Extra spicy, no onions...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quantity Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16),
                                  onPressed: () {
                                    if (quantity > 1) setState(() => quantity--);
                                  },
                                ),
                                Text('$quantity', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16),
                                  onPressed: () {
                                    setState(() => quantity++);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Add to Cart Action
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(cartProvider.notifier).addItem(
                            item: item,
                            size: selectedSize,
                            crust: selectedCrust,
                            toppings: selectedToppings.toList(),
                            quantity: quantity,
                            instructions: instructionsController.text.trim(),
                          );
                      Navigator.pop(context);
                      showTopCartToast(context, 'Added ${item.title} to cart! 🍕');
                    },
                    child: Text(
                      'Add to Cart • Rs. ${totalPrice.toInt()}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Location Selection Modal Dialog (GPS + Dropdown Menu + Manual Text Input)
class LocationSelectionDialog extends ConsumerStatefulWidget {
  const LocationSelectionDialog({super.key});

  @override
  ConsumerState<LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends ConsumerState<LocationSelectionDialog> {
  final List<String> abbottabadLocations = const [
    'COMSATS University, Abbottabad Campus',
    'COMSATS Abbottabad, Phase 2',
    'Supply Bazaar, Abbottabad',
    'Mandian Main Market, Abbottabad',
    'Jinnahabad, Abbottabad',
    'Pine City, Abbottabad',
    'PMA Kakul Road, Abbottabad',
    'Mansehra Road, Abbottabad',
    'Nawanshehr, Abbottabad',
    'Habibullah Colony, Abbottabad',
    'Main Bazaar, Abbottabad',
    'Civic Center, Abbottabad',
  ];

  late String selectedDropdownLocation;
  final TextEditingController customLocationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedDropdownLocation = abbottabadLocations.first;
  }

  @override
  void dispose() {
    customLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Delivery Location',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Option 1: Use Current GPS Location
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use Current GPS Location', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                ref.read(locationProvider.notifier).useCurrentLocation();
                Navigator.pop(context);
                showTopCartToast(context, '📍 Location set to Current GPS Location!');
              },
            ),

            const SizedBox(height: 16),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),

            // Option 2: Choose from Abbottabad Locations Dropdown Menu
            const Text(
              'Select Abbottabad Location Dropdown:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedDropdownLocation,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
                  items: abbottabadLocations.map((loc) {
                    return DropdownMenuItem<String>(
                      value: loc,
                      child: Text(
                        loc,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => selectedDropdownLocation = val);
                      ref.read(locationProvider.notifier).setLocation(val);
                      Navigator.pop(context);
                      showTopCartToast(context, '📍 Location set to $val!');
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),

            // Option 3: Write Custom Location Manually
            const Text(
              'Write Location Manually:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: customLocationController,
              decoration: InputDecoration(
                hintText: 'e.g. Street #4, House 12A, Supply...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textLight),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final customText = customLocationController.text.trim();
                  if (customText.isNotEmpty) {
                    final fullLoc = customText.contains('Abbottabad') ? customText : '$customText, Abbottabad';
                    ref.read(locationProvider.notifier).setLocation(fullLoc);
                    Navigator.pop(context);
                    showTopCartToast(context, '📍 Location set to $fullLoc!');
                  }
                },
                icon: const Icon(Icons.edit_location_alt_rounded, size: 16, color: AppColors.primary),
                label: const Text('Save Custom Location', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
