import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/providers/role_provider.dart';
import '../core/routing/route_guard.dart';
import '../core/theme/neumorphic.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/loyalty/models/loyalty.dart';
import '../features/loyalty/providers/loyalty_provider.dart';
import '../features/profile/models/support_document.dart';
import '../features/profile/providers/profile_provider.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  /// True only once the startup session check has settled on a signed-in
  /// user. A signed-out visitor browses the menu as a guest, so the card shows
  /// a guest identity instead of values nobody can match to an account.
  bool get _isSignedIn {
    final state = ref.watch(authStateProvider);
    return state.isAuthenticated && !state.isLoading;
  }

  String get _displayName {
    final profile = ref.watch(profileFutureProvider).value;
    final email = ref.watch(authStateProvider).user?.email ?? '';
    final fullName = profile?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    if (email.trim().isNotEmpty) return email.split('@').first;
    return 'Guest';
  }

  String get _avatarLetter {
    final name = _displayName.trim();
    if (name.isEmpty) return 'G';
    return name[0].toUpperCase();
  }

  /// Null while signed out, so the phone row is hidden rather than inventing a
  /// number the guest never gave.
  String? get _phone {
    if (!_isSignedIn) return null;
    final phone = ref.watch(profileFutureProvider).value?.phone ?? '';
    final trimmed = phone.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _push(String path) {
    Navigator.pop(context);
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    // Read inside build, not a field initialiser: initialisers run before
    // Riverpod assigns `ref`.
    final isRider = ref.watch(roleProvider).valueOrNull == UserRole.rider;
    final phone = _phone;
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.82,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF0F3F8),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(36),
            bottomRight: Radius.circular(36),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(6, 0),
              blurRadius: 20,
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar with Close Button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // DELIVERING TO Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5EBF3),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.white,
                            offset: Offset(-2, -2),
                            blurRadius: 4,
                          ),
                          BoxShadow(
                            color: Color(0x18000000),
                            offset: Offset(2, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Text(
                        'DELIVERING TO',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFFE51926),
                        ),
                      ),
                    ),

                    // Circular Close '✕' Button
                    NeuCircleButton(
                      size: 40,
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF141923),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),

              // User Info Card Section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Row(
                  children: [
                    // Glowing Red Initial Avatar
                    Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE51926),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66E51926),
                            offset: Offset(0, 6),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _avatarLetter,
                        style: const TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF141923),
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (phone != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone_outlined,
                                  size: 14,
                                  color: Color(0xFF758295),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  phone,
                                  style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 13,
                                    color: Color(0xFF758295),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Menu Navigation Items
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (isRider) ...[
                      _buildNeuDrawerTile(
                        icon: Icons.delivery_dining_outlined,
                        title: 'My Deliveries',
                        onTap: () => _push(riderLandingLocation),
                      ),
                      _buildNeuDrawerTile(
                        icon: Icons.headphones_outlined,
                        title: 'Support Center',
                        onTap: () => _push('/support'),
                      ),
                    ] else ...[
                      // The guest sees the store front, not the account
                      // screens: loyalty, addresses and order history all
                      // live in the database behind a session, so they come
                      // back with the log-in tile instead of bouncing the
                      // guest into auth screens they did not ask for.
                      if (_isSignedIn) ...[
                        _buildNeuDrawerTile(
                          icon: Icons.star_border_rounded,
                          title: 'Loyalty Points',
                          trailing: _buildLoyaltyBadge(),
                          onTap: () => _push(loyaltyLocation),
                        ),
                        _buildNeuDrawerTile(
                          icon: Icons.location_on_outlined,
                          title: 'My Addresses',
                          onTap: () => _push(addressesLocation),
                        ),
                        _buildNeuDrawerTile(
                          icon: Icons.receipt_long_outlined,
                          title: 'My Orders',
                          onTap: () => _push(myOrdersLocation),
                        ),
                        _buildNeuDrawerTile(
                          icon: Icons.favorite_border_rounded,
                          title: 'My Favourites',
                          onTap: () => _push(favoritesLocation),
                        ),
                      ],
                      _buildNeuDrawerTile(
                        icon: Icons.headphones_outlined,
                        title: 'Support Center',
                        onTap: () => _push(supportCenterLocation),
                      ),
                      _buildNeuDrawerTile(
                        icon: Icons.feedback_outlined,
                        title: 'Terms & Privacy',
                        onTap: () => _push('$supportCenterLocation/document/'
                            '${SupportDocument.termsAndConditions.slug}'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(
                      color: Color(0xFFDDE3EC),
                      height: 1,
                      indent: 8,
                      endIndent: 8,
                    ),
                    const SizedBox(height: 10),
                    if (_isSignedIn)
                      _buildNeuDrawerTile(
                        icon: Icons.logout_rounded,
                        title: 'Logout',
                        isLogout: true,
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(authStateProvider.notifier).logout();
                        },
                      )
                    else
                      _buildNeuDrawerTile(
                        icon: Icons.login_rounded,
                        title: 'Log in',
                        isLogout: true,
                        onTap: () {
                          Navigator.pop(context);
                          context.push(loginLocation);
                        },
                      ),
                  ],
                ),
              ),

              // Footer Section: Social Icons + Logo & Version
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    // Social Circular Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuCircleButton(
                          size: 42,
                          onTap: () {},
                          child: const Icon(
                            Icons.camera_alt_outlined,
                            size: 19,
                            color: Color(0xFF141923),
                          ),
                        ),
                        const SizedBox(width: 14),
                        NeuCircleButton(
                          size: 42,
                          onTap: () {},
                          child: const Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: Color(0xFF141923),
                          ),
                        ),
                        const SizedBox(width: 14),
                        NeuCircleButton(
                          size: 42,
                          onTap: () {},
                          child: const Icon(
                            Icons.language_rounded,
                            size: 19,
                            color: Color(0xFF141923),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Cartoon Mr. Pizza Logo
                    Image.asset(
                      'assets/images/logo.png',
                      height: 42,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        'Mr. PIZZA',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF141923),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Version 1.1.8+18',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 11,
                        color: Color(0xFF758295),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeuDrawerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Soft Neumorphic Icon Container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isLogout
                        ? const Color(0xFF141923)
                        : const Color(0xFFF0F3F8),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isLogout
                        ? const [
                            BoxShadow(
                              color: Color(0x33000000),
                              offset: Offset(0, 4),
                              blurRadius: 8,
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Colors.white,
                              offset: Offset(-3, -3),
                              blurRadius: 6,
                            ),
                            BoxShadow(
                              color: Color(0x2AA6B4C9),
                              offset: Offset(3, 3),
                              blurRadius: 6,
                            ),
                          ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 20,
                    color: isLogout ? Colors.white : const Color(0xFF141923),
                  ),
                ),
                const SizedBox(width: 14),

                // Title Text
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF141923),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),

                // Optional trailing widget (the loyalty badge), else chevron
                if (trailing != null)
                  trailing
                else if (!isLogout)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFF758295),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The real points balance from the ledger — never a hardcoded number, and
  /// withheld entirely while the balance is unknown or the user is signed out.
  Widget? _buildLoyaltyBadge() {
    final balance =
        ref.watch(loyaltyBalanceProvider).valueOrNull ?? LoyaltyBalance.signedOut;
    if (!balance.isSignedIn) return null;
    final points = NumberFormat('#,##0').format(balance.balance);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0DC),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Colors.white,
            offset: Offset(-2, -2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Color(0x33A6B4C9),
            offset: Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        '$points Points',
        style: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF9A6B1F),
        ),
      ),
    );
  }
}