import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../menu/providers/menu_provider.dart';

enum PaymentMethod {
  card('Credit / Debit Card', Icons.credit_card),
  applePay('Apple Pay / Google Pay', Icons.contactless),
  safepay('Safepay Gateway', Icons.lock_outline),
  cash('Cash on Delivery', Icons.payments_outlined);

  final String title;
  final IconData icon;
  const PaymentMethod(this.title, this.icon);
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod selectedPayment = PaymentMethod.card;
  final TextEditingController promoController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  bool isPlacingOrder = false;

  @override
  void dispose() {
    promoController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Your Order & Checkout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
              },
            ),
        ],
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🍕', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  const Text(
                    'Your Cart is Empty',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Explore our menu and add your favorite pizzas!',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.go('/home');
                    },
                    child: const Text('Explore Menu'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cart Items List Card
                  const Text(
                    'Order Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...cart.items.map((cartItem) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              cartItem.item.imageUrl,
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cartItem.item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${cartItem.size.name} • ${cartItem.crust.name}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (cartItem.selectedToppings.isNotEmpty)
                                  Text(
                                    'Toppings: ${cartItem.selectedToppings.map((t) => t.name).join(', ')}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  'Rs. ${cartItem.totalPrice.toInt()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Quantity Stepper
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16),
                                  onPressed: () {
                                    ref.read(cartProvider.notifier).updateQuantity(cartItem.id, -1);
                                  },
                                ),
                                Text(
                                  '${cartItem.quantity}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16),
                                  onPressed: () {
                                    ref.read(cartProvider.notifier).updateQuantity(cartItem.id, 1);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  // Promo Code Input
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Promo / Coupon Code',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: promoController,
                                decoration: const InputDecoration(
                                  hintText: 'Enter code (e.g. MRPIZZA50)',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                final success = ref.read(cartProvider.notifier).applyPromoCode(promoController.text);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? '🎉 Promo Code Applied Successfully!'
                                          : 'Invalid promo code. Try MRPIZZA50',
                                    ),
                                    backgroundColor: success ? AppColors.success : AppColors.primary,
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                        if (cart.promoCode != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Applied "${cart.promoCode}" (${(cart.discountPercentage * 100).toInt()}% OFF)',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  ref.read(cartProvider.notifier).removePromoCode();
                                },
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Delivery Address Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.location_on, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivery Address',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                '742 Evergreen Terrace, Springfield',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              Text(
                                'ETA: ~22 Minutes',
                                style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textLight),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Payment Method Selector
                  const Text(
                    'Select Payment Method',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: PaymentMethod.values.map((method) {
                      final isSelected = selectedPayment == method;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: RadioListTile<PaymentMethod>(
                          value: method,
                          groupValue: selectedPayment,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            if (val != null) setState(() => selectedPayment = val);
                          },
                          title: Text(
                            method.title,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                          secondary: Icon(method.icon, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Summary Breakdown Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal', style: TextStyle(color: AppColors.textSecondary)),
                            Text('Rs. ${cart.subtotal.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (cart.discountAmount > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Promo Discount', style: TextStyle(color: AppColors.success)),
                              Text('-Rs. ${cart.discountAmount.toInt()}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Delivery Fee', style: TextStyle(color: AppColors.textSecondary)),
                            Text('Rs. ${cart.deliveryFee.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimated Tax (8%)', style: TextStyle(color: AppColors.textSecondary)),
                            Text('Rs. ${cart.taxAmount.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Rs. ${cart.grandTotal.toInt()}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Place Order Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isPlacingOrder
                          ? null
                          : () async {
                              setState(() => isPlacingOrder = true);
                              await Future.delayed(const Duration(milliseconds: 800));
                              if (mounted) {
                                setState(() => isPlacingOrder = false);
                                context.go('/orders/track');
                              }
                            },
                      child: isPlacingOrder
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'Place Order • Rs. ${cart.grandTotal.toInt()}',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
