import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  bool _offerNotifications = true;
  int _versionTapCount = 0;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      width: MediaQuery.of(context).size.width * 0.80,
      child: SafeArea(
        child: Column(
          children: [
            // User Header Profile Section (Upgraded Modern Card Design)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.06),
                    Colors.white,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aalyan Mughal',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '+923316290108',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            // Scrollable Tighter Menu List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  // My Wallet
                  _buildDrawerTile(
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: Colors.blueAccent,
                    title: 'My Wallet',
                    trailing: _buildBadge('Rs. 0.00', Colors.blue.shade50, Colors.blue.shade800),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/wallet');
                    },
                  ),

                  // Loyalty Points
                  _buildDrawerTile(
                    icon: Icons.stars_rounded,
                    iconColor: Colors.amber.shade800,
                    title: 'Loyalty Points',
                    trailing: _buildBadge('120 Points', Colors.amber.shade50, Colors.amber.shade900),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/loyalty');
                    },
                  ),

                  // My Addresses
                  _buildDrawerTile(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.redAccent,
                    title: 'My Addresses',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLight),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/addresses');
                    },
                  ),

                  // My Orders
                  _buildDrawerTile(
                    icon: Icons.receipt_long_rounded,
                    iconColor: Colors.deepOrangeAccent,
                    title: 'My Orders',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLight),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/my-orders');
                    },
                  ),

                  // My Favourites
                  _buildDrawerTile(
                    icon: Icons.favorite_rounded,
                    iconColor: Colors.pinkAccent,
                    title: 'My Favourites',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLight),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/favorites');
                    },
                  ),

                  // Support Center
                  _buildDrawerTile(
                    icon: Icons.headset_mic_rounded,
                    iconColor: Colors.teal,
                    title: 'Support Center',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLight),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/support');
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: AppColors.border),
                  ),

                  // Offer Notifications Switch
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.notifications_active_rounded, size: 18, color: Colors.purple),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Offer Notifications',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: _offerNotifications,
                            activeColor: AppColors.primary,
                            onChanged: (val) {
                              setState(() => _offerNotifications = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: AppColors.border),
                  ),

                  // Req Account Deletion
                  _buildDrawerTile(
                    icon: Icons.person_remove_rounded,
                    iconColor: Colors.grey.shade700,
                    title: 'Req Account Deletion',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLight),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/delete-account');
                    },
                  ),

                  // Logout
                  _buildDrawerTile(
                    icon: Icons.logout_rounded,
                    iconColor: Colors.red,
                    title: 'Logout',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/login');
                    },
                  ),

                  const SizedBox(height: 16),

                  // Social Icons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialButton(Icons.facebook, Colors.blue),
                      const SizedBox(width: 16),
                      _buildSocialButton(Icons.camera_alt_outlined, Colors.purple),
                      const SizedBox(width: 16),
                      _buildSocialButton(Icons.video_library_outlined, Colors.black87),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Footer Powered By & Secret Triple-Tap Version
                  Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_pizza_rounded, size: 14, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Powered by ',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            'Mr. Pizza',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _versionTapCount++;
                          });
                          if (_versionTapCount >= 3) {
                            _versionTapCount = 0;
                            Navigator.pop(context);
                            context.push('/rider');
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                          child: Text(
                            'Version 1.1.8+18',
                            style: TextStyle(fontSize: 10, color: AppColors.textLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildBadge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildSocialButton(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
